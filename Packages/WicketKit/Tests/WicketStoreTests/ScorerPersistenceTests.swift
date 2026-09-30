import Foundation
import Testing
import WicketKit
@testable import WicketStore

@Suite("Persisted scorer ledger")
struct ScorerPersistenceTests {
    @Test("partial over resumes with exact rules and event order")
    func partialOverResume() throws {
        let setup = try makeFixture()
        let rules = MatchRules(oversPerInnings: 10)
        try setup.store.setMatchRules(rules, fixtureID: setup.fixture.id)

        let events = [
            MatchEvent(
                sequence: 1,
                kind: .toss(winner: setup.home.id, decision: .bat)
            ),
            MatchEvent(
                sequence: 2,
                kind: .inningsStarted(number: 1, batting: setup.home.id, bowling: setup.away.id)
            ),
            MatchEvent(
                sequence: 3,
                kind: .ball(
                    BallEvent(
                        striker: nil,
                        nonStriker: nil,
                        bowler: nil,
                        runsOffBat: 4
                    )
                )
            ),
            MatchEvent(
                sequence: 4,
                kind: .ball(
                    BallEvent(
                        striker: nil,
                        nonStriker: nil,
                        bowler: nil,
                        runsOffBat: 0,
                        extra: ExtraEvent(kind: .wide, runs: 1)
                    )
                )
            ),
        ]
        for event in events {
            try setup.store.appendScoringEvent(event, fixtureID: setup.fixture.id, rules: rules)
        }

        let resumed = try setup.store.scoringSession(fixtureID: setup.fixture.id)
        let state = resumed.ledger.replay(rules: resumed.rules)

        #expect(resumed.rules == rules)
        #expect(resumed.ledger.events == events)
        #expect(state.innings.first?.runs == 5)
        #expect(state.innings.first?.legalDeliveries == 1)
        #expect(state.scorecard.first?.overs == "0.1")
    }

    @Test("undo and redo persist as later replacement corrections")
    func appendOnlyUndoRedo() throws {
        let setup = try makeFixture()
        let rules = MatchRules(oversPerInnings: 10)
        let start = MatchEvent(
            sequence: 1,
            kind: .inningsStarted(number: 1, batting: setup.home.id, bowling: setup.away.id)
        )
        let boundary = MatchEvent(
            sequence: 2,
            kind: .ball(
                BallEvent(striker: nil, nonStriker: nil, bowler: nil, runsOffBat: 4)
            )
        )
        let neutral = MatchEventKind.penaltyRuns(
            PenaltyRunEvent(awardedToBatting: false, runs: 0, reason: "wicket-tally undo no-op")
        )
        let undo = MatchEvent(
            sequence: 3,
            kind: .correction(
                CorrectionEvent(
                    action: .replace(target: boundary.id, with: neutral),
                    reason: "scorer undo",
                    provenance: "wicket-tally-scorer"
                )
            )
        )
        let redo = MatchEvent(
            sequence: 4,
            kind: .correction(
                CorrectionEvent(
                    action: .replace(target: boundary.id, with: boundary.kind),
                    reason: "scorer redo",
                    provenance: "wicket-tally-scorer"
                )
            )
        )

        for event in [start, boundary, undo] {
            try setup.store.appendScoringEvent(event, fixtureID: setup.fixture.id, rules: rules)
        }
        var resumed = try setup.store.scoringSession(fixtureID: setup.fixture.id)
        #expect(resumed.ledger.events.count == 3)
        #expect(resumed.ledger.replay(rules: rules).innings.first?.runs == 0)
        #expect(resumed.ledger.replay(rules: rules).innings.first?.legalDeliveries == 0)

        try setup.store.appendScoringEvent(redo, fixtureID: setup.fixture.id, rules: rules)
        resumed = try setup.store.scoringSession(fixtureID: setup.fixture.id)
        #expect(resumed.ledger.events.count == 4)
        #expect(resumed.ledger.replay(rules: rules).innings.first?.runs == 4)
        #expect(resumed.ledger.replay(rules: rules).innings.first?.legalDeliveries == 1)
    }

    @Test("rules and sequences reject stale scorer writes")
    func conflictGuards() throws {
        let setup = try makeFixture()
        let rules = MatchRules(oversPerInnings: 10)
        let event = MatchEvent(
            sequence: 1,
            kind: .toss(winner: setup.home.id, decision: .bowl)
        )
        try setup.store.appendScoringEvent(event, fixtureID: setup.fixture.id, rules: rules)

        #expect(throws: WicketStoreError.scoringConflict) {
            try setup.store.setMatchRules(.odi, fixtureID: setup.fixture.id)
        }

        #expect(throws: WicketStoreError.scoringConflict) {
            try setup.store.appendScoringEvent(
                MatchEvent(sequence: 3, kind: .overCompleted),
                fixtureID: setup.fixture.id,
                rules: rules
            )
        }
        #expect(throws: WicketStoreError.scoringConflict) {
            try setup.store.appendScoringEvent(
                MatchEvent(sequence: 2, kind: .overCompleted),
                fixtureID: setup.fixture.id,
                rules: .odi
            )
        }
    }

    @Test("complete custom rule snapshot survives restart")
    func customRulesRoundTrip() throws {
        let setup = try makeFixture()
        let preset = try RulePreset(
            name: "Garden cut",
            oversPerInnings: 8,
            ballsPerOver: 5,
            playersPerSide: 7,
            maxRunsPerOver: 12,
            inningsRunCap: 80,
            runPresets: [0, 1, 2, 4, 6, 8],
            oneHandCatchAllowed: true
        )
        let rules = MatchRules(preset: preset)

        try setup.store.setMatchRules(rules, fixtureID: setup.fixture.id)
        let resumed = try setup.store.scoringSession(fixtureID: setup.fixture.id)

        #expect(resumed.rules == rules)
        #expect(resumed.rules.presetID == preset.id)
        #expect(resumed.rules.runPresets == [0, 1, 2, 4, 6, 8])
        #expect(resumed.rules.maxRunsPerOver == 12)
        #expect(resumed.rules.oneHandCatchAllowed)
    }

    @Test("league rule presets persist, default to standard, and reject malformed JSON")
    func leagueRulePresets() throws {
        let setup = try makeFixture()
        #expect(try setup.store.rulePreset(for: setup.league.id) == .standard)

        let preset = try RulePreset(
            name: "Beach Eights",
            oversPerInnings: 8,
            ballsPerOver: 5,
            playersPerSide: 8,
            maxRunsPerOver: 15,
            inningsRunCap: 90,
            runPresets: [0, 1, 2, 4, 6],
            oneHandCatchAllowed: true
        )
        try setup.store.setRulePreset(preset, for: setup.league.id)
        let loaded = try setup.store.rulePreset(for: setup.league.id)
        #expect(loaded == preset)

        // A match with no header yet copies the league preset...
        let session = try setup.store.scoringSession(fixtureID: setup.fixture.id)
        #expect(session.rules.presetID == preset.id)
        #expect(session.rules.ballsPerOver == 5)

        // ...but once scoring starts the snapshot is frozen against later edits.
        try setup.store.appendScoringEvent(
            MatchEvent(sequence: 1, kind: .toss(winner: setup.home.id, decision: .bat)),
            fixtureID: setup.fixture.id,
            rules: session.rules
        )
        let revised = try RulePreset(
            name: "Beach Nines",
            oversPerInnings: 9,
            ballsPerOver: 6,
            playersPerSide: 9,
            runPresets: [0, 1, 2, 4, 6]
        )
        try setup.store.setRulePreset(revised, for: setup.league.id)
        #expect(try setup.store.scoringSession(fixtureID: setup.fixture.id).rules.presetName == "Beach Eights")

        #expect(throws: WicketStoreError.recordNotFound) {
            try setup.store.rulePreset(for: LeagueID("missing-league"))
        }
    }

    @Test("corrupt league preset surfaces instead of silently defaulting")
    func malformedLeaguePreset() throws {
        let setup = try makeFixture()
        // Only SQL NULL is "unconfigured"; an empty string is corruption
        // because RulePreset can never encode to one.
        for corrupt in ["{not json", "", "null", "[]"] {
            try setup.store.db.write { database in
                try database.execute(
                    sql: "UPDATE leagues SET rule_preset_json = ? WHERE id = ?",
                    arguments: [corrupt, setup.league.id.rawValue]
                )
            }
            #expect(throws: WicketStoreError.malformedConfiguration) {
                try setup.store.rulePreset(for: setup.league.id)
            }
            #expect(throws: WicketStoreError.malformedConfiguration) {
                try setup.store.scoringSession(fixtureID: setup.fixture.id)
            }
        }

        try setup.store.db.write { database in
            try database.execute(
                sql: "UPDATE leagues SET rule_preset_json = NULL WHERE id = ?",
                arguments: [setup.league.id.rawValue]
            )
        }
        #expect(try setup.store.rulePreset(for: setup.league.id) == .standard)
    }

    @Test("manual points overrides append an audit trail and expose the latest per team")
    func pointsOverrideAudit() throws {
        let setup = try makeFixture()
        #expect(try setup.store.listPointsOverrides(leagueID: setup.league.id).isEmpty)

        let first = try StandingsPointsOverride(
            teamID: setup.home.id,
            points: 4,
            reason: "Forfeit awarded",
            provenance: "Committee",
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let revised = try StandingsPointsOverride(
            teamID: setup.home.id,
            points: 2,
            reason: "Appeal upheld",
            provenance: "Chair",
            recordedAt: Date(timeIntervalSince1970: 1_800_090_000)
        )
        let other = try StandingsPointsOverride(
            teamID: setup.away.id,
            points: -1,
            reason: "Slow over rate",
            provenance: "Umpire",
            recordedAt: Date(timeIntervalSince1970: 1_800_100_000)
        )
        try setup.store.setPointsOverride(leagueID: setup.league.id, override: first)
        try setup.store.setPointsOverride(leagueID: setup.league.id, override: revised)
        try setup.store.setPointsOverride(leagueID: setup.league.id, override: other)

        let latest = try setup.store.listPointsOverrides(leagueID: setup.league.id)
        #expect(latest.count == 2)
        #expect(latest.first(where: { $0.teamID == setup.home.id })?.points == 2)
        #expect(latest.first(where: { $0.teamID == setup.home.id })?.reason == "Appeal upheld")
        #expect(latest.first(where: { $0.teamID == setup.away.id })?.points == -1)

        // Superseded rows survive as history, including exact timestamps.
        let history = try setup.store.pointsOverrideHistory(leagueID: setup.league.id)
        #expect(history.count == 3)
        #expect(history.map(\.points) == [4, 2, -1])
        #expect(history[0].recordedAt == first.recordedAt)
        #expect(history[0].provenance == "Committee")
    }

    @Test("points overrides reject unknown leagues and foreign teams")
    func pointsOverrideGuards() throws {
        let setup = try makeFixture()
        let otherLeague = try setup.store.createLeague(name: "Other", kind: .league)
        let valid = try StandingsPointsOverride(
            teamID: setup.home.id,
            points: 3,
            reason: "Ruling",
            provenance: "Chair",
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(throws: WicketStoreError.recordNotFound) {
            try setup.store.setPointsOverride(leagueID: LeagueID("missing"), override: valid)
        }
        #expect(throws: WicketStoreError.parentNotFound) {
            try setup.store.setPointsOverride(leagueID: otherLeague.id, override: valid)
        }
        #expect(throws: WicketStoreError.recordNotFound) {
            try setup.store.listPointsOverrides(leagueID: LeagueID("missing"))
        }
        #expect(try setup.store.listPointsOverrides(leagueID: otherLeague.id).isEmpty)
    }

    @Test("corrupt stored rules surface as errors instead of silent defaults")
    func corruptRulesPayloadThrows() throws {
        let setup = try makeFixture()
        try setup.store.setMatchRules(.t20, fixtureID: setup.fixture.id)
        try setup.store.db.write { database in
            try database.execute(
                sql: "UPDATE match_rules SET rules_payload = ? WHERE fixture_id = ?",
                arguments: [Data("not a rules snapshot".utf8), setup.fixture.id.rawValue]
            )
        }
        // The standings sheet reports this rather than showing wrong numbers.
        #expect(throws: (any Error).self) {
            try setup.store.scoringSession(fixtureID: setup.fixture.id)
        }
    }

    @Test("league deletion previews the full cascade and removes every child row")
    func leagueCascadePreviewAndDeletion() throws {
        let setup = try makeFixture()
        let rules = MatchRules.t20
        try setup.store.appendScoringEvent(
            MatchEvent(sequence: 1, kind: .toss(winner: setup.home.id, decision: .bat)),
            fixtureID: setup.fixture.id,
            rules: rules
        )
        try setup.store.setPointsOverride(
            leagueID: setup.league.id,
            override: try StandingsPointsOverride(
                teamID: setup.home.id,
                points: 2,
                reason: "Committee ruling",
                provenance: "Chair",
                recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        // An unrelated league with its own scored fixture must be unaffected.
        let other = try makeFixture(in: setup.store, leagueName: "Other season")
        try setup.store.appendScoringEvent(
            MatchEvent(sequence: 1, kind: .toss(winner: other.home.id, decision: .bowl)),
            fixtureID: other.fixture.id,
            rules: rules
        )
        try setup.store.setPointsOverride(
            leagueID: other.league.id,
            override: try StandingsPointsOverride(
                teamID: other.home.id,
                points: 5,
                reason: "Bonus",
                provenance: "Committee",
                recordedAt: Date(timeIntervalSince1970: 1_800_000_500)
            )
        )

        let preview = try setup.store.previewLeagueDeletion(id: setup.league.id)
        #expect(preview.teamCount == 2)
        #expect(preview.fixtureCount == 1)
        #expect(preview.scoringEventCount == 1)
        #expect(preview.pointsOverrideCount == 1)

        // Scoring after the preview must invalidate the confirmation, or a
        // freshly scored ball could be destroyed by a stale dialog.
        try setup.store.appendScoringEvent(
            MatchEvent(
                sequence: 2,
                kind: .inningsStarted(number: 1, batting: setup.home.id, bowling: setup.away.id)
            ),
            fixtureID: setup.fixture.id,
            rules: rules
        )
        #expect(throws: WicketStoreError.confirmationStale) {
            try setup.store.deleteLeague(id: setup.league.id, confirming: preview)
        }

        let current = try setup.store.previewLeagueDeletion(id: setup.league.id)
        #expect(current.scoringEventCount == 2)
        try setup.store.deleteLeague(id: setup.league.id, confirming: current)

        #expect(try setup.store.league(id: setup.league.id) == nil)
        // Every dependent row of the deleted league is gone...
        let deletedFixtureID = setup.fixture.id.rawValue
        let deletedLeagueID = setup.league.id.rawValue
        let leftovers = try setup.store.db.read { database -> [Int] in
            [
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM match_events WHERE fixture_id = ?",
                    arguments: [deletedFixtureID]
                ) ?? -1,
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM match_rules WHERE fixture_id = ?",
                    arguments: [deletedFixtureID]
                ) ?? -1,
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM standings_points_overrides WHERE league_id = ?",
                    arguments: [deletedLeagueID]
                ) ?? -1,
            ]
        }
        #expect(leftovers == [0, 0, 0])

        // ...while an unrelated league keeps its own teams, fixture, scoring
        // ledger and points audit intact.
        #expect(try setup.store.league(id: other.league.id) != nil)
        let survivor = try setup.store.previewLeagueDeletion(id: other.league.id)
        #expect(survivor.teamCount == 2)
        #expect(survivor.fixtureCount == 1)
        #expect(survivor.scoringEventCount == 1)
        #expect(survivor.pointsOverrideCount == 1)
        #expect(try setup.store.scoringSession(fixtureID: other.fixture.id).ledger.events.count == 1)
        #expect(try setup.store.listPointsOverrides(leagueID: other.league.id).count == 1)
        #expect(try setup.store.listFixtures().map(\.id) == [other.fixture.id])
    }

    private func makeFixture(
        in existingStore: WicketStore? = nil,
        leagueName: String = "Scorer League"
    ) throws -> (
        store: WicketStore,
        fixture: FixtureRecord,
        home: TeamRecord,
        away: TeamRecord,
        league: LeagueRecord
    ) {
        let store = try existingStore ?? WicketStore.inMemory()
        let league = try store.createLeague(name: leagueName, kind: .league)
        let home = try store.createTeam(leagueID: league.id, name: "\(leagueName) Home XI", colour: .wicketGreen)
        let away = try store.createTeam(leagueID: league.id, name: "\(leagueName) Away XI", colour: .cricketRed)
        let ground = try store.createGround(name: "Park \(leagueName)")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try store.createFixture(
            leagueID: league.id,
            name: "\(leagueName) scoring fixture",
            homeTeamID: home.id,
            awayTeamID: away.id,
            groundID: ground.id,
            participatingPlayerIDs: [],
            startsAt: start,
            endsAt: start.addingTimeInterval(7_200),
            reminder: .none
        )
        return (store, fixture, home, away, league)
    }
}
