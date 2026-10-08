import Foundation
import WicketStore
import WicketKit


@MainActor
enum LocalStore {
    private static var didSeedUITest = false
    private static var didResetAdhocUITest = false

    static func open() throws -> WicketStore {
        let manager = FileManager.default
        let root = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent("WicketTally", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let arguments = ProcessInfo.processInfo.arguments
        let isSeasonUITest = arguments.contains("--ui-testing-season")
        let isUITest = arguments.contains("--ui-testing-scorer") || isSeasonUITest

        let isFreshAdhocUITest = arguments.contains("--ui-testing-adhoc")
        let isAdhocRelaunchUITest = arguments.contains("--ui-testing-adhoc-relaunch")
        let fileName: String
        if isUITest { fileName = "scorer-ui-test.sqlite" }
        else if isFreshAdhocUITest || isAdhocRelaunchUITest { fileName = "adhoc-ui-test.sqlite" }
        else { fileName = "wicket-tally.sqlite" }
        let url = directory.appendingPathComponent(fileName)
        if isUITest && !didSeedUITest {
            didSeedUITest = true
            for suffix in ["", "-wal", "-shm"] {
                try? manager.removeItem(atPath: url.path + suffix)
            }
            let store = try WicketStore.open(at: url)
            let league = try store.createLeague(name: "Scorer UI League", kind: .league)
            let home = try store.createTeam(leagueID: league.id, name: "Home XI", colour: .saffron)
            let away = try store.createTeam(leagueID: league.id, name: "Away XI", colour: .wicketGreen)
            let ground = try store.createGround(name: "Local Ground")
            let fixture = try store.createFixture(
                leagueID: league.id, name: "Scorer UI Match",
                homeTeamID: home.id, awayTeamID: away.id, groundID: ground.id,
                participatingPlayerIDs: [], startsAt: Date(timeIntervalSince1970: 1_800_000_000),
                endsAt: Date(timeIntervalSince1970: 1_800_007_200), reminder: .none
            )
            if isSeasonUITest {
                let batter = try store.createPlayer(teamID: home.id, name: "Season Batter", role: .batter)
                let bowler = try store.createPlayer(teamID: away.id, name: "Season Bowler", role: .bowler)
                let rules = MatchRules(oversPerInnings: 1, ballsPerOver: 1, maxWickets: 2)
                let kinds: [MatchEventKind] = [
                    .inningsStarted(number: 1, batting: home.id, bowling: away.id),
                    .ball(BallEvent(striker: batter.id, nonStriker: nil, bowler: bowler.id, runsOffBat: 4)),
                    .inningsStarted(number: 2, batting: away.id, bowling: home.id),
                    .ball(BallEvent(striker: bowler.id, nonStriker: nil, bowler: batter.id, runsOffBat: 0)),
                ]
                for (index, kind) in kinds.enumerated() {
                    try store.appendScoringEvent(MatchEvent(sequence: index + 1, kind: kind), fixtureID: fixture.id, rules: rules)
                }
            }
            return store
        }
        if isFreshAdhocUITest && !didResetAdhocUITest {
            // Issue #16 UI seam: start from a genuinely empty database so the
            // test proves an impromptu game needs no league/team/ground setup.
            didResetAdhocUITest = true
            for suffix in ["", "-wal", "-shm"] {
                try? manager.removeItem(atPath: url.path + suffix)
            }
        }
        return try WicketStore.open(at: url)
    }
}
