import Foundation
import GRDB
import WicketKit

public enum WicketBackupError: Error, Equatable, Sendable {
  case unsupportedVersion(Int)
  case invalidBackup
  case incompatibleSchema
  case confirmationStale
  case invalidWipeConfirmation
}

extension WicketBackupError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version):
      "Backup version \(version) is not supported by this version of Wicket Tally."
    case .invalidBackup:
      "The selected file is not a valid Wicket Tally backup."
    case .incompatibleSchema:
      "The backup was created with an incompatible database schema. No local data was changed."
    case .confirmationStale:
      "The data changed after the preview. Review fresh counts before trying again."
    case .invalidWipeConfirmation:
      "The typed wipe confirmation did not match."
    }
  }
}

public struct WicketBackupPreview: Equatable, Sendable {
  public let formatVersion: Int
  public let createdAt: Date
  public let tableCounts: [String: Int]
  public let contentIdentifier: String

  public var totalRecordCount: Int {
    tableCounts.values.reduce(0, +)
  }

  public var leagueCount: Int { tableCounts["leagues", default: 0] }
  public var teamCount: Int { tableCounts["teams", default: 0] }
  public var playerCount: Int { tableCounts["players", default: 0] }
  public var fixtureCount: Int { tableCounts["fixtures", default: 0] }
  public var lineupTemplateCount: Int { tableCounts["lineup_templates", default: 0] }
  public var fixtureLineupCount: Int { tableCounts["fixture_lineups", default: 0] }
}

public struct WicketWipePreview: Equatable, Sendable {
  public static let requiredConfirmation = "DELETE ALL DATA"

  public let tableCounts: [String: Int]

  public var totalRecordCount: Int {
    tableCounts.values.reduce(0, +)
  }
}

public enum WicketCSVDocument: String, CaseIterable, Sendable {
  case scorecards
  case standings
  case playerStats

  public var filename: String {
    switch self {
    case .scorecards: "wicket-tally-scorecards.csv"
    case .standings: "wicket-tally-standings.csv"
    case .playerStats: "wicket-tally-player-stats.csv"
    }
  }
}

extension WicketStore {
  public static let backupFormatVersion = 1

  public func makeBackup() throws -> Data {
    let backup = try db.read { database in
      try DatabaseBackup.capture(from: database)
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(backup)
  }

  public func previewRestore(from data: Data) throws -> WicketBackupPreview {
    let backup = try decodeBackup(data)
    return backup.preview(contentIdentifier: contentIdentifier(for: data))
  }

  public func restoreBackup(
    from data: Data,
    confirming preview: WicketBackupPreview
  ) throws {
    let backup = try decodeBackup(data)
    guard backup.preview(contentIdentifier: contentIdentifier(for: data)) == preview else {
      throw WicketBackupError.confirmationStale
    }

    try db.write { database in
      let liveSchema = try DatabaseBackup.schema(in: database)
      guard schemaCanRestore(backup.schema, into: liveSchema) else {
        throw WicketBackupError.incompatibleSchema
      }

      try database.execute(sql: "PRAGMA defer_foreign_keys = ON")
      for table in liveSchema.reversed() {
        try database.execute(sql: "DELETE FROM \(quotedIdentifier(table.name))")
      }
      for table in backup.tables {
        try restore(table, into: database)
      }
      try Self.backfillFixtureLineups(in: database)
    }
  }

  public func previewWipeAll() throws -> WicketWipePreview {
    try db.read { database in
      WicketWipePreview(tableCounts: try recordCounts(in: database))
    }
  }

  public func wipeAll(
    typedConfirmation: String,
    confirming preview: WicketWipePreview
  ) throws {
    guard typedConfirmation == WicketWipePreview.requiredConfirmation else {
      throw WicketBackupError.invalidWipeConfirmation
    }

    try db.write { database in
      let current = WicketWipePreview(tableCounts: try recordCounts(in: database))
      guard current == preview else {
        throw WicketBackupError.confirmationStale
      }

      try database.execute(sql: "PRAGMA defer_foreign_keys = ON")
      for table in try applicationTableNames(in: database).reversed() {
        try database.execute(sql: "DELETE FROM \(quotedIdentifier(table))")
      }
    }
  }

  public func makeCSV(_ document: WicketCSVDocument) throws -> Data {
    let text: String
    switch document {
    case .scorecards:
      text = try scorecardsCSV()
    case .standings:
      text = try standingsCSV()
    case .playerStats:
      text = try playerStatsCSV()
    }
    return Data(text.utf8)
  }
}

private struct DatabaseBackup: Codable {
  let formatVersion: Int
  let createdAt: Date
  let tables: [BackupTable]

  var schema: [BackupTableSchema] {
    tables.map(\.schema)
  }

  static func capture(from database: Database) throws -> DatabaseBackup {
    let schemaRows = try Row.fetchAll(
      database,
      sql: """
        SELECT name, sql
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
          AND name != 'grdb_migrations'
        ORDER BY name
        """
    )
    let tables = try schemaRows.map { row in
      let name: String = row["name"]
      let sql: String = row["sql"]
      let columns = try database.columns(in: name).map {
        BackupColumn(
          name: $0.name,
          declaredType: $0.type,
          isNotNull: $0.isNotNull,
          defaultValueSQL: $0.defaultValueSQL,
          primaryKeyIndex: $0.primaryKeyIndex
        )
      }
      let rows = try Row.fetchAll(database, sql: "SELECT * FROM \(quotedIdentifier(name))")
        .map { row in
          columns.map { BackupValue(databaseValue: row[$0.name] as DatabaseValue) }
        }
      return BackupTable(name: name, creationSQL: sql, columns: columns, rows: rows)
    }
    return DatabaseBackup(
      formatVersion: WicketStore.backupFormatVersion,
      createdAt: Date(),
      tables: tables
    )
  }

  static func schema(in database: Database) throws -> [BackupTableSchema] {
    try Row.fetchAll(
      database,
      sql: """
        SELECT name, sql
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
          AND name != 'grdb_migrations'
        ORDER BY name
        """
    ).map { row in
      let name: String = row["name"]
      let sql: String = row["sql"]
      let columns = try database.columns(in: name).map {
        BackupColumn(
          name: $0.name,
          declaredType: $0.type,
          isNotNull: $0.isNotNull,
          defaultValueSQL: $0.defaultValueSQL,
          primaryKeyIndex: $0.primaryKeyIndex
        )
      }
      return BackupTableSchema(name: name, creationSQL: sql, columns: columns)
    }
  }

  func preview(contentIdentifier: String) -> WicketBackupPreview {
    WicketBackupPreview(
      formatVersion: formatVersion,
      createdAt: createdAt,
      tableCounts: Dictionary(uniqueKeysWithValues: tables.map { ($0.name, $0.rows.count) }),
      contentIdentifier: contentIdentifier
    )
  }
}

private struct BackupTable: Codable {
  let name: String
  let creationSQL: String
  let columns: [BackupColumn]
  let rows: [[BackupValue]]

  var schema: BackupTableSchema {
    BackupTableSchema(name: name, creationSQL: creationSQL, columns: columns)
  }
}

private struct BackupTableSchema: Codable, Equatable {
  let name: String
  let creationSQL: String
  let columns: [BackupColumn]
}

private struct BackupColumn: Codable, Equatable {
  let name: String
  let declaredType: String
  let isNotNull: Bool
  let defaultValueSQL: String?
  let primaryKeyIndex: Int
}

private enum BackupValue: Codable {
  case null
  case integer(Int64)
  case real(Double)
  case text(String)
  case blob(Data)

  private enum CodingKeys: String, CodingKey {
    case type
    case value
  }

  private enum ValueType: String, Codable {
    case null
    case integer
    case real
    case text
    case blob
  }

  init(databaseValue: DatabaseValue) {
    switch databaseValue.storage {
    case .null:
      self = .null
    case .int64(let value):
      self = .integer(value)
    case .double(let value):
      self = .real(value)
    case .string(let value):
      self = .text(value)
    case .blob(let value):
      self = .blob(value)
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(ValueType.self, forKey: .type) {
    case .null:
      self = .null
    case .integer:
      self = .integer(try container.decode(Int64.self, forKey: .value))
    case .real:
      self = .real(try container.decode(Double.self, forKey: .value))
    case .text:
      self = .text(try container.decode(String.self, forKey: .value))
    case .blob:
      self = .blob(try container.decode(Data.self, forKey: .value))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .null:
      try container.encode(ValueType.null, forKey: .type)
    case .integer(let value):
      try container.encode(ValueType.integer, forKey: .type)
      try container.encode(value, forKey: .value)
    case .real(let value):
      try container.encode(ValueType.real, forKey: .type)
      try container.encode(value, forKey: .value)
    case .text(let value):
      try container.encode(ValueType.text, forKey: .type)
      try container.encode(value, forKey: .value)
    case .blob(let value):
      try container.encode(ValueType.blob, forKey: .type)
      try container.encode(value, forKey: .value)
    }
  }

  var databaseValue: DatabaseValue {
    switch self {
    case .null: .null
    case .integer(let value): value.databaseValue
    case .real(let value): value.databaseValue
    case .text(let value): value.databaseValue
    case .blob(let value): value.databaseValue
    }
  }
}

extension WicketStore {
  fileprivate func decodeBackup(_ data: Data) throws -> DatabaseBackup {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let backup: DatabaseBackup
    do {
      backup = try decoder.decode(DatabaseBackup.self, from: data)
    } catch {
      throw WicketBackupError.invalidBackup
    }

    guard backup.formatVersion == Self.backupFormatVersion else {
      throw WicketBackupError.unsupportedVersion(backup.formatVersion)
    }
    let names = backup.tables.map(\.name)
    guard Set(names).count == names.count,
      names == names.sorted(),
      backup.tables.allSatisfy({ table in
        !table.name.isEmpty
          && !table.name.lowercased().hasPrefix("sqlite_")
          && !table.columns.isEmpty
          && Set(table.columns.map(\.name)).count == table.columns.count
          && table.rows.allSatisfy { $0.count == table.columns.count }
      })
    else {
      throw WicketBackupError.invalidBackup
    }
    return backup
  }

  fileprivate func restore(_ table: BackupTable, into database: Database) throws {
    guard !table.rows.isEmpty else { return }
    let columns = table.columns.map { quotedIdentifier($0.name) }.joined(separator: ", ")
    let placeholders = Array(repeating: "?", count: table.columns.count).joined(separator: ", ")
    let sql = "INSERT INTO \(quotedIdentifier(table.name)) (\(columns)) VALUES (\(placeholders))"
    let statement = try database.makeStatement(sql: sql)
    for row in table.rows {
      try statement.execute(arguments: StatementArguments(row.map(\.databaseValue)))
    }
  }

  fileprivate func schemaCanRestore(
    _ backupSchema: [BackupTableSchema],
    into liveSchema: [BackupTableSchema]
  ) -> Bool {
    let liveTables = Dictionary(uniqueKeysWithValues: liveSchema.map { ($0.name, $0) })
    for backupTable in backupSchema {
      guard let liveTable = liveTables[backupTable.name] else { return false }
      let backupColumns = Dictionary(
        uniqueKeysWithValues: backupTable.columns.map { ($0.name, $0) })
      let liveColumns = Dictionary(uniqueKeysWithValues: liveTable.columns.map { ($0.name, $0) })
      for backupColumn in backupTable.columns {
        guard liveColumns[backupColumn.name] == backupColumn else { return false }
      }
      for liveColumn in liveTable.columns where backupColumns[liveColumn.name] == nil {
        guard !liveColumn.isNotNull || liveColumn.defaultValueSQL != nil else { return false }
      }
    }
    return true
  }

  fileprivate func recordCounts(in database: Database) throws -> [String: Int] {
    let pairs = try applicationTableNames(in: database).map { table in
      let count =
        try Int.fetchOne(
          database,
          sql: "SELECT COUNT(*) FROM \(quotedIdentifier(table))"
        ) ?? 0
      return (table, count)
    }
    return Dictionary(uniqueKeysWithValues: pairs)
  }

  fileprivate func applicationTableNames(in database: Database) throws -> [String] {
    try String.fetchAll(
      database,
      sql: """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
          AND name != 'grdb_migrations'
        ORDER BY name
        """
    )
  }

  fileprivate func scorecardsCSV() throws -> String {
    let context = try csvContext()
    let projections = try csvProjections(context: context, includeStandaloneFixtures: true)
    return projections.flatMap { projection in
      projection.stats.scorecards.keys
        .sorted { $0.rawValue < $1.rawValue }
        .compactMap { fixtureID -> (FixtureRecord, MatchScorecard)? in
          guard let fixture = projection.fixtures.first(where: { $0.id == fixtureID }),
            let card = projection.stats.scorecards[fixtureID]
          else { return nil }
          return (fixture, card)
        }
    }.map { fixture, card in
      var lines = [
        "# match: \(fixture.name)",
        "fixture_id,result",
        csvRow([fixture.id.rawValue, resultText(card, teamNames: context.teamNames)]),
        "",
        "innings,team,score,overs",
      ]
      lines += card.innings.map { innings in
        return csvRow([
          String(innings.state.number),
          context.teamNames[innings.state.battingTeam] ?? innings.state.battingTeam.rawValue,
          innings.state.scoreline,
          innings.state.oversString(ballsPerOver: card.rules.ballsPerOver),
        ])
      }
      lines += [
        "",
        "innings,batter,runs,balls,fours,sixes,strike_rate,dismissal_kind,dismissed_status,fielder,one_hand_catch,dismissal_bowler",
      ]
      for innings in card.innings {
        lines += innings.batting.map { batter in
          let dismissalStatus: String
          if let dismissal = batter.dismissal {
            dismissalStatus = dismissal.kind.rawValue
          } else if card.result != nil, innings.state.isComplete {
            dismissalStatus = "not out"
          } else {
            dismissalStatus = "not dismissed (partial)"
          }
          return csvRow([
            String(innings.state.number),
            playerName(batter.playerID, names: context.playerNames),
            String(batter.runs),
            String(batter.balls),
            String(batter.fours),
            String(batter.sixes),
            rateText(batter.strikeRate),
            batter.dismissal?.kind.rawValue ?? "",
            dismissalStatus,
            playerNameOrBlank(batter.dismissal?.fielder, names: context.playerNames),
            batter.dismissal.map { String($0.isOneHandCatch) } ?? "",
            playerNameOrBlank(batter.dismissalBowler, names: context.playerNames),
          ])
        }
      }
      lines += ["", "innings,bowler,legal_deliveries,overs,maidens,runs,wickets,economy"]
      for innings in card.innings {
        lines += innings.bowling.map { bowler in
          csvRow([
            String(innings.state.number),
            playerName(bowler.playerID, names: context.playerNames),
            String(bowler.legalDeliveries),
            bowler.overs,
            String(bowler.maidens),
            String(bowler.runs),
            String(bowler.wickets),
            rateText(bowler.economy),
          ])
        }
      }
      lines += ["", "innings,wides,no_balls,byes,leg_byes,penalties,total_extras"]
      lines += card.innings.map { innings in
        csvRow([
          String(innings.state.number),
          String(innings.extras.wides),
          String(innings.extras.noBalls),
          String(innings.extras.byes),
          String(innings.extras.legByes),
          String(innings.extras.penalties),
          String(innings.extras.total),
        ])
      }
      lines += ["", "innings,wicket,runs,overs,dismissed,kind"]
      for innings in card.innings {
        lines += innings.fallOfWickets.map { fall in
          csvRow([
            String(innings.state.number),
            String(fall.wicket),
            String(fall.runs),
            fall.overs,
            playerName(fall.dismissed, names: context.playerNames),
            fall.kind.rawValue,
          ])
        }
      }
      lines += ["", "innings,runs_delta,wickets_delta,reason,provenance"]
      for innings in card.innings {
        lines += innings.adjustments.compactMap { correction in
          guard case .scoreAdjustment(let delta) = correction.action else { return nil }
          return csvRow([
            String(innings.state.number),
            String(delta.runsDelta),
            String(delta.wicketsDelta),
            correction.reason,
            correction.provenance,
          ])
        }
      }
      lines += [
        "",
        "metadata,value",
        csvRow(["nrr_unavailable_reason", card.nrrUnavailableReason ?? ""]),
      ]
      lines += card.warnings.map { csvRow(["warning", $0]) }
      lines += ["", "detail_line,text"]
      let detail = card.plainText(
        title: fixture.name,
        teamNames: context.teamNames,
        playerNames: context.playerNames
      )
      lines += detail.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
        .map { index, line in csvRow([String(index + 1), String(line)]) }
      return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
  }

  fileprivate func standingsCSV() throws -> String {
    let context = try csvContext()
    let projections = try csvProjections(context: context)
    return projections.map { projection in
      var lines = [
        "# standings: \(projection.league.name)",
        "team,played,won,lost,tied,derived_points,points,points_label,override_reason,override_provenance,override_recorded_at,net_run_rate,unresolved_fixtures,nrr_note",
      ]
      lines += projection.stats.standings.map { row in
        let override = row.pointsOverride
        return csvRow([
          context.teamNames[row.teamID] ?? row.teamID.rawValue,
          numericText(row.played),
          numericText(row.won),
          numericText(row.lost),
          numericText(row.tied),
          numericText(row.derivedPoints),
          numericText(row.points),
          row.pointsLabel,
          override?.reason ?? "",
          override?.provenance ?? "",
          override.map { iso8601String($0.recordedAt) } ?? "",
          rateText(row.netRunRate),
          row.unresolvedFixtures.map(\.rawValue).joined(separator: " | "),
          row.nrrUnavailableReason ?? "",
        ])
      }
      return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
  }

  fileprivate func playerStatsCSV() throws -> String {
    let context = try csvContext()
    let projections = try csvProjections(context: context)
    return projections.map { projection in
      var lines = [
        "# player stats: \(projection.league.name)",
        "player,batting_innings,runs,highest_score,dismissals,balls_faced,average,strike_rate,bowling_overs,bowling_legal_deliveries,maidens,runs_conceded,wickets,economy,availability_note",
      ]
      lines += projection.stats.players.map { player in
        csvRow([
          context.playerNames[player.playerID] ?? player.playerID.rawValue,
          numericText(player.battingInnings),
          numericText(player.runs),
          numericText(player.highestScore),
          numericText(player.dismissals),
          numericText(player.ballsFaced),
          rateText(player.average),
          rateText(player.strikeRate),
          player.bowlingOvers.rendered,
          numericText(player.bowlingLegalDeliveries),
          numericText(player.maidens),
          numericText(player.runsConceded),
          numericText(player.wickets),
          rateText(player.economy),
          [player.battingUnavailableReason, player.bowlingUnavailableReason]
            .compactMap { $0 }
            .joined(separator: " "),
        ])
      }
      return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
  }

  fileprivate func csvContext() throws -> CSVContext {
    // includeQuickGames: true so ad-hoc team names still resolve in the
    // standalone-match scorecard sections below; the container league is
    // filtered out of the per-league projections in `csvProjections`.
    let leagues = try listLeagues(includeArchived: true, includeQuickGames: true)
    let teams = try leagues.flatMap { try listTeams(leagueID: $0.id, includeArchived: true) }
    let players = try teams.flatMap { try listPlayers(teamID: $0.id, includeArchived: true) }
    return CSVContext(
      leagues: leagues,
      teams: teams,
      players: players,
      fixtures: try listFixtures(),
      teamNames: Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.name) }),
      playerNames: Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.name) })
    )
  }

  fileprivate func statsFixture(_ fixture: FixtureRecord) throws -> StatsFixture {
    let session = try scoringSession(fixtureID: fixture.id)
    return StatsFixture(
      id: fixture.id,
      homeTeamID: fixture.homeTeamID,
      awayTeamID: fixture.awayTeamID,
      rules: session.rules,
      ledger: session.ledger,
      playerIDs: fixture.participatingPlayerIDs
    )
  }

  fileprivate func csvProjections(
    context: CSVContext,
    includeStandaloneFixtures: Bool = false
  ) throws -> [CSVProjection] {
    // The hidden quick-games container never projects as a standings/stats
    // table (issue #16): impromptu matches are standalone fixtures and
    // surface as standalone scorecards instead.
    var projections = try context.leagues
      .filter { $0.id != WicketStore.quickGamesLeagueID }
      .map { league in
      let teams = context.teams.filter { $0.leagueID == league.id }
      let teamIDs = Set(teams.map(\.id))
      let players = context.players.filter { teamIDs.contains($0.teamID) }
      let fixtures = context.fixtures.filter { $0.leagueID == league.id }
      let stats = try StatsDerivation.derive(
        fixtures: try fixtures.map(statsFixture),
        teamIDs: Array(teamIDs),
        playerIDs: players.map(\.id),
        manualPoints: try listPointsOverrides(leagueID: league.id)
      )
      return CSVProjection(league: league, fixtures: fixtures, stats: stats)
    }

    if includeStandaloneFixtures {
      for fixture in context.fixtures
      where fixture.leagueID == nil {
        let standaloneLeague = LeagueRecord(
          id: LeagueID("standalone-\(fixture.id.rawValue)"),
          name: "Standalone matches",
          kind: .tournament,
          createdAt: fixture.createdAt,
          updatedAt: fixture.updatedAt
        )
        let stats = try StatsDerivation.derive(
          fixtures: [try statsFixture(fixture)],
          teamIDs: [fixture.homeTeamID, fixture.awayTeamID],
          playerIDs: Array(fixture.participatingPlayerIDs)
        )
        projections.append(
          CSVProjection(league: standaloneLeague, fixtures: [fixture], stats: stats))
      }
    }
    return projections
  }

  fileprivate func contentIdentifier(for data: Data) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}

private struct CSVContext {
  let leagues: [LeagueRecord]
  let teams: [TeamRecord]
  let players: [PlayerRecord]
  let fixtures: [FixtureRecord]
  let teamNames: [TeamID: String]
  let playerNames: [PlayerID: String]
}

private struct CSVProjection {
  let league: LeagueRecord
  let fixtures: [FixtureRecord]
  let stats: LeagueStats
}

private func csvRow(_ values: [String]) -> String {
  values.map(csvEscaped).joined(separator: ",")
}

private func numericText(_ value: NumericValue) -> String {
  switch value {
  case .known(let number):
    number.rounded() == number ? String(Int(number)) : String(format: "%.2f", number)
  case .unknown:
    "unknown"
  }
}

private func rateText(_ value: NumericValue) -> String {
  UnknownSafeFormatter.rateString(value)
}

private func iso8601String(_ date: Date) -> String {
  ISO8601DateFormatter().string(from: date)
}

private func playerName(_ id: PlayerID?, names: [PlayerID: String]) -> String {
  guard let id else { return "Unknown player" }
  return names[id] ?? id.rawValue
}

private func playerNameOrBlank(_ id: PlayerID?, names: [PlayerID: String]) -> String {
  guard let id else { return "" }
  return names[id] ?? id.rawValue
}

private func resultText(_ card: MatchScorecard, teamNames: [TeamID: String]) -> String {
  guard let result = card.result else {
    return "Unknown - \(card.resultUnavailableReason ?? "incomplete match")"
  }
  switch result {
  case .wonByRuns(let team, let runs):
    return "\(teamNames[team] ?? team.rawValue) won by \(runs) runs"
  case .wonByWickets(let team, let wickets):
    return "\(teamNames[team] ?? team.rawValue) won by \(wickets) wickets"
  case .tie:
    return "Tie"
  case .noResult(let reason):
    return "No result - \(reason)"
  }
}

private func quotedIdentifier(_ identifier: String) -> String {
  "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
}

private func csvEscaped(_ value: String) -> String {
  guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
  else {
    return value
  }
  return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}
