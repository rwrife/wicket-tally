import Foundation
import GRDB
import Testing
@testable import WicketStore

@Suite("WicketStore v1 migration")
struct WicketStoreMigrationTests {
    @Test("v1 creates the complete setup schema and can roll back cleanly")
    func v1ForwardBackward() throws {
        let queue = try DatabaseQueue()
        try WicketStore.migrator.migrate(queue)

        let tables = try queue.read { db in
            try Set(String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
            ))
        }
        #expect(tables.isSuperset(of: ["leagues", "teams", "players", "grdb_migrations"]))

        try queue.write { db in
            try WicketStore.removeV1Schema(db)
        }

        let remaining = try queue.read { db in
            try Set(String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('leagues', 'teams', 'players')"
            ))
        }
        #expect(remaining.isEmpty)
    }

    @Test("checked-in v1 fixture opens without mutation and preserves its setup records")
    func checkedInFixture() throws {
        let fixture = try #require(Bundle.module.url(forResource: "wicket-store-v1", withExtension: "sqlite"))
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("wicket-store-fixture-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: fixture, to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let store = try WicketStore.open(at: temporary)
        let leagues = try store.listLeagues(includeArchived: true)
        let teams = try store.listTeams(leagueID: try #require(leagues.first?.id), includeArchived: true)
        let players = try store.listPlayers(teamID: try #require(teams.first?.id), includeArchived: true)

        #expect(leagues.map(\.name) == ["Sunday Gully Cup"])
        #expect(teams.map(\.name) == ["Azad XI"])
        #expect(teams.first?.colour == .saffron)
        #expect(players.map(\.name) == ["Asha Rao"])
        #expect(players.first?.role == .allRounder)
    }
}

@Suite("Fixture generation (one-time maintenance)")
struct WicketStoreFixtureGenerationTests {
    /// Not a normal assertion. Regenerates the checked-in v1 fixture in place
    /// when `WICKET_REGENERATE_FIXTURE=/abs/path` is set, so the committed DB
    /// is always produced by the exact shipping migrator (never hand-edited).
    @Test("regenerate checked-in v1 fixture on demand")
    func regenerateFixture() throws {
        guard let destination = ProcessInfo.processInfo.environment["WICKET_REGENERATE_FIXTURE"] else {
            return
        }
        let url = URL(fileURLWithPath: destination)
        try? FileManager.default.removeItem(at: url)
        let store = try WicketStore.open(at: url)
        let league = try store.createLeague(name: "Sunday Gully Cup", kind: .tournament)
        let team = try store.createTeam(leagueID: league.id, name: "Azad XI", colour: .saffron)
        _ = try store.createPlayer(teamID: team.id, name: "Asha Rao", role: .allRounder)
    }
}

@Suite("League, team, and player CRUD")
struct WicketStoreCRUDTests {
    @Test("creates, edits, archives, and lists setup records")
    func crudLifecycle() throws {
        let store = try WicketStore.inMemory()
        let league = try store.createLeague(name: "  Park League  ", kind: .league)
        let team = try store.createTeam(leagueID: league.id, name: "Boundary Riders", colour: .wicketGreen)
        let player = try store.createPlayer(teamID: team.id, name: "Mira Sen", role: .bowler)

        #expect(league.name == "Park League")
        #expect(try store.listLeagues() == [league])
        #expect(try store.listTeams(leagueID: league.id) == [team])
        #expect(try store.listPlayers(teamID: team.id) == [player])

        let renamedLeague = try store.updateLeague(id: league.id, name: "Park Tournament", kind: .tournament)
        let recolouredTeam = try store.updateTeam(id: team.id, name: "Boundary Riders XI", colour: .cricketRed)
        let promotedPlayer = try store.updatePlayer(id: player.id, name: "Mira Sen", role: .allRounder)

        #expect(renamedLeague.kind == .tournament)
        #expect(recolouredTeam.colour == .cricketRed)
        #expect(promotedPlayer.role == .allRounder)

        let archivedLeague = try store.setLeagueArchived(id: league.id, archived: true)
        let archivedTeam = try store.setTeamArchived(id: team.id, archived: true)
        let archivedPlayer = try store.setPlayerArchived(id: player.id, archived: true)

        #expect(archivedLeague.isArchived)
        #expect(archivedTeam.isArchived)
        #expect(archivedPlayer.isArchived)
        #expect(try store.listLeagues().isEmpty)
        #expect(try store.listTeams(leagueID: league.id).isEmpty)
        #expect(try store.listPlayers(teamID: team.id).isEmpty)
        #expect(try store.listLeagues(includeArchived: true).count == 1)
    }

    @Test("rejects blank names and orphaned children")
    func validation() throws {
        let store = try WicketStore.inMemory()

        #expect(throws: WicketStoreError.invalidName) {
            try store.createLeague(name: "   ", kind: .league)
        }
        #expect(throws: WicketStoreError.parentNotFound) {
            try store.createTeam(leagueID: "missing", name: "No League", colour: .marigold)
        }
        #expect(throws: WicketStoreError.parentNotFound) {
            try store.createPlayer(teamID: "missing", name: "No Team", role: .batter)
        }
    }

    @Test("deletion requires an exact cascade preview and never silently destroys children")
    func guardedDeletion() throws {
        let store = try WicketStore.inMemory()
        let league = try store.createLeague(name: "Street Cup", kind: .tournament)
        let team = try store.createTeam(leagueID: league.id, name: "Red Fort XI", colour: .royalPurple)
        _ = try store.createPlayer(teamID: team.id, name: "Kabir Shah", role: .batter)

        let leaguePreview = try store.previewLeagueDeletion(id: league.id)
        #expect(leaguePreview.leagueCount == 1)
        #expect(leaguePreview.teamCount == 1)
        #expect(leaguePreview.playerCount == 1)
        #expect(leaguePreview.summary == "Delete Street Cup, 1 team, and 1 player")

        _ = try store.createPlayer(teamID: team.id, name: "Naina Das", role: .bowler)
        #expect(throws: WicketStoreError.confirmationStale) {
            try store.deleteLeague(id: league.id, confirming: leaguePreview)
        }

        let refreshed = try store.previewLeagueDeletion(id: league.id)
        try store.deleteLeague(id: league.id, confirming: refreshed)
        #expect(try store.listLeagues(includeArchived: true).isEmpty)
        #expect(try store.listTeams(leagueID: league.id, includeArchived: true).isEmpty)
        #expect(try store.listPlayers(teamID: team.id, includeArchived: true).isEmpty)
    }

    @Test("team and player deletion previews state their exact impact")
    func childDeletionPreviews() throws {
        let store = try WicketStore.inMemory()
        let league = try store.createLeague(name: "Office League", kind: .league)
        let team = try store.createTeam(leagueID: league.id, name: "Spin Doctors", colour: .skyBlue)
        let player = try store.createPlayer(teamID: team.id, name: "Dev Patel", role: .wicketKeeper)

        let playerPreview = try store.previewPlayerDeletion(id: player.id)
        #expect(playerPreview.summary == "Delete Dev Patel")
        try store.deletePlayer(id: player.id, confirming: playerPreview)

        let teamPreview = try store.previewTeamDeletion(id: team.id)
        #expect(teamPreview.summary == "Delete Spin Doctors")
        try store.deleteTeam(id: team.id, confirming: teamPreview)
        #expect(try store.listTeams(leagueID: league.id, includeArchived: true).isEmpty)
    }
}
