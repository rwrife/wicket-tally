import Foundation
import Observation
import WicketKit
import WicketStore

@MainActor
@Observable
final class SetupViewModel {
    private let store: WicketStore?

    private(set) var leagues: [LeagueRecord] = []
    private(set) var teamsByLeague: [LeagueID: [TeamRecord]] = [:]
    private(set) var playersByTeam: [TeamID: [PlayerRecord]] = [:]
    var errorMessage: String?

    private init(store: WicketStore?, startupError: String? = nil) {
        self.store = store
        errorMessage = startupError
        if let store {
            do {
                leagues = try store.listLeagues(includeArchived: true)
            } catch {
                errorMessage = Self.userMessage(for: error)
            }
        }
    }

    static func live() -> SetupViewModel {
        do {
            let manager = FileManager.default
            let applicationSupport = try manager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = applicationSupport.appendingPathComponent("WicketTally", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try WicketStore.open(at: directory.appendingPathComponent("wicket-tally.sqlite"))
            return SetupViewModel(store: store)
        } catch {
            return SetupViewModel(store: nil, startupError: "Local storage could not be opened. No data was changed.")
        }
    }

    static func preview() -> SetupViewModel {
        do {
            let store = try WicketStore.inMemory()
            let league = try store.createLeague(name: "Sunday Gully Cup", kind: .tournament)
            let team = try store.createTeam(leagueID: league.id, name: "Azad XI", colour: .saffron)
            _ = try store.createPlayer(teamID: team.id, name: "Asha Rao", role: .allRounder)
            let model = SetupViewModel(store: store)
            try model.reloadTeams(for: league.id)
            try model.reloadPlayers(for: team.id)
            return model
        } catch {
            return SetupViewModel(store: nil, startupError: "Preview data could not be created.")
        }
    }

    func activeLeagues(showArchived: Bool) -> [LeagueRecord] {
        leagues.filter { showArchived || !$0.isArchived }
    }

    func teams(for leagueID: LeagueID, showArchived: Bool) -> [TeamRecord] {
        (teamsByLeague[leagueID] ?? []).filter { showArchived || !$0.isArchived }
    }

    func players(for teamID: TeamID, showArchived: Bool) -> [PlayerRecord] {
        (playersByTeam[teamID] ?? []).filter { showArchived || !$0.isArchived }
    }

    func reloadLeagues() throws {
        leagues = try requiredStore().listLeagues(includeArchived: true)
    }

    func reloadTeams(for leagueID: LeagueID) throws {
        teamsByLeague[leagueID] = try requiredStore().listTeams(
            leagueID: leagueID,
            includeArchived: true
        )
    }

    func reloadPlayers(for teamID: TeamID) throws {
        playersByTeam[teamID] = try requiredStore().listPlayers(
            teamID: teamID,
            includeArchived: true
        )
    }

    func createLeague(name: String, kind: LeagueKind) throws {
        _ = try requiredStore().createLeague(name: name, kind: kind)
        try reloadLeagues()
    }

    func updateLeague(_ league: LeagueRecord, name: String, kind: LeagueKind) throws {
        _ = try requiredStore().updateLeague(id: league.id, name: name, kind: kind)
        try reloadLeagues()
    }

    func setArchived(_ league: LeagueRecord, archived: Bool) throws {
        _ = try requiredStore().setLeagueArchived(id: league.id, archived: archived)
        try reloadLeagues()
    }

    func previewDeletion(of league: LeagueRecord) throws -> LeagueDeletionPreview {
        try requiredStore().previewLeagueDeletion(id: league.id)
    }

    func deleteLeague(_ league: LeagueRecord, confirming preview: LeagueDeletionPreview) throws {
        try requiredStore().deleteLeague(id: league.id, confirming: preview)
        teamsByLeague[league.id] = nil
        try reloadLeagues()
    }

    func createTeam(leagueID: LeagueID, name: String, colour: TeamKitColour) throws {
        _ = try requiredStore().createTeam(leagueID: leagueID, name: name, colour: colour)
        try reloadTeams(for: leagueID)
    }

    func updateTeam(_ team: TeamRecord, name: String, colour: TeamKitColour) throws {
        _ = try requiredStore().updateTeam(id: team.id, name: name, colour: colour)
        try reloadTeams(for: team.leagueID)
    }

    func setArchived(_ team: TeamRecord, archived: Bool) throws {
        _ = try requiredStore().setTeamArchived(id: team.id, archived: archived)
        try reloadTeams(for: team.leagueID)
    }

    func previewDeletion(of team: TeamRecord) throws -> TeamDeletionPreview {
        try requiredStore().previewTeamDeletion(id: team.id)
    }

    func deleteTeam(_ team: TeamRecord, confirming preview: TeamDeletionPreview) throws {
        try requiredStore().deleteTeam(id: team.id, confirming: preview)
        playersByTeam[team.id] = nil
        try reloadTeams(for: team.leagueID)
    }

    func createPlayer(teamID: TeamID, name: String, role: PlayerRole) throws {
        _ = try requiredStore().createPlayer(teamID: teamID, name: name, role: role)
        try reloadPlayers(for: teamID)
    }

    func updatePlayer(_ player: PlayerRecord, name: String, role: PlayerRole) throws {
        _ = try requiredStore().updatePlayer(id: player.id, name: name, role: role)
        try reloadPlayers(for: player.teamID)
    }

    func setArchived(_ player: PlayerRecord, archived: Bool) throws {
        _ = try requiredStore().setPlayerArchived(id: player.id, archived: archived)
        try reloadPlayers(for: player.teamID)
    }

    func previewDeletion(of player: PlayerRecord) throws -> PlayerDeletionPreview {
        try requiredStore().previewPlayerDeletion(id: player.id)
    }

    func deletePlayer(_ player: PlayerRecord, confirming preview: PlayerDeletionPreview) throws {
        try requiredStore().deletePlayer(id: player.id, confirming: preview)
        try reloadPlayers(for: player.teamID)
    }

    func report(_ error: Error) {
        errorMessage = Self.userMessage(for: error)
    }

    private func requiredStore() throws -> WicketStore {
        guard let store else { throw WicketStoreError.recordNotFound }
        return store
    }

    private static func userMessage(for error: Error) -> String {
        switch error {
        case WicketStoreError.invalidName:
            return "Enter a name before saving."
        case WicketStoreError.parentNotFound:
            return "The parent record no longer exists. Refresh and try again."
        case WicketStoreError.recordNotFound:
            return "This record no longer exists. Refresh and try again."
        case WicketStoreError.confirmationStale:
            return "The deletion impact changed. Review the updated preview before deleting."
        default:
            return "The local change could not be saved. No account or cloud copy exists."
        }
    }
}
