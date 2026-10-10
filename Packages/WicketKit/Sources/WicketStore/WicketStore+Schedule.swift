import Foundation
import GRDB
import WicketKit

extension WicketStore {
    /// Preview the *exact* records that will be saved. Rechecked inside the
    /// commit transaction so a concurrent edit cannot silently add a clash.
    public func previewSchedule(_ records: [FixtureRecord]) throws -> [[FixtureConflict]] {
        let existing = try listFixtures()
        return records.enumerated().map { index, candidate in
            FixtureConflictDetector.conflicts(for: candidate, among: existing + Array(records.prefix(index)))
        }
    }

    /// All-or-nothing creation. No existing fixture or match ledger is edited.
    /// The caller must confirm the conflict snapshot shown in the preview UI.
    public func commitSchedule(
        _ records: [FixtureRecord], confirmedConflicts: [[FixtureConflict]]
    ) throws {
        guard !records.isEmpty, confirmedConflicts.count == records.count else {
            throw WicketStoreError.confirmationStale
        }
        try db.write { database in
            let existingRows = try Row.fetchAll(database, sql: "SELECT * FROM fixtures")
            let existing: [FixtureRecord] = try existingRows.map { row in
                // Avoid re-entering the database queue during its write.
                let id: String = row["id"]
                let leagueString: String? = row["league_id"]
                let name: String = row["name"]
                let homeString: String = row["home_team_id"]
                let awayString: String = row["away_team_id"]
                let groundString: String = row["ground_id"]
                let starts: Int64 = row["starts_at_ms"]
                let ends: Int64 = row["ends_at_ms"]
                let reminderMinutes: Int = row["reminder_minutes"]
                let created: Int64 = row["created_at_ms"]
                let updated: Int64 = row["updated_at_ms"]
                let participants = try String.fetchAll(database, sql: "SELECT player_id FROM fixture_players WHERE fixture_id = ?", arguments: [id])
                return FixtureRecord(
                    id: FixtureID(id), leagueID: leagueString.map { LeagueID($0) },
                    name: name, homeTeamID: TeamID(homeString),
                    awayTeamID: TeamID(awayString), groundID: GroundID(groundString),
                    participatingPlayerIDs: Set(participants.map { PlayerID($0) }),
                    startsAt: Date(millisecondsSince1970: starts),
                    endsAt: Date(millisecondsSince1970: ends),
                    reminder: FixtureReminder(rawValue: reminderMinutes) ?? .none,
                    createdAt: Date(millisecondsSince1970: created),
                    updatedAt: Date(millisecondsSince1970: updated)
                )
            }
            var previous: [FixtureRecord] = []
            for (index, record) in records.enumerated() {
                guard let league = record.leagueID,
                      record.homeTeamID != record.awayTeamID,
                      record.startsAt < record.endsAt,
                      !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      record.startsAt == record.startsAt.truncatedToMilliseconds,
                      record.endsAt == record.endsAt.truncatedToMilliseconds
                else { throw WicketStoreError.invalidTimeSlot }
                let actual = FixtureConflictDetector.conflicts(for: record, among: existing + previous)
                guard actual == confirmedConflicts[index] else { throw WicketStoreError.confirmationStale }
                let already = (existing + previous).contains { other in
                    other.leagueID == league && Set([other.homeTeamID, other.awayTeamID]) == Set([record.homeTeamID, record.awayTeamID])
                }
                guard !already else { throw WicketStoreError.scheduleAlreadyExists }
                guard try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM leagues WHERE id = ?", arguments: [league.rawValue]) == 1,
                      try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM grounds WHERE id = ?", arguments: [record.groundID.rawValue]) == 1,
                      try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM teams WHERE league_id = ? AND id IN (?, ?)", arguments: [league.rawValue, record.homeTeamID.rawValue, record.awayTeamID.rawValue]) == 2
                else { throw WicketStoreError.parentNotFound }
                try database.execute(sql: """
                    INSERT INTO fixtures (id, league_id, name, home_team_id, away_team_id, ground_id,
                      starts_at_ms, ends_at_ms, reminder_minutes, created_at_ms, updated_at_ms)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [record.id.rawValue, league.rawValue, record.name,
                        record.homeTeamID.rawValue, record.awayTeamID.rawValue, record.groundID.rawValue,
                        record.startsAt.millisecondsSince1970, record.endsAt.millisecondsSince1970,
                        record.reminder.rawValue, record.createdAt.millisecondsSince1970,
                        record.updatedAt.millisecondsSince1970])
                try validateFixtureParticipants(record.participatingPlayerIDs, fixtureID: record.id, home: record.homeTeamID, away: record.awayTeamID, in: database)
                for player in record.participatingPlayerIDs {
                    try database.execute(sql: "INSERT INTO fixture_players (fixture_id, player_id) VALUES (?, ?)", arguments: [record.id.rawValue, player.rawValue])
                }
                try Self.backfillFixtureLineups(in: database)
                previous.append(record)
            }
        }
    }
}
