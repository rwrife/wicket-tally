import Testing
@testable import WicketKit

@Suite("WicketKit domain core")
struct WicketKitTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(WicketKit.domain == "WicketKit")
    }

    @Test("milestone marker reflects the ledger/rules/derivations milestone")
    func milestoneMarker() {
        #expect(WicketKit.milestone == "M1-ledger-rules-derivations")
    }
}
