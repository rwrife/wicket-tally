import Testing
@testable import WicketKit

@Suite("Schedule generator")
struct ScheduleGeneratorTests {
    @Test(arguments: [2, 3, 4, 5])
    func roundRobin(size: Int) throws {
        let teams = (0..<size).map { TeamID(String($0)) }
        let plan = try ScheduleGenerator.generate(teams: Array(teams.reversed()), format: .roundRobin)
        #expect(plan.rounds.count == (size % 2 == 0 ? size - 1 : size))
        #expect(plan.knownMatchCount == size * (size - 1) / 2)
        #expect(plan.projectedMatchCount == plan.knownMatchCount)
        let pairs = plan.rounds.flatMap(\.pairings).filter(\.isPlayable)
        let keys = pairs.map { Set([$0.home!, $0.away!]) }
        #expect(Set(keys).count == keys.count)
        for round in plan.rounds {
            let participants = round.pairings.flatMap { [$0.home, $0.away].compactMap { $0 } }
            #expect(Set(participants).count == size)
        }
        #expect(try ScheduleGenerator.generate(teams: teams, format: .roundRobin) == plan)
    }

    @Test(arguments: [2, 3, 4, 5])
    func knockout(size: Int) throws {
        let plan = try ScheduleGenerator.generate(teams: (0..<size).map { TeamID(String($0)) }, format: .knockout)
        #expect(plan.projectedMatchCount == size - 1)
        let byes = plan.rounds[0].pairings.filter { !$0.isPlayable }
        #expect(byes.count == (size == 3 ? 1 : size == 5 ? 3 : 0))
        #expect(plan.rounds.last?.pairings.count == 1)
        #expect(plan.knownMatchCount <= size - 1)
    }

    @Test func invalidTeams() {
        #expect(throws: ScheduleError.notEnoughTeams) {
            try ScheduleGenerator.generate(teams: ["one"], format: .knockout)
        }
        #expect(throws: ScheduleError.duplicateTeam) {
            try ScheduleGenerator.generate(teams: ["same", "same"], format: .roundRobin)
        }
    }
}
