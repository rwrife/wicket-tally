import Foundation

/// A resolved sRGB colour token used by the Indica design system.
///
/// Tokens are stored as plain sRGB components so contrast can be audited by
/// real WCAG relative-luminance math in tests on any platform, independent of
/// SwiftUI rendering.
public struct IndicaColor: Sendable, Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Creates a token from a six-digit sRGB hex string such as `"C92A2A"`.
    /// Invalid input resolves to mid grey rather than trapping so a malformed
    /// token can never crash a live scorer session.
    public init(hexRGB: String) {
        let clean = hexRGB
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard clean.count == 6, let raw = Int(clean, radix: 16) else {
            self.init(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        self.init(
            red: Double((raw >> 16) & 0xFF) / 255.0,
            green: Double((raw >> 8) & 0xFF) / 255.0,
            blue: Double(raw & 0xFF) / 255.0
        )
    }

    public var hexRGB: String {
        String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// WCAG 2.1 relative luminance.
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 2.1 contrast ratio between two opaque colours (1...21).
    public func contrastRatio(to other: IndicaColor) -> Double {
        let lhs = relativeLuminance
        let rhs = other.relativeLuminance
        let lighter = max(lhs, rhs)
        let darker = min(lhs, rhs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Picks whichever of the two supplied foregrounds contrasts more strongly.
    public func preferredForeground(
        light: IndicaColor = IndicaColor(hexRGB: "FFFFFF"),
        dark: IndicaColor = IndicaColor(hexRGB: "000000")
    ) -> IndicaColor {
        contrastRatio(to: light) >= contrastRatio(to: dark) ? light : dark
    }
}

/// The contrast floors the Indica system commits to, expressed so tests and
/// the documented contrast matrix share one source of truth.
public enum IndicaContrastRequirement: Sendable, CaseIterable {
    /// Body text and any text below 18pt regular / 14pt bold.
    case bodyText
    /// Large text (>= 18pt regular or >= 14pt bold) and headline treatments.
    case largeText
    /// Non-text UI components: chip fills, strokes, focus rings, glyphs.
    case uiComponent

    public var minimumRatio: Double {
        switch self {
        case .bodyText: return 4.5
        case .largeText, .uiComponent: return 3.0
        }
    }

    public var label: String {
        switch self {
        case .bodyText: return "body text (4.5:1)"
        case .largeText: return "large text (3:1)"
        case .uiComponent: return "non-text UI (3:1)"
        }
    }
}

public extension IndicaColor {
    func satisfies(_ requirement: IndicaContrastRequirement, against background: IndicaColor) -> Bool {
        contrastRatio(to: background) >= requirement.minimumRatio
    }
}
