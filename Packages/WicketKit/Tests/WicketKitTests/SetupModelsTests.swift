import Testing
@testable import WicketKit

@Suite("Setup domain models")
struct SetupModelsTests {
    @Test("league kind display names are human readable")
    func leagueKindDisplayNames() {
        #expect(LeagueKind.league.displayName == "League")
        #expect(LeagueKind.tournament.displayName == "Tournament")
        #expect(LeagueKind.allCases.count == 2)
    }

    @Test("player role display names cover every case")
    func playerRoleDisplayNames() {
        #expect(PlayerRole.batter.displayName == "Batter")
        #expect(PlayerRole.bowler.displayName == "Bowler")
        #expect(PlayerRole.allRounder.displayName == "All-rounder")
        #expect(PlayerRole.wicketKeeper.displayName == "Wicket-keeper")
        #expect(PlayerRole.allCases.count == 4)
    }

    @Test("every Indica team kit colour has a unique display name and hex")
    func teamKitColourTokens() {
        var seenNames = Set<String>()
        var seenHex = Set<String>()
        for colour in TeamKitColour.allCases {
            #expect(!colour.displayName.isEmpty)
            #expect(colour.hexRGB.count == 6)
            #expect(colour.prefersLightForeground)
            seenNames.insert(colour.displayName)
            seenHex.insert(colour.hexRGB)
        }
        #expect(seenNames.count == TeamKitColour.allCases.count)
        #expect(seenHex.count == TeamKitColour.allCases.count)
        #expect(TeamKitColour.allCases.count == 8)
    }

    @Test("league/team/player IDs preserve raw string values")
    func idRawValues() {
        let league: LeagueID = "league-1"
        let team: TeamID = "team-1"
        let player: PlayerID = "player-1"
        #expect(league.rawValue == "league-1")
        #expect(team.rawValue == "team-1")
        #expect(player.rawValue == "player-1")
        #expect(LeagueID("league-1") == league)
    }

    @Test("league deletion preview summary covers zero, singular, and plural children")
    func leagueDeletionPreviewSummaries() {
        let empty = LeagueDeletionPreview(leagueID: "l1", leagueName: "Empty Cup", teamCount: 0, playerCount: 0)
        #expect(empty.summary == "Delete Empty Cup")
        #expect(empty.leagueCount == 1)

        let oneTeam = LeagueDeletionPreview(leagueID: "l2", leagueName: "Solo Cup", teamCount: 1, playerCount: 0)
        #expect(oneTeam.summary == "Delete Solo Cup, 1 team")

        let onePlayer = LeagueDeletionPreview(leagueID: "l3", leagueName: "Duo Cup", teamCount: 0, playerCount: 1)
        #expect(onePlayer.summary == "Delete Duo Cup, 1 player")

        let both = LeagueDeletionPreview(leagueID: "l4", leagueName: "Street Cup", teamCount: 1, playerCount: 1)
        #expect(both.summary == "Delete Street Cup, 1 team, and 1 player")

        let plural = LeagueDeletionPreview(leagueID: "l5", leagueName: "Big Cup", teamCount: 3, playerCount: 12)
        #expect(plural.summary == "Delete Big Cup, 3 teams, and 12 players")
    }

    @Test("team deletion preview summary covers zero, singular, and plural children")
    func teamDeletionPreviewSummaries() {
        let empty = TeamDeletionPreview(teamID: "t1", teamName: "Ghost XI", playerCount: 0)
        #expect(empty.summary == "Delete Ghost XI")

        let one = TeamDeletionPreview(teamID: "t2", teamName: "Solo XI", playerCount: 1)
        #expect(one.summary == "Delete Solo XI and 1 player")

        let many = TeamDeletionPreview(teamID: "t3", teamName: "Full XI", playerCount: 11)
        #expect(many.summary == "Delete Full XI and 11 players")
    }

    @Test("player deletion preview summary names the player")
    func playerDeletionPreviewSummary() {
        let preview = PlayerDeletionPreview(playerID: "p1", playerName: "Kabir Shah")
        #expect(preview.summary == "Delete Kabir Shah")
    }
}
