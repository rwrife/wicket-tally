import Foundation

/// Design-system mirror of the closed jersey-colour set defined in the domain
/// layer (`WicketKit.TeamKitColour`). Raw values match one-for-one so the
/// theme can resolve chip styling without the design system depending on the
/// domain module, and without the domain owning presentation concerns.
///
/// These are generic kit colours only — no club names, crests, or marks.
public enum IndicaKitColour: String, Sendable, Equatable, Hashable, CaseIterable {
    case cricketRed
    case saffron
    case wicketGreen
    case royalPurple
    case skyBlue
    case marigold
    case sunsetOrange
    case peacockTeal
}

/// A fully resolved, contrast-audited chip appearance for one kit colour on
/// one theme.
public struct IndicaChipStyle: Sendable, Equatable {
    public let fill: IndicaColor
    public let foreground: IndicaColor
    public let stroke: IndicaColor

    public init(fill: IndicaColor, foreground: IndicaColor, stroke: IndicaColor) {
        self.fill = fill
        self.foreground = foreground
        self.stroke = stroke
    }
}

#if canImport(WicketKit)
import WicketKit

public extension IndicaKitColour {
    /// Bridges a domain jersey colour into its design-system token.
    init(_ teamKitColour: TeamKitColour) {
        self = IndicaKitColour(rawValue: teamKitColour.rawValue) ?? .cricketRed
    }
}
#endif
