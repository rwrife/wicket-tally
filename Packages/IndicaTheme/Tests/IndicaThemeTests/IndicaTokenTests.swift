import Foundation
import Testing
@testable import IndicaTheme

@Suite("Indica token system")
struct IndicaTokenTests {
    @Test("registry ships light, dark, sunlight and a festive skin")
    func registryCoverage() {
        let ids = IndicaThemeRegistry.all.map(\.id)
        #expect(ids.contains("indica.light"))
        #expect(ids.contains("indica.dark"))
        #expect(ids.contains("indica.sunlight"))
        #expect(ids.contains("indica.festive.lights"))
        #expect(Set(ids).count == ids.count)
        #expect(IndicaThemeRegistry.all.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("hex round-trips through the token type")
    func hexRoundTrip() {
        for hex in ["000000", "FFFFFF", "C92A2A", "0B7285", "7F5FDF"] {
            #expect(IndicaColor(hexRGB: hex).hexRGB == hex)
        }
        #expect(IndicaColor(hexRGB: "#c92a2a").hexRGB == "C92A2A")
        // Malformed tokens degrade to grey instead of trapping mid-match.
        #expect(IndicaColor(hexRGB: "nope").hexRGB == IndicaColor(red: 0.5, green: 0.5, blue: 0.5).hexRGB)
    }

    @Test("selection resolves to the expected theme")
    func selectionResolution() {
        #expect(IndicaThemeSelection.automatic.resolve(isSystemDark: false).id == "indica.light")
        #expect(IndicaThemeSelection.automatic.resolve(isSystemDark: true).id == "indica.dark")
        #expect(IndicaThemeSelection.sunlight.resolve(isSystemDark: false).id == "indica.sunlight")
        #expect(IndicaThemeSelection.sunlight.resolve(isSystemDark: true).id == "indica.sunlight")
        #expect(IndicaThemeSelection.festiveLights.resolve(isSystemDark: false).id == "indica.festive.lights")
        #expect(IndicaThemeSelection.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("kit colour tokens mirror the domain jersey set exactly")
    func kitColourParity() {
        // Mirrors `WicketKit.TeamKitColour` raw values; the design system must
        // never silently drop or rename a jersey option.
        let domainRawValues = [
            "cricketRed", "saffron", "wicketGreen", "royalPurple",
            "skyBlue", "marigold", "sunsetOrange", "peacockTeal",
        ]
        #expect(IndicaKitColour.allCases.map(\.rawValue) == domainRawValues)
        for raw in domainRawValues {
            #expect(IndicaKitColour(rawValue: raw) != nil)
        }
    }

    @Test("every theme resolves a chip style for every kit colour")
    func chipCoverage() {
        for theme in IndicaThemeRegistry.all {
            for kit in IndicaKitColour.allCases {
                let style = theme.chipStyle(for: kit)
                #expect(style.fill.hexRGB.count == 6)
                #expect(style.foreground == style.fill.preferredForeground(light: IndicaColor(hexRGB: "FFFFFF"), dark: IndicaColor(hexRGB: "000000")))
            }
        }
    }

    @Test("sunlight metrics harden strokes and drop decorative glow")
    func sunlightMetrics() {
        let sunlight = IndicaSunlightTheme()
        let light = IndicaLightTheme()
        #expect(sunlight.metrics.hairline >= light.metrics.hairline)
        #expect(sunlight.metrics.chipStrokeWidth >= light.metrics.chipStrokeWidth)
        #expect(sunlight.metrics.glowOpacity == 0)
        #expect(sunlight.metrics.minimumHitTarget >= 44)
    }

    @Test("metrics keep a 44pt minimum hit target on every theme")
    func hitTargets() {
        for theme in IndicaThemeRegistry.all {
            #expect(theme.metrics.minimumHitTarget >= 44)
            #expect(theme.metrics.spacingSmall > 0)
        }
    }

    @Test("preferredForeground picks the higher-contrast option")
    func foregroundSelection() {
        #expect(IndicaColor(hexRGB: "000000").preferredForeground().hexRGB == "FFFFFF")
        #expect(IndicaColor(hexRGB: "FFFFFF").preferredForeground().hexRGB == "000000")
    }
}
