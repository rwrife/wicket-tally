/// WicketKit — pure-domain core for Wicket Tally.
///
/// No UIKit, no GRDB, no Foundation-heavy I/O, no network clients, and no
/// file handles. Cricket ledger math and rules must be
/// exhaustively unit-testable without a simulator.
///
/// Issue #2 lands the MatchEvent ledger, rules engine, and derivations.
/// See `MatchLedger`, `MatchRules`, and `MatchState` for the entry points.
public enum WicketKit {
    /// Namespace marker for the domain layer.
    public static let domain = "WicketKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M1-ledger-rules-derivations"
}
