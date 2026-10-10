import Foundation
import Observation
import UserNotifications
import WicketKit
import WicketStore

@MainActor
@Observable
final class FixturesViewModel {
    private let store: WicketStore?
    private let notifications: LocalFixtureNotificationScheduling

    private(set) var fixtures: [FixtureRecord] = []
    private(set) var grounds: [GroundRecord] = []
    private(set) var leagues: [LeagueRecord] = []
    private(set) var teams: [TeamRecord] = []
    private(set) var players: [PlayerRecord] = []
    var errorMessage: String?

    private init(
        store: WicketStore?,
        notifications: LocalFixtureNotificationScheduling,
        startupError: String? = nil
    ) {
        self.store = store
        self.notifications = notifications
        errorMessage = startupError
        reload()
    }

    static func live() -> FixturesViewModel {
        do {
            let store = try LocalStore.open()
            return FixturesViewModel(store: store, notifications: LocalFixtureNotificationScheduler())
        } catch {
            return FixturesViewModel(
                store: nil,
                notifications: LocalFixtureNotificationScheduler(),
                startupError: "Local fixture storage could not be opened."
            )
        }
    }

    static func preview() -> FixturesViewModel {
        do {
            let store = try WicketStore.inMemory()
            let league = try store.createLeague(name: "Sunday Gully Cup", kind: .tournament)
            let home = try store.createTeam(leagueID: league.id, name: "Azad XI", colour: .saffron)
            let away = try store.createTeam(leagueID: league.id, name: "Maidan Stars", colour: .wicketGreen)
            let ground = try store.createGround(name: "Azad Maidan")
            _ = try store.createFixture(
                leagueID: league.id,
                name: "Sunday opener",
                homeTeamID: home.id,
                awayTeamID: away.id,
                groundID: ground.id,
                participatingPlayerIDs: [],
                startsAt: Date().addingTimeInterval(3_600),
                endsAt: Date().addingTimeInterval(10_800),
                reminder: .oneHourBefore
            )
            return FixturesViewModel(store: store, notifications: PreviewNotificationScheduler())
        } catch {
            return FixturesViewModel(store: nil, notifications: PreviewNotificationScheduler(), startupError: "Preview fixture could not be created.")
        }
    }

    func reload() {
        guard let store else { return }
        do {
            fixtures = try store.listFixtures()
            grounds = try store.listGrounds()
            leagues = try store.listLeagues()
            teams = try leagues.flatMap { try store.listTeams(leagueID: $0.id) }
            players = try teams.flatMap { try store.listPlayers(teamID: $0.id) }
        } catch {
            errorMessage = message(for: error)
        }
    }

    func team(_ id: TeamID) -> TeamRecord? {
        if let cached = teams.first(where: { $0.id == id }) { return cached }
        // Ad-hoc throwaway teams (issue #16) are deliberately absent from
        // the setup cache so they never appear in pickers; resolve them by
        // id so their user-entered names still render on quick-game rows.
        return try? store?.team(id: id)
    }
    func ground(_ id: GroundID) -> GroundRecord? {
        if let cached = grounds.first(where: { $0.id == id }) { return cached }
        // The hidden quick-games ground (issue #16) stays out of picker
        // lists but still resolves by id so quick-game rows show "Any
        // ground" instead of "Unknown ground".
        return try? store?.ground(id: id)
    }
    var scoringStore: WicketStore? { store }

    /// Builds league statistics from the persisted ledgers plus the stored
    /// manual-points audit. Recomputed on demand so it always reflects the
    /// latest scoring and override edits.
    func leagueStats(for leagueID: LeagueID) throws -> LeagueStats {
        let store = try requiredStore()
        let leagueFixtures = fixtures.filter { $0.leagueID == leagueID }
        let statsFixtures = try leagueFixtures.map { fixture in
            let session = try store.scoringSession(fixtureID: fixture.id)
            return StatsFixture(
                id: fixture.id,
                homeTeamID: fixture.homeTeamID,
                awayTeamID: fixture.awayTeamID,
                rules: session.rules,
                ledger: session.ledger,
                playerIDs: fixture.participatingPlayerIDs
            )
        }
        let leagueTeams = teams.filter { $0.leagueID == leagueID }.map(\.id)
        let leaguePlayers = Set(leagueFixtures.flatMap(\.participatingPlayerIDs))
        return try StatsDerivation.derive(
            fixtures: statsFixtures,
            teamIDs: leagueTeams,
            playerIDs: Array(leaguePlayers),
            manualPoints: try store.listPointsOverrides(leagueID: leagueID)
        )
    }

    func savePointsOverride(_ override: StandingsPointsOverride, leagueID: LeagueID) throws {
        try requiredStore().setPointsOverride(leagueID: leagueID, override: override)
    }

    func previewSchedule(_ records: [FixtureRecord]) throws -> [[FixtureConflict]] {
        try requiredStore().previewSchedule(records)
    }

    func commitSchedule(_ records: [FixtureRecord], confirmedConflicts: [[FixtureConflict]]) throws {
        try requiredStore().commitSchedule(records, confirmedConflicts: confirmedConflicts)
        reload()
    }

    func createGround(name: String) throws -> GroundRecord {
        let ground = try requiredStore().createGround(name: name)
        reload()
        return ground
    }

    func save(_ draft: FixtureDraft, editing existing: FixtureRecord?) async throws -> [FixtureConflict] {
        let store = try requiredStore()
        let participantIDs = Set(draft.lineups.values.flatMap(\.playerIDs))
        let now = Date()
        let candidate = FixtureRecord(
            id: existing?.id ?? FixtureID(UUID().uuidString.lowercased()),
            leagueID: draft.leagueID,
            name: draft.name,
            homeTeamID: draft.homeTeamID,
            awayTeamID: draft.awayTeamID,
            groundID: draft.groundID,
            participatingPlayerIDs: participantIDs,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            reminder: draft.reminder,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        let conflicts = try store.conflicts(for: candidate)

        let saved: FixtureRecord
        if let existing {
            saved = try store.updateFixture(
                id: existing.id,
                leagueID: draft.leagueID,
                name: draft.name,
                homeTeamID: draft.homeTeamID,
                awayTeamID: draft.awayTeamID,
                groundID: draft.groundID,
                participatingPlayerIDs: participantIDs,
                startsAt: draft.startsAt,
                endsAt: draft.endsAt,
                reminder: draft.reminder,
                lineups: draft.lineups
            )
        } else {
            saved = try store.createFixture(
                leagueID: draft.leagueID,
                name: draft.name,
                homeTeamID: draft.homeTeamID,
                awayTeamID: draft.awayTeamID,
                groundID: draft.groundID,
                participatingPlayerIDs: participantIDs,
                startsAt: draft.startsAt,
                endsAt: draft.endsAt,
                reminder: draft.reminder,
                lineups: draft.lineups
            )
        }
        try await notifications.replaceReminder(for: saved)
        reload()
        return conflicts
    }

    func delete(_ fixture: FixtureRecord) async throws {
        try requiredStore().deleteFixture(id: fixture.id)
        await notifications.removeReminder(for: fixture.id)
        reload()
    }

    /// Starts an impromptu game (issue #16): two names and an overs choice,
    /// no league/team/ground setup. The returned fixture is standalone and
    /// opens straight into the scorer.
    @discardableResult
    func startQuickGame(homeName: String, awayName: String, overs: Int) throws -> AdhocMatchStart {
        let store = try requiredStore()
        let start = try store.startAdhocMatch(
            homeName: homeName,
            awayName: awayName,
            rules: MatchRules(oversPerInnings: overs)
        )
        reload()
        return start
    }

    func report(_ error: Error) { errorMessage = message(for: error) }

    /// Standings failures are reported verbatim rather than folded into the
    /// generic fixture-save message: a derivation or store fault here means the
    /// numbers cannot be trusted, so the cause must stay visible.
    func reportStatsFailure(_ error: Error, league: String) {
        errorMessage = "Standings for \(league) could not be derived: \(error.localizedDescription)"
    }

    private func requiredStore() throws -> WicketStore {
        guard let store else { throw WicketStoreError.recordNotFound }
        return store
    }

    private func message(for error: Error) -> String {
        switch error {
        case let error as LineupError: return error.localizedDescription
        case WicketStoreError.invalidName: return "Enter a fixture or ground name."
        case WicketStoreError.invalidTimeSlot: return "The fixture must end after it starts."
        case WicketStoreError.scoringConflict: return "The teams cannot change after scoring starts. Lineup participants can still be edited."
        case WicketStoreError.invalidTeams: return "Choose two different teams."
        case WicketStoreError.parentNotFound: return "A selected league, team, ground, or player no longer exists."
        default: return "The local fixture change could not be saved."
        }
    }
}

struct FixtureDraft {
    var leagueID: LeagueID?
    var name: String
    var homeTeamID: TeamID
    var awayTeamID: TeamID
    var groundID: GroundID
    var startsAt: Date
    var endsAt: Date
    var reminder: FixtureReminder
    var lineups: [TeamID: TeamLineup] = [:]
}

@MainActor
protocol LocalFixtureNotificationScheduling {
    func replaceReminder(for fixture: FixtureRecord) async throws
    func removeReminder(for fixtureID: FixtureID) async
}

@MainActor
struct LocalFixtureNotificationScheduler: LocalFixtureNotificationScheduling {
    func replaceReminder(for fixture: FixtureRecord) async throws {
        let center = UNUserNotificationCenter.current()
        let identifier = "fixture-\(fixture.id.rawValue)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let reminderDate = fixture.reminder.reminderDate(for: fixture.startsAt) else { return }

        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = fixture.name
        content.body = "Match starts soon. Open Wicket Tally for the recorded fixture details."
        content.sound = .default
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try await center.add(request)
    }

    func removeReminder(for fixtureID: FixtureID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["fixture-\(fixtureID.rawValue)"]
        )
    }
}

@MainActor
struct PreviewNotificationScheduler: LocalFixtureNotificationScheduling {
    func replaceReminder(for fixture: FixtureRecord) async throws {}
    func removeReminder(for fixtureID: FixtureID) async {}
}
