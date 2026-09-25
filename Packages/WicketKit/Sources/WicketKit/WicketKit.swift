/// WicketKit — pure-domain core for Wicket Tally.
///
/// Issue #1 ships only the skeleton namespace so CI has a real, testable
/// target. No UIKit, no GRDB, no Foundation-heavy I/O — cricket ledger
/// math and rules must be exhaustively unit-testable without a simulator.
/// Issue #2 lands the MatchEvent ledger, rules engine, and derivations here.
public enum WicketKit {
    /// Namespace marker for the domain layer.
    public static let domain = "WicketKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M0-skeleton"
}
