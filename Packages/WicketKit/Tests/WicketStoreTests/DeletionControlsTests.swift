import Foundation
import Testing
import WicketKit

@testable import WicketStore

@Suite("Deletion control matrix")
struct DeletionControlsTests {
  @Test("wipe all requires exact typed confirmation and preserves an operational schema")
  func typedWipeAll() throws {
    let store = try WicketStore.inMemory()
    let league = try store.createLeague(name: "Wipe League", kind: .league)
    let team = try store.createTeam(leagueID: league.id, name: "Wipe XI", colour: .marigold)
    _ = try store.createPlayer(teamID: team.id, name: "Wipe Player", role: .batter)
    let preview = try store.previewWipeAll()

    #expect(preview.totalRecordCount == 3)
    #expect(throws: WicketBackupError.invalidWipeConfirmation) {
      try store.wipeAll(typedConfirmation: "delete all data", confirming: preview)
    }
    #expect(try store.listLeagues(includeArchived: true).count == 1)

    try store.wipeAll(
      typedConfirmation: WicketWipePreview.requiredConfirmation,
      confirming: preview
    )
    #expect(try store.listLeagues(includeArchived: true).isEmpty)
    #expect(try store.listGrounds().isEmpty)

    let replacement = try store.createLeague(name: "Fresh League", kind: .tournament)
    #expect(try store.league(id: replacement.id) == replacement)
  }

  @Test("wipe refuses a stale preview")
  func staleWipePreview() throws {
    let store = try WicketStore.inMemory()
    _ = try store.createLeague(name: "Original", kind: .league)
    let preview = try store.previewWipeAll()
    _ = try store.createLeague(name: "Added later", kind: .league)

    #expect(throws: WicketBackupError.confirmationStale) {
      try store.wipeAll(
        typedConfirmation: WicketWipePreview.requiredConfirmation,
        confirming: preview
      )
    }
    #expect(try store.listLeagues().count == 2)
  }

  @Test("existing per-league deletion preview cascades only that league")
  func leagueCascadeReuse() throws {
    let store = try WicketStore.inMemory()
    let deletedLeague = try store.createLeague(name: "Delete Cup", kind: .tournament)
    let keptLeague = try store.createLeague(name: "Keep Cup", kind: .tournament)
    let home = try store.createTeam(leagueID: deletedLeague.id, name: "Home", colour: .cricketRed)
    let away = try store.createTeam(leagueID: deletedLeague.id, name: "Away", colour: .skyBlue)
    let player = try store.createPlayer(teamID: home.id, name: "Player", role: .allRounder)
    let ground = try store.createGround(name: "Shared Ground")
    _ = try store.createFixture(
      leagueID: deletedLeague.id,
      name: "Delete fixture",
      homeTeamID: home.id,
      awayTeamID: away.id,
      groundID: ground.id,
      participatingPlayerIDs: [player.id],
      startsAt: Date(timeIntervalSince1970: 1_800_000_000),
      endsAt: Date(timeIntervalSince1970: 1_800_003_600),
      reminder: .none
    )

    let preview = try store.previewLeagueDeletion(id: deletedLeague.id)
    #expect(preview.leagueCount == 1)
    #expect(preview.teamCount == 2)
    #expect(preview.playerCount == 1)
    try store.deleteLeague(id: deletedLeague.id, confirming: preview)

    #expect(try store.listLeagues().map(\.id) == [keptLeague.id])
    #expect(try store.listFixtures().isEmpty)
    #expect(try store.listGrounds() == [ground])
  }

  @Test("archive hides data without deleting it or its children")
  func archiveIsNotDelete() throws {
    let store = try WicketStore.inMemory()
    let league = try store.createLeague(name: "Archived Cup", kind: .league)
    let team = try store.createTeam(leagueID: league.id, name: "Archived XI", colour: .wicketGreen)
    let player = try store.createPlayer(teamID: team.id, name: "Archived Player", role: .bowler)

    _ = try store.setLeagueArchived(id: league.id, archived: true)

    #expect(try store.listLeagues().isEmpty)
    #expect(try store.listLeagues(includeArchived: true).map(\.id) == [league.id])
    #expect(try store.listTeams(leagueID: league.id, includeArchived: true).map(\.id) == [team.id])
    #expect(try store.listPlayers(teamID: team.id, includeArchived: true).map(\.id) == [player.id])
  }
}
