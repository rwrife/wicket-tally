import Foundation
import GRDB
import Testing
import WicketKit

@testable import WicketStore

@Suite("Whole database backup and restore")
struct BackupRestoreTests {
  @Test("version 1 JSON round trips every current and dynamically added table")
  func roundTripWholeDatabase() throws {
    let store = try populatedStore()
    try store.db.write { db in
      try db.create(table: "backup_extension_values") { table in
        table.column("id", .text).primaryKey()
        table.column("sequence", .integer).notNull()
        table.column("payload", .blob).notNull()
        table.column("rating", .double)
      }
      try db.execute(
        sql:
          "INSERT INTO backup_extension_values (id, sequence, payload, rating) VALUES (?, ?, ?, ?)",
        arguments: ["event-1", 1, Data([0, 1, 2, 255]), 4.5]
      )
    }

    let backup = try store.makeBackup()
    let preview = try store.previewRestore(from: backup)
    #expect(preview.formatVersion == 1)
    #expect(preview.leagueCount == 1)
    #expect(preview.teamCount == 2)
    #expect(preview.playerCount == 2)
    #expect(preview.fixtureCount == 1)
    #expect(preview.tableCounts["backup_extension_values"] == 1)

    try store.db.write { db in
      try db.execute(sql: "DELETE FROM backup_extension_values")
      try db.execute(sql: "UPDATE leagues SET name = 'Changed after backup'")
      try db.execute(sql: "DELETE FROM fixture_players")
    }

    try store.restoreBackup(from: backup, confirming: preview)

    #expect(try store.listLeagues(includeArchived: true).map(\.name) == ["Backup League"])
    #expect(try store.listFixtures().first?.participatingPlayerIDs.count == 2)
    let event: (sequence: Int, payload: Data, rating: Double)? = try store.db.read { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql: "SELECT * FROM backup_extension_values WHERE id = 'event-1'"
        )
      else {
        return nil
      }
      return (row["sequence"], row["payload"], row["rating"])
    }
    #expect(event?.sequence == 1)
    #expect(event?.payload == Data([0, 1, 2, 255]))
    #expect(event?.rating == 4.5)
  }

  @Test("preview and cancellation path never mutate live data")
  func previewIsCancelSafe() throws {
    let store = try populatedStore()
    let backup = try store.makeBackup()
    _ = try store.updateLeague(
      id: try #require(store.listLeagues(includeArchived: true).first?.id),
      name: "Keep this edit",
      kind: .league
    )

    let preview = try store.previewRestore(from: backup)
    #expect(preview.totalRecordCount > 0)
    #expect(try store.listLeagues(includeArchived: true).map(\.name) == ["Keep this edit"])
  }

  @Test("current schema round trip preserves v5 league presets and v4 scoring snapshots")
  func currentSchemaConfigurationAndScoringRoundTrip() throws {
    let store = try WicketStore.inMemory()
    let league = try store.createLeague(name: "Preset League", kind: .league)
    let home = try store.createTeam(leagueID: league.id, name: "Home", colour: .saffron)
    let away = try store.createTeam(leagueID: league.id, name: "Away", colour: .skyBlue)
    let batter = try store.createPlayer(teamID: home.id, name: "Batter", role: .batter)
    let bowler = try store.createPlayer(teamID: away.id, name: "Bowler", role: .bowler)
    let ground = try store.createGround(name: "Ground")
    let fixture = try store.createFixture(
      leagueID: league.id,
      name: "Snapshot match",
      homeTeamID: home.id,
      awayTeamID: away.id,
      groundID: ground.id,
      participatingPlayerIDs: [batter.id, bowler.id],
      startsAt: Date(timeIntervalSince1970: 1_800_000_000),
      endsAt: Date(timeIntervalSince1970: 1_800_003_600),
      reminder: .none
    )
    let preset = try RulePreset(
      name: "Gully five",
      oversPerInnings: 5,
      ballsPerOver: 5,
      playersPerSide: 6,
      maxRunsPerOver: 8,
      inningsRunCap: 50,
      runPresets: [0, 1, 2, 4, 6],
      oneHandCatchAllowed: true
    )
    try store.setRulePreset(preset, for: league.id)
    let pointsOverride = try StandingsPointsOverride(
      teamID: home.id,
      points: 5,
      reason: "Disciplinary adjustment",
      provenance: "League organiser",
      recordedAt: Date(timeIntervalSince1970: 1_800_000_500)
    )
    try store.setPointsOverride(leagueID: league.id, override: pointsOverride)
    let rules = preset.rules
    let start = MatchEvent(
      sequence: 1,
      kind: .inningsStarted(number: 1, batting: home.id, bowling: away.id)
    )
    let delivery = MatchEvent(
      sequence: 2,
      kind: .ball(
        BallEvent(
          striker: batter.id,
          nonStriker: nil,
          bowler: bowler.id,
          runsOffBat: 4
        ))
    )
    try store.appendScoringEvent(start, fixtureID: fixture.id, rules: rules)
    try store.appendScoringEvent(delivery, fixtureID: fixture.id, rules: rules)

    let backup = try store.makeBackup()
    let preview = try store.previewRestore(from: backup)
    #expect(preview.tableCounts["match_rules"] == 1)
    #expect(preview.tableCounts["match_events"] == 2)
    #expect(preview.tableCounts["standings_points_overrides"] == 1)

    try store.setRulePreset(.standard, for: league.id)
    try store.db.write { db in
      try db.execute(
        sql: "DELETE FROM match_events WHERE fixture_id = ?", arguments: [fixture.id.rawValue])
      try db.execute(
        sql: "DELETE FROM match_rules WHERE fixture_id = ?", arguments: [fixture.id.rawValue])
      try db.execute(
        sql: "DELETE FROM standings_points_overrides WHERE league_id = ?",
        arguments: [league.id.rawValue]
      )
    }

    try store.restoreBackup(from: backup, confirming: preview)

    #expect(try store.rulePreset(for: league.id) == preset)
    let restored = try store.scoringSession(fixtureID: fixture.id)
    #expect(restored.rules == rules)
    #expect(restored.rules.presetID == preset.id)
    #expect(restored.ledger.events == [start, delivery])
    #expect(try store.listPointsOverrides(leagueID: league.id) == [pointsOverride])
  }

  @Test("version N backup restores forward into nullable schema additions")
  func schemaForwardRestore() throws {
    let store = try populatedStore()
    let backup = try store.makeBackup()
    let preview = try store.previewRestore(from: backup)

    try store.db.write { db in
      try db.alter(table: "leagues") { table in
        table.add(column: "future_note", .text)
      }
      try db.execute(sql: "UPDATE leagues SET name = 'Changed', future_note = 'new schema'")
    }

    try store.restoreBackup(from: backup, confirming: preview)

    #expect(try store.listLeagues(includeArchived: true).map(\.name) == ["Backup League"])
    let note = try store.db.read { db in
      try String.fetchOne(db, sql: "SELECT future_note FROM leagues")
    }
    #expect(note == nil)
  }

  @Test("backup with unknown schema rejects atomically")
  func incompatibleSchemaIsAtomic() throws {
    let store = try populatedStore()
    try store.db.write { db in
      try db.create(table: "future_required_records") { table in
        table.column("id", .text).primaryKey()
      }
      try db.execute(sql: "INSERT INTO future_required_records (id) VALUES ('from-backup')")
    }
    let backup = try store.makeBackup()
    let preview = try store.previewRestore(from: backup)

    try store.db.write { db in
      try db.drop(table: "future_required_records")
      try db.execute(sql: "UPDATE leagues SET name = 'Still live'")
    }

    #expect(throws: WicketBackupError.incompatibleSchema) {
      try store.restoreBackup(from: backup, confirming: preview)
    }
    #expect(try store.listLeagues(includeArchived: true).map(\.name) == ["Still live"])
  }

  @Test("version 1 fixture rejects unsupported future versions without mutation")
  func versionedFixtureValidation() throws {
    let store = try populatedStore()
    let backup = try store.makeBackup()
    let fixture = String(decoding: backup, as: UTF8.self)
      .replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 99")

    #expect(throws: WicketBackupError.unsupportedVersion(99)) {
      try store.previewRestore(from: Data(fixture.utf8))
    }
    #expect(try store.listLeagues(includeArchived: true).count == 1)
  }

  @Test("version 1 JSON restores records migrated from the checked-in database fixture")
  func versionOneFixtureRestore() throws {
    let fixture = try #require(
      Bundle.module.url(forResource: "wicket-store-v1", withExtension: "sqlite"))
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent("wicket-backup-fixture-\(UUID().uuidString).sqlite")
    try FileManager.default.copyItem(at: fixture, to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let source = try WicketStore.open(at: temporary)
    let backup = try source.makeBackup()
    let target = try WicketStore.inMemory()
    _ = try target.createLeague(name: "Replaced", kind: .league)

    let preview = try target.previewRestore(from: backup)
    #expect(preview.formatVersion == 1)
    try target.restoreBackup(from: backup, confirming: preview)

    #expect(try target.listLeagues(includeArchived: true).map(\.name) == ["Sunday Gully Cup"])
    let league = try #require(target.listLeagues(includeArchived: true).first)
    let team = try #require(target.listTeams(leagueID: league.id, includeArchived: true).first)
    #expect(
      try target.listPlayers(teamID: team.id, includeArchived: true).map(\.name) == ["Asha Rao"])
  }

  @Test("CSV exports remain line-oriented and quote messaging-hostile text")
  func csvReadability() throws {
    let store = try WicketStore.inMemory()
    let league = try store.createLeague(name: "Cup, Season \"One\"", kind: .tournament)
    let home = try store.createTeam(
      leagueID: league.id, name: "Line\nBreak XI", colour: .saffron)
    let away = try store.createTeam(leagueID: league.id, name: "Away XI", colour: .skyBlue)
    let batter = try store.createPlayer(teamID: home.id, name: "Asha, Rao", role: .allRounder)
    let bowler = try store.createPlayer(teamID: away.id, name: "Dev", role: .bowler)
    let ground = try store.createGround(name: "Ground")
    let fixture = try store.createFixture(
      leagueID: league.id,
      name: "Cut-over match",
      homeTeamID: home.id,
      awayTeamID: away.id,
      groundID: ground.id,
      participatingPlayerIDs: [batter.id, bowler.id],
      startsAt: Date(timeIntervalSince1970: 1_800_000_000),
      endsAt: Date(timeIntervalSince1970: 1_800_003_600),
      reminder: .none
    )
    let preset = try RulePreset(
      name: "Five-run overs",
      oversPerInnings: 2,
      playersPerSide: 2,
      maxRunsPerOver: 5
    )
    let rules = preset.rules
    let overrideDate = Date(timeIntervalSince1970: 1_800_000_123)
    try store.setPointsOverride(
      leagueID: league.id,
      override: try StandingsPointsOverride(
        teamID: home.id,
        points: 7,
        reason: "Rain table adjustment",
        provenance: "League organiser",
        recordedAt: overrideDate
      )
    )
    try store.appendScoringEvent(
      MatchEvent(
        sequence: 1,
        kind: .inningsStarted(number: 1, batting: home.id, bowling: away.id)
      ),
      fixtureID: fixture.id,
      rules: rules
    )
    try store.appendScoringEvent(
      MatchEvent(
        sequence: 2,
        kind: .ball(
          BallEvent(
            striker: batter.id,
            nonStriker: nil,
            bowler: bowler.id,
            runsOffBat: 6,
            wicket: WicketEvent(
              kind: .caught,
              dismissed: batter.id,
              fielder: bowler.id,
              isOneHandCatch: true
            )
          ))
      ),
      fixtureID: fixture.id,
      rules: rules
    )

    let scorecards = String(decoding: try store.makeCSV(.scorecards), as: UTF8.self)
    let standings = String(decoding: try store.makeCSV(.standings), as: UTF8.self)
    let stats = String(decoding: try store.makeCSV(.playerStats), as: UTF8.self)

    #expect(scorecards.contains("# match: Cut-over match"))
    #expect(scorecards.contains("1,\"Line\nBreak XI\",6/0,1.0"))
    #expect(
      scorecards.contains(
        "\"Asha, Rao\",6,1,0,1,600.00,,not dismissed (partial),,,"))
    #expect(scorecards.contains("innings,wides,no_balls,byes,leg_byes,penalties,total_extras"))
    #expect(scorecards.contains("innings,wicket,runs,overs,dismissed,kind"))
    #expect(scorecards.contains("innings,runs_delta,wickets_delta,reason,provenance"))
    #expect(scorecards.contains("nrr_unavailable_reason"))
    #expect(scorecards.contains("detail_line,text"))
    #expect(scorecards.contains("Extras:"))
    #expect(standings.contains("# standings: Cup, Season \"One\""))
    #expect(standings.contains("\"Line\nBreak XI\""))
    #expect(standings.contains("override_reason,override_provenance,override_recorded_at"))
    #expect(standings.contains("7,Manual points override,Rain table adjustment,League organiser"))
    #expect(standings.contains(ISO8601DateFormatter().string(from: overrideDate)))
    #expect(stats.contains("# player stats: Cup, Season \"One\""))
    #expect(stats.contains("\"Asha, Rao\""))
    #expect(stats.contains("dismissals,balls_faced,average,strike_rate"))
    #expect(stats.contains("unknown"))
  }

  private func populatedStore() throws -> WicketStore {
    let store = try WicketStore.inMemory()
    let league = try store.createLeague(name: "Backup League", kind: .league)
    let home = try store.createTeam(leagueID: league.id, name: "Home XI", colour: .saffron)
    let away = try store.createTeam(leagueID: league.id, name: "Away XI", colour: .skyBlue)
    let homePlayer = try store.createPlayer(teamID: home.id, name: "Asha", role: .batter)
    let awayPlayer = try store.createPlayer(teamID: away.id, name: "Dev", role: .bowler)
    let ground = try store.createGround(name: "Maidan")
    _ = try store.createFixture(
      leagueID: league.id,
      name: "Final",
      homeTeamID: home.id,
      awayTeamID: away.id,
      groundID: ground.id,
      participatingPlayerIDs: [homePlayer.id, awayPlayer.id],
      startsAt: Date(timeIntervalSince1970: 1_800_000_000),
      endsAt: Date(timeIntervalSince1970: 1_800_003_600),
      reminder: .oneHourBefore
    )
    _ = try store.setLeagueArchived(id: league.id, archived: true)
    return store
  }
}
