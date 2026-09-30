import Foundation

/// Semantic colour surface of the Indica design system. Every feature view
/// reads colour from these tokens; no feature view builds its own colours.
public struct IndicaPalette: Sendable, Equatable {
    // Surfaces
    public let background: IndicaColor
    public let surface: IndicaColor
    public let surfaceElevated: IndicaColor
    public let separator: IndicaColor

    // Content
    public let textPrimary: IndicaColor
    public let textSecondary: IndicaColor
    public let textOnAccent: IndicaColor

    // Accents (cricket-ball red lead, saffron + green support)
    public let accentPrimary: IndicaColor
    public let accentSecondary: IndicaColor
    public let accentTertiary: IndicaColor

    // Status
    public let positive: IndicaColor
    public let warning: IndicaColor
    public let destructive: IndicaColor

    // Banner-painted match header
    public let bannerBackground: IndicaColor
    public let bannerForeground: IndicaColor
    public let bannerStripe: IndicaColor

    // Trophy-glow scoreboard
    public let scoreboardBackground: IndicaColor
    public let scoreboardForeground: IndicaColor
    public let trophyGlow: IndicaColor

    public init(
        background: IndicaColor,
        surface: IndicaColor,
        surfaceElevated: IndicaColor,
        separator: IndicaColor,
        textPrimary: IndicaColor,
        textSecondary: IndicaColor,
        textOnAccent: IndicaColor,
        accentPrimary: IndicaColor,
        accentSecondary: IndicaColor,
        accentTertiary: IndicaColor,
        positive: IndicaColor,
        warning: IndicaColor,
        destructive: IndicaColor,
        bannerBackground: IndicaColor,
        bannerForeground: IndicaColor,
        bannerStripe: IndicaColor,
        scoreboardBackground: IndicaColor,
        scoreboardForeground: IndicaColor,
        trophyGlow: IndicaColor
    ) {
        self.background = background
        self.surface = surface
        self.surfaceElevated = surfaceElevated
        self.separator = separator
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textOnAccent = textOnAccent
        self.accentPrimary = accentPrimary
        self.accentSecondary = accentSecondary
        self.accentTertiary = accentTertiary
        self.positive = positive
        self.warning = warning
        self.destructive = destructive
        self.bannerBackground = bannerBackground
        self.bannerForeground = bannerForeground
        self.bannerStripe = bannerStripe
        self.scoreboardBackground = scoreboardBackground
        self.scoreboardForeground = scoreboardForeground
        self.trophyGlow = trophyGlow
    }
}

/// Non-colour tokens. Values are point-based *baselines* — views must keep
/// applying Dynamic Type scaling (`@ScaledMetric`, relative font styles) on
/// top of them rather than freezing layout.
public struct IndicaMetrics: Sendable, Equatable {
    public let spacingXSmall: Double
    public let spacingSmall: Double
    public let spacingMedium: Double
    public let spacingLarge: Double
    public let cornerRadiusSmall: Double
    public let cornerRadiusMedium: Double
    public let cornerRadiusLarge: Double
    public let hairline: Double
    public let chipStrokeWidth: Double
    public let minimumHitTarget: Double
    /// Opacity of the trophy glow behind scoreboard numerals; the glow is
    /// always decorative and never the only carrier of meaning.
    public let glowOpacity: Double

    public init(
        spacingXSmall: Double = 4,
        spacingSmall: Double = 8,
        spacingMedium: Double = 12,
        spacingLarge: Double = 20,
        cornerRadiusSmall: Double = 8,
        cornerRadiusMedium: Double = 12,
        cornerRadiusLarge: Double = 20,
        hairline: Double = 1,
        chipStrokeWidth: Double = 1,
        minimumHitTarget: Double = 44,
        glowOpacity: Double = 0.35
    ) {
        self.spacingXSmall = spacingXSmall
        self.spacingSmall = spacingSmall
        self.spacingMedium = spacingMedium
        self.spacingLarge = spacingLarge
        self.cornerRadiusSmall = cornerRadiusSmall
        self.cornerRadiusMedium = cornerRadiusMedium
        self.cornerRadiusLarge = cornerRadiusLarge
        self.hairline = hairline
        self.chipStrokeWidth = chipStrokeWidth
        self.minimumHitTarget = minimumHitTarget
        self.glowOpacity = glowOpacity
    }
}

/// One skinnable Indica appearance. Light, Dark, Sunlight and festive skins
/// are all the same protocol, so a seasonal skin can never introduce a token
/// a screen does not already know how to consume.
public protocol IndicaTheme: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// `true` when the theme is tuned for direct-sunlight legibility: heavier
    /// strokes, flatter fills, and a 7:1 text floor.
    var isHighContrast: Bool { get }
    /// `true` for dark-first skins, so views can pick matching system chrome.
    var prefersDarkAppearance: Bool { get }
    var palette: IndicaPalette { get }
    var metrics: IndicaMetrics { get }
    /// Contrast floor for body text. Sunlight raises this above WCAG AA.
    var bodyTextFloor: Double { get }
    func chipStyle(for kit: IndicaKitColour) -> IndicaChipStyle
}

public extension IndicaTheme {
    var isHighContrast: Bool { false }
    var bodyTextFloor: Double { isHighContrast ? 7.0 : 4.5 }
}

// MARK: - Shared chip construction

private func chipStyles(
    _ table: [IndicaKitColour: String],
    stroke: IndicaColor,
    light: IndicaColor,
    dark: IndicaColor
) -> [IndicaKitColour: IndicaChipStyle] {
    var styles: [IndicaKitColour: IndicaChipStyle] = [:]
    for kit in IndicaKitColour.allCases {
        let fill = IndicaColor(hexRGB: table[kit] ?? "6B7280")
        styles[kit] = IndicaChipStyle(
            fill: fill,
            foreground: fill.preferredForeground(light: light, dark: dark),
            stroke: stroke
        )
    }
    return styles
}

// MARK: - Light

/// Warm daylight paper: banner-painted saturation on a cream ground.
public struct IndicaLightTheme: IndicaTheme {
    public let id = "indica.light"
    public let displayName = "Indica Light"
    public let prefersDarkAppearance = false
    public let metrics = IndicaMetrics()

    public init() {}

    public let palette = IndicaPalette(
        background: IndicaColor(hexRGB: "FFF8F0"),
        surface: IndicaColor(hexRGB: "FFFFFF"),
        surfaceElevated: IndicaColor(hexRGB: "FFF1E0"),
        separator: IndicaColor(hexRGB: "8A7458"),
        textPrimary: IndicaColor(hexRGB: "1A1208"),
        textSecondary: IndicaColor(hexRGB: "55442E"),
        textOnAccent: IndicaColor(hexRGB: "FFF8F0"),
        accentPrimary: IndicaColor(hexRGB: "B3261E"),
        accentSecondary: IndicaColor(hexRGB: "A34700"),
        accentTertiary: IndicaColor(hexRGB: "1F6B2E"),
        positive: IndicaColor(hexRGB: "1F6B2E"),
        warning: IndicaColor(hexRGB: "8A5A00"),
        destructive: IndicaColor(hexRGB: "B3261E"),
        bannerBackground: IndicaColor(hexRGB: "B3261E"),
        bannerForeground: IndicaColor(hexRGB: "FFF8F0"),
        bannerStripe: IndicaColor(hexRGB: "F2A007"),
        scoreboardBackground: IndicaColor(hexRGB: "14110D"),
        scoreboardForeground: IndicaColor(hexRGB: "FFF3D6"),
        trophyGlow: IndicaColor(hexRGB: "FFC53D")
    )

    private static let styles = chipStyles(
        [
            .cricketRed: "C92A2A",
            .saffron: "C45206",
            .wicketGreen: "29853C",
            .royalPurple: "6741D9",
            .skyBlue: "1971C2",
            .marigold: "AA6300",
            .sunsetOrange: "C94D0A",
            .peacockTeal: "0B7285",
        ],
        stroke: IndicaColor(hexRGB: "1A1208"),
        light: IndicaColor(hexRGB: "FFFFFF"),
        dark: IndicaColor(hexRGB: "000000")
    )

    public func chipStyle(for kit: IndicaKitColour) -> IndicaChipStyle {
        Self.styles[kit] ?? Self.styles[.cricketRed]!
    }
}

// MARK: - Dark

/// Night-match floodlight: deep ink ground with warm lamp accents.
public struct IndicaDarkTheme: IndicaTheme {
    public let id = "indica.dark"
    public let displayName = "Indica Dark"
    public let prefersDarkAppearance = true
    public let metrics = IndicaMetrics()

    public init() {}

    public let palette = IndicaPalette(
        background: IndicaColor(hexRGB: "121014"),
        surface: IndicaColor(hexRGB: "1E1B22"),
        surfaceElevated: IndicaColor(hexRGB: "272430"),
        separator: IndicaColor(hexRGB: "7E7793"),
        textPrimary: IndicaColor(hexRGB: "F5EFE6"),
        textSecondary: IndicaColor(hexRGB: "C0B4A4"),
        textOnAccent: IndicaColor(hexRGB: "121014"),
        accentPrimary: IndicaColor(hexRGB: "FF6B5A"),
        accentSecondary: IndicaColor(hexRGB: "FFB35C"),
        accentTertiary: IndicaColor(hexRGB: "5FD37E"),
        positive: IndicaColor(hexRGB: "5FD37E"),
        warning: IndicaColor(hexRGB: "FFC15C"),
        destructive: IndicaColor(hexRGB: "FF7A6B"),
        bannerBackground: IndicaColor(hexRGB: "7A1A14"),
        bannerForeground: IndicaColor(hexRGB: "FFF1E6"),
        bannerStripe: IndicaColor(hexRGB: "F2A007"),
        scoreboardBackground: IndicaColor(hexRGB: "0B0A0E"),
        scoreboardForeground: IndicaColor(hexRGB: "FFF3D6"),
        trophyGlow: IndicaColor(hexRGB: "FFC53D")
    )

    private static let styles = chipStyles(
        [
            .cricketRed: "D04545",
            .saffron: "C45206",
            .wicketGreen: "29853C",
            .royalPurple: "7F5FDF",
            .skyBlue: "2679C5",
            .marigold: "AA6300",
            .sunsetOrange: "C94D0A",
            .peacockTeal: "258192",
        ],
        stroke: IndicaColor(hexRGB: "F5EFE6"),
        light: IndicaColor(hexRGB: "FFFFFF"),
        dark: IndicaColor(hexRGB: "000000")
    )

    public func chipStyle(for kit: IndicaKitColour) -> IndicaChipStyle {
        Self.styles[kit] ?? Self.styles[.cricketRed]!
    }
}

// MARK: - Sunlight

/// Direct-sunlight appearance used by the scorer and glance mode: maximum
/// luminance separation, flat fills, 7:1 text floor, heavier strokes.
public struct IndicaSunlightTheme: IndicaTheme {
    public let id = "indica.sunlight"
    public let displayName = "Direct Sunlight"
    public let isHighContrast = true
    public let prefersDarkAppearance = false

    public let metrics = IndicaMetrics(
        cornerRadiusSmall: 6,
        cornerRadiusMedium: 10,
        cornerRadiusLarge: 16,
        hairline: 2,
        chipStrokeWidth: 2,
        minimumHitTarget: 48,
        glowOpacity: 0
    )

    public init() {}

    public let palette = IndicaPalette(
        background: IndicaColor(hexRGB: "FFFFFF"),
        surface: IndicaColor(hexRGB: "FFFFFF"),
        surfaceElevated: IndicaColor(hexRGB: "F0EFEC"),
        separator: IndicaColor(hexRGB: "1A1A1A"),
        textPrimary: IndicaColor(hexRGB: "000000"),
        textSecondary: IndicaColor(hexRGB: "3B3B3B"),
        textOnAccent: IndicaColor(hexRGB: "FFFFFF"),
        accentPrimary: IndicaColor(hexRGB: "A92323"),
        accentSecondary: IndicaColor(hexRGB: "943E04"),
        accentTertiary: IndicaColor(hexRGB: "1F652D"),
        positive: IndicaColor(hexRGB: "1F652D"),
        warning: IndicaColor(hexRGB: "6B4A00"),
        destructive: IndicaColor(hexRGB: "A92323"),
        bannerBackground: IndicaColor(hexRGB: "000000"),
        bannerForeground: IndicaColor(hexRGB: "FFFFFF"),
        bannerStripe: IndicaColor(hexRGB: "E03131"),
        scoreboardBackground: IndicaColor(hexRGB: "000000"),
        scoreboardForeground: IndicaColor(hexRGB: "FFFFFF"),
        trophyGlow: IndicaColor(hexRGB: "FFD400")
    )

    private static let styles = chipStyles(
        [
            .cricketRed: "AA2323",
            .saffron: "953E04",
            .wicketGreen: "20652E",
            .royalPurple: "603CCA",
            .skyBlue: "145A9B",
            .marigold: "834C00",
            .sunsetOrange: "993B08",
            .peacockTeal: "096172",
        ],
        stroke: IndicaColor(hexRGB: "000000"),
        light: IndicaColor(hexRGB: "FFFFFF"),
        dark: IndicaColor(hexRGB: "000000")
    )

    public func chipStyle(for kit: IndicaKitColour) -> IndicaChipStyle {
        Self.styles[kit] ?? Self.styles[.cricketRed]!
    }
}

// MARK: - Festive

/// Festival-of-lights seasonal skin: lamp-lit indigo ground, marigold and
/// diya-gold accents. Decorative only — no club, league, or sponsor marks.
public struct IndicaFestiveLightsTheme: IndicaTheme {
    public let id = "indica.festive.lights"
    public let displayName = "Festival of Lights"
    public let prefersDarkAppearance = true
    public let metrics = IndicaMetrics(glowOpacity: 0.5)

    public init() {}

    public let palette = IndicaPalette(
        background: IndicaColor(hexRGB: "1A0E2E"),
        surface: IndicaColor(hexRGB: "2A1745"),
        surfaceElevated: IndicaColor(hexRGB: "3A2059"),
        separator: IndicaColor(hexRGB: "8A66B8"),
        textPrimary: IndicaColor(hexRGB: "FFF3D6"),
        textSecondary: IndicaColor(hexRGB: "E0C9A8"),
        textOnAccent: IndicaColor(hexRGB: "1A0E2E"),
        accentPrimary: IndicaColor(hexRGB: "FFB300"),
        accentSecondary: IndicaColor(hexRGB: "FF9457"),
        accentTertiary: IndicaColor(hexRGB: "6FE0A8"),
        positive: IndicaColor(hexRGB: "6FE0A8"),
        warning: IndicaColor(hexRGB: "FFC85C"),
        destructive: IndicaColor(hexRGB: "FF8A7A"),
        bannerBackground: IndicaColor(hexRGB: "4A1273"),
        bannerForeground: IndicaColor(hexRGB: "FFF3D6"),
        bannerStripe: IndicaColor(hexRGB: "FFB300"),
        scoreboardBackground: IndicaColor(hexRGB: "120821"),
        scoreboardForeground: IndicaColor(hexRGB: "FFE9B0"),
        trophyGlow: IndicaColor(hexRGB: "FFD54F")
    )

    private static let styles = chipStyles(
        [
            .cricketRed: "D24C4C",
            .saffron: "F76707",
            .wicketGreen: "2C8B3F",
            .royalPurple: "8364E0",
            .skyBlue: "2D7DC7",
            .marigold: "F08C00",
            .sunsetOrange: "E8590C",
            .peacockTeal: "2A8494",
        ],
        stroke: IndicaColor(hexRGB: "FFF3D6"),
        light: IndicaColor(hexRGB: "FFFFFF"),
        dark: IndicaColor(hexRGB: "000000")
    )

    public func chipStyle(for kit: IndicaKitColour) -> IndicaChipStyle {
        Self.styles[kit] ?? Self.styles[.cricketRed]!
    }
}

// MARK: - Selection

/// How a screen chooses its theme. `automatic` follows the system appearance;
/// `sunlight` and festive skins are explicit user/scorer choices.
public enum IndicaThemeSelection: String, Sendable, Equatable, CaseIterable, Codable {
    case automatic
    case light
    case dark
    case sunlight
    case festiveLights

    public var displayName: String {
        switch self {
        case .automatic: return "Match the system"
        case .light: return IndicaLightTheme().displayName
        case .dark: return IndicaDarkTheme().displayName
        case .sunlight: return IndicaSunlightTheme().displayName
        case .festiveLights: return IndicaFestiveLightsTheme().displayName
        }
    }

    /// Resolves to a concrete theme. `isSystemDark` is supplied by the view
    /// layer from the SwiftUI colour scheme.
    public func resolve(isSystemDark: Bool) -> any IndicaTheme {
        switch self {
        case .automatic: return isSystemDark ? IndicaDarkTheme() : IndicaLightTheme()
        case .light: return IndicaLightTheme()
        case .dark: return IndicaDarkTheme()
        case .sunlight: return IndicaSunlightTheme()
        case .festiveLights: return IndicaFestiveLightsTheme()
        }
    }
}

/// Every shipped theme, used by the contrast audit and by theme pickers.
public enum IndicaThemeRegistry {
    public static let all: [any IndicaTheme] = [
        IndicaLightTheme(),
        IndicaDarkTheme(),
        IndicaSunlightTheme(),
        IndicaFestiveLightsTheme(),
    ]
}
