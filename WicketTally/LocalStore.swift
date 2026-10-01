import Foundation
import WicketStore

@MainActor
enum LocalStore {
    private static var didSeedUITest = false

    static func open() throws -> WicketStore {
        let manager = FileManager.default
        let root = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent("WicketTally", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let isUITest = ProcessInfo.processInfo.arguments.contains("--ui-testing-scorer")
        let url = directory.appendingPathComponent(isUITest ? "scorer-ui-test.sqlite" : "wicket-tally.sqlite")
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
            _ = try store.createFixture(
                leagueID: league.id, name: "Scorer UI Match",
                homeTeamID: home.id, awayTeamID: away.id, groundID: ground.id,
                participatingPlayerIDs: [], startsAt: Date(timeIntervalSince1970: 1_800_000_000),
                endsAt: Date(timeIntervalSince1970: 1_800_007_200), reminder: .none
            )
            return store
        }
        return try WicketStore.open(at: url)
    }
}
