import Testing
@testable import WicketKit

@Suite("WicketKit skeleton placeholder")
struct WicketKitTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(WicketKit.domain == "WicketKit")
    }

    @Test("milestone marker is set for M0")
    func milestoneMarker() {
        #expect(WicketKit.milestone == "M0-skeleton")
    }
}
