import Foundation
import Testing
@testable import IndicaTheme

/// One audited foreground/background pair. Ratios are computed with real WCAG
/// relative-luminance math in `IndicaColor`, not hardcoded expectations.
private struct ContrastPair {
    let label: String
    let foreground: IndicaColor
    let background: IndicaColor
    let requirement: IndicaContrastRequirement
}

private func textPairs(for theme: any IndicaTheme) -> [ContrastPair] {
    let p = theme.palette
    return [
        ContrastPair(label: "textPrimary on background", foreground: p.textPrimary, background: p.background, requirement: .bodyText),
        ContrastPair(label: "textPrimary on surface", foreground: p.textPrimary, background: p.surface, requirement: .bodyText),
        ContrastPair(label: "textPrimary on surfaceElevated", foreground: p.textPrimary, background: p.surfaceElevated, requirement: .bodyText),
        ContrastPair(label: "textSecondary on background", foreground: p.textSecondary, background: p.background, requirement: .bodyText),
        ContrastPair(label: "textSecondary on surface", foreground: p.textSecondary, background: p.surface, requirement: .bodyText),
        ContrastPair(label: "textSecondary on surfaceElevated", foreground: p.textSecondary, background: p.surfaceElevated, requirement: .bodyText),
        ContrastPair(label: "accentPrimary on background", foreground: p.accentPrimary, background: p.background, requirement: .bodyText),
        ContrastPair(label: "accentPrimary on surface", foreground: p.accentPrimary, background: p.surface, requirement: .bodyText),
        ContrastPair(label: "accentSecondary on background", foreground: p.accentSecondary, background: p.background, requirement: .bodyText),
        ContrastPair(label: "accentSecondary on surface", foreground: p.accentSecondary, background: p.surface, requirement: .bodyText),
        ContrastPair(label: "accentTertiary on background", foreground: p.accentTertiary, background: p.background, requirement: .bodyText),
        ContrastPair(label: "positive on surface", foreground: p.positive, background: p.surface, requirement: .bodyText),
        ContrastPair(label: "warning on surface", foreground: p.warning, background: p.surface, requirement: .bodyText),
        ContrastPair(label: "destructive on surface", foreground: p.destructive, background: p.surface, requirement: .bodyText),
        ContrastPair(label: "textOnAccent on accentPrimary", foreground: p.textOnAccent, background: p.accentPrimary, requirement: .largeText),
        ContrastPair(label: "scorer action on accentPrimary", foreground: p.textOnAccent, background: p.accentPrimary, requirement: .bodyText),
        ContrastPair(label: "scorer wicket on destructive", foreground: p.textOnAccent, background: p.destructive, requirement: .bodyText),
        ContrastPair(label: "bannerForeground on bannerBackground", foreground: p.bannerForeground, background: p.bannerBackground, requirement: .bodyText),
        ContrastPair(label: "scoreboardForeground on scoreboardBackground", foreground: p.scoreboardForeground, background: p.scoreboardBackground, requirement: .bodyText),
        ContrastPair(label: "trophyGlow on scoreboardBackground", foreground: p.trophyGlow, background: p.scoreboardBackground, requirement: .uiComponent),
        ContrastPair(label: "bannerStripe on bannerBackground", foreground: p.bannerStripe, background: p.bannerBackground, requirement: .uiComponent),
        ContrastPair(label: "separator on background", foreground: p.separator, background: p.background, requirement: .uiComponent),
        ContrastPair(label: "separator on surface", foreground: p.separator, background: p.surface, requirement: .uiComponent),
    ]
}

@Suite("Indica contrast audit")
struct IndicaContrastTests {
    @Test("relative luminance and ratio math match WCAG reference values")
    func wcagReferenceMath() {
        let white = IndicaColor(hexRGB: "FFFFFF")
        let black = IndicaColor(hexRGB: "000000")
        #expect(abs(white.relativeLuminance - 1.0) < 0.0001)
        #expect(abs(black.relativeLuminance - 0.0) < 0.0001)
        #expect(abs(white.contrastRatio(to: black) - 21.0) < 0.0001)
        #expect(abs(black.contrastRatio(to: white) - 21.0) < 0.0001)
        #expect(abs(white.contrastRatio(to: white) - 1.0) < 0.0001)
        // Reference: #767676 on white is the canonical 4.54:1 AA boundary.
        let grey = IndicaColor(hexRGB: "767676")
        #expect(abs(grey.contrastRatio(to: white) - 4.54) < 0.02)
        // Reference: #0000FF on white is 8.59:1.
        #expect(abs(IndicaColor(hexRGB: "0000FF").contrastRatio(to: white) - 8.59) < 0.02)
    }

    @Test("every theme meets its text and UI contrast floors", arguments: IndicaThemeRegistry.all.map(\.id))
    func semanticTokenContrast(themeID: String) throws {
        let theme = try #require(IndicaThemeRegistry.all.first { $0.id == themeID })
        for pair in textPairs(for: theme) {
            let ratio = pair.foreground.contrastRatio(to: pair.background)
            let floor = pair.requirement == .bodyText ? theme.bodyTextFloor : pair.requirement.minimumRatio
            #expect(
                ratio >= floor,
                "\(theme.displayName): \(pair.label) is \(String(format: "%.2f", ratio)):1, below \(floor):1"
            )
        }
    }

    @Test("team kit chips stay legible on every theme", arguments: IndicaThemeRegistry.all.map(\.id))
    func teamChipContrast(themeID: String) throws {
        let theme = try #require(IndicaThemeRegistry.all.first { $0.id == themeID })
        for kit in IndicaKitColour.allCases {
            let style = theme.chipStyle(for: kit)
            let textRatio = style.foreground.contrastRatio(to: style.fill)
            #expect(
                textRatio >= theme.bodyTextFloor,
                "\(theme.displayName): \(kit.rawValue) chip label is \(String(format: "%.2f", textRatio)):1 on its fill"
            )
            for (name, background) in [
                ("background", theme.palette.background),
                ("surface", theme.palette.surface),
                ("surfaceElevated", theme.palette.surfaceElevated),
            ] {
                let fillRatio = style.fill.contrastRatio(to: background)
                #expect(
                    fillRatio >= IndicaContrastRequirement.uiComponent.minimumRatio,
                    "\(theme.displayName): \(kit.rawValue) chip fill is \(String(format: "%.2f", fillRatio)):1 on \(name)"
                )
            }
            let strokeRatio = style.stroke.contrastRatio(to: style.fill)
            #expect(strokeRatio > 1.0, "\(theme.displayName): \(kit.rawValue) chip stroke is invisible on its fill")
        }
    }

    @Test("sunlight theme holds a 7:1 text floor above plain AA")
    func sunlightExceedsAA() {
        let sunlight = IndicaSunlightTheme()
        #expect(sunlight.isHighContrast)
        #expect(sunlight.bodyTextFloor >= 7.0)
        for pair in textPairs(for: sunlight) where pair.requirement == .bodyText {
            #expect(pair.foreground.contrastRatio(to: pair.background) >= 7.0)
        }
    }

    @Test("no two adjacent kit chips on one theme collapse into the same fill", arguments: IndicaThemeRegistry.all.map(\.id))
    func chipsAreDistinguishable(themeID: String) throws {
        let theme = try #require(IndicaThemeRegistry.all.first { $0.id == themeID })
        let fills = IndicaKitColour.allCases.map { theme.chipStyle(for: $0).fill.hexRGB }
        #expect(Set(fills).count == IndicaKitColour.allCases.count)
    }

    /// Emits the documented contrast matrix as test output so CI evidence and
    /// `docs/indica-design-system.md` cannot drift apart silently.
    @Test("contrast matrix evidence")
    func printContrastMatrix() {
        var lines: [String] = ["| Theme | Pair | Requirement | Measured |", "| --- | --- | --- | --- |"]
        for theme in IndicaThemeRegistry.all {
            for pair in textPairs(for: theme) {
                lines.append("| \(theme.displayName) | \(pair.label) | \(pair.requirement.label) | \(String(format: "%.2f", pair.foreground.contrastRatio(to: pair.background))):1 |")
            }
            for kit in IndicaKitColour.allCases {
                let style = theme.chipStyle(for: kit)
                lines.append("| \(theme.displayName) | chip \(kit.rawValue) label on fill | \(IndicaContrastRequirement.bodyText.label) | \(String(format: "%.2f", style.foreground.contrastRatio(to: style.fill))):1 |")
                lines.append("| \(theme.displayName) | chip \(kit.rawValue) fill on background | \(IndicaContrastRequirement.uiComponent.label) | \(String(format: "%.2f", style.fill.contrastRatio(to: theme.palette.background))):1 |")
            }
        }
        print(lines.joined(separator: "\n"))
        #expect(lines.count > 2)
    }
}
