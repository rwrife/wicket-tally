#if canImport(SwiftUI)
import SwiftUI

public extension IndicaColor {
    /// SwiftUI bridge. Tokens are authored in sRGB, so they are converted in
    /// the same space the contrast audit measures.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

private struct IndicaThemeKey: EnvironmentKey {
    static let defaultValue: any IndicaTheme = IndicaLightTheme()
}

private struct IndicaThemeSelectionKey: EnvironmentKey {
    static let defaultValue: IndicaThemeSelection = .automatic
}

public extension EnvironmentValues {
    /// The resolved Indica theme. Feature views read colour only from here.
    var indicaTheme: any IndicaTheme {
        get { self[IndicaThemeKey.self] }
        set { self[IndicaThemeKey.self] = newValue }
    }

    /// The user-facing selection that produced `indicaTheme`.
    var indicaThemeSelection: IndicaThemeSelection {
        get { self[IndicaThemeSelectionKey.self] }
        set { self[IndicaThemeSelectionKey.self] = newValue }
    }
}

private struct IndicaThemeModifier: ViewModifier {
    let selection: IndicaThemeSelection
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = selection.resolve(isSystemDark: colorScheme == .dark)
        let appearance: ColorScheme = theme.prefersDarkAppearance ? .dark : .light
        return content
            .environment(\.indicaTheme, theme)
            .environment(\.indicaThemeSelection, selection)
            .environment(\.colorScheme, appearance)
            .preferredColorScheme(selection == .automatic ? nil : appearance)
            .foregroundStyle(theme.palette.textPrimary.color)
            .tint(theme.palette.accentPrimary.color)
    }
}

public extension View {
    /// Installs an Indica theme for this subtree. Call once at the app root;
    /// scorer/glance surfaces can re-apply `.sunlight` locally.
    func indicaTheme(_ selection: IndicaThemeSelection) -> some View {
        modifier(IndicaThemeModifier(selection: selection))
    }

    /// Paints the themed screen background behind scrolling content.
    func indicaScreenBackground() -> some View {
        modifier(IndicaScreenBackground())
    }

    /// Themed list-row background; keeps rows on tokens instead of the
    /// platform default material.
    func indicaRowBackground() -> some View {
        modifier(IndicaRowBackground())
    }

}

private struct IndicaScreenBackground: ViewModifier {
    @Environment(\.indicaTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.palette.background.color.ignoresSafeArea())
    }
}

private struct IndicaRowBackground: ViewModifier {
    @Environment(\.indicaTheme) private var theme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(theme.palette.textPrimary.color)
            .listRowBackground(theme.palette.surface.color)
    }

}

// MARK: - Components

/// Banner-painted match header. Text keeps its semantic font style so Dynamic
/// Type continues to scale it, and the stripe is decorative only.
public struct IndicaBannerHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    @Environment(\.indicaTheme) private var theme

    public init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spacingMedium) {
            VStack(alignment: .leading, spacing: theme.metrics.spacingXSmall) {
                Text(title)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(theme.palette.bannerForeground.color)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(theme.palette.bannerForeground.color)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(theme.metrics.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                theme.palette.bannerBackground.color
                Rectangle()
                    .fill(theme.palette.bannerStripe.color)
                    .frame(height: theme.metrics.hairline * 4)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusMedium))
    }
}

public extension IndicaBannerHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Trophy-glow scoreboard container for the scorer and glance mode. The glow
/// is purely decorative; legibility comes from the scoreboard tokens, which
/// are contrast-audited on every theme.
public struct IndicaScoreboardPanel<Content: View>: View {
    private let content: Content
    @Environment(\.indicaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .foregroundStyle(theme.palette.scoreboardForeground.color)
            .padding(theme.metrics.spacingLarge)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusLarge)
                    .fill(theme.palette.scoreboardBackground.color)
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusLarge)
                            .strokeBorder(
                                theme.palette.trophyGlow.color.opacity(glowOpacity),
                                lineWidth: theme.metrics.hairline * 3
                            )
                    }
                    .accessibilityHidden(true)
            }
    }

    private var glowOpacity: Double {
        reduceMotion ? min(theme.metrics.glowOpacity, 0.2) : theme.metrics.glowOpacity
    }
}

/// Team kit chip. Colour is never the sole carrier of meaning: the chip
/// always renders its colour name and exposes it to VoiceOver.
public struct IndicaTeamChip: View {
    private let kit: IndicaKitColour
    private let label: String

    @Environment(\.indicaTheme) private var theme
    @ScaledMetric(relativeTo: .caption) private var horizontalPadding: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var verticalPadding: CGFloat = 6

    public init(kit: IndicaKitColour, label: String) {
        self.kit = kit
        self.label = label
    }

    public var body: some View {
        let style = theme.chipStyle(for: kit)
        return HStack(spacing: theme.metrics.spacingXSmall) {
            Image(systemName: "tshirt.fill")
                .font(.caption.bold())
            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .foregroundStyle(style.foreground.color)
        .background(
            RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusSmall)
                .fill(style.fill.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.cornerRadiusSmall)
                .stroke(style.stroke.color.opacity(theme.isHighContrast ? 1 : 0.24), lineWidth: theme.metrics.chipStrokeWidth)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jersey colour \(label)")
    }
}

/// Small status capsule (for example "Archived") built from surface tokens.
public struct IndicaStatusPill: View {
    private let text: String
    @Environment(\.indicaTheme) private var theme
    @ScaledMetric(relativeTo: .caption) private var horizontalPadding: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var verticalPadding: CGFloat = 4

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(theme.palette.textPrimary.color)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Capsule().fill(theme.palette.surfaceElevated.color))
            .overlay(
                Capsule().stroke(theme.palette.separator.color.opacity(theme.isHighContrast ? 1 : 0.4), lineWidth: theme.metrics.hairline)
            )
    }
}

public extension View {
    /// Applies the themed secondary text token (replaces `.secondary`).
    func indicaSecondaryText() -> some View {
        modifier(IndicaSecondaryText())
    }

    /// Applies the themed primary text token.
    func indicaPrimaryText() -> some View {
        modifier(IndicaPrimaryText())
    }
}

private struct IndicaSecondaryText: ViewModifier {
    @Environment(\.indicaTheme) private var theme
    func body(content: Content) -> some View {
        content.foregroundStyle(theme.palette.textSecondary.color)
    }
}

private struct IndicaPrimaryText: ViewModifier {
    @Environment(\.indicaTheme) private var theme
    func body(content: Content) -> some View {
        content.foregroundStyle(theme.palette.textPrimary.color)
    }
}
#endif
