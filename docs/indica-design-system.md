# Indica design system

The Indica design system is WicketTally's outdoor-first, street-cricket visual
language expressed as tokens. Feature views never author colour: they read
semantic tokens from a theme, so a new skin (or the Direct Sunlight appearance)
can never leave a screen unreadable.

Generic kit colours only — no club names, crests, sponsor marks, or other
trademarked material appears anywhere in the token set.

## Where the code lives

| Path | Purpose |
| --- | --- |
| `WicketTally/Theme/IndicaColor.swift` | sRGB token type + real WCAG relative-luminance / contrast math |
| `WicketTally/Theme/IndicaKitColour.swift` | Jersey-colour token set, chip style type, `WicketKit.TeamKitColour` bridge |
| `WicketTally/Theme/IndicaTheme.swift` | `IndicaTheme` protocol, palettes, metrics, the four shipped skins, selection + registry |
| `WicketTally/Theme/IndicaThemeEnvironment.swift` | SwiftUI environment, modifiers and components (banner header, scoreboard, chips, pills) |
| `Packages/IndicaTheme` | `swift test` harness; `Sources/IndicaTheme` is a symlink to `WicketTally/Theme` so the app and the tests compile the *same* files |
| `scripts/check_indica_tokens.sh` | CI gate: every feature view must be token-only, including newly added screens |

## Themes

| Theme | `id` | Intent | Body-text floor |
| --- | --- | --- | --- |
| Indica Light | `indica.light` | Warm daylight paper, banner-painted saturation | 4.5:1 |
| Indica Dark | `indica.dark` | Night match under floodlights | 4.5:1 |
| Direct Sunlight | `indica.sunlight` | High-contrast outdoor appearance used by the scorer and glance mode; flat fills, doubled strokes, no decorative glow | 7:1 |
| Festival of Lights | `indica.festive.lights` | Seasonal skin: lamp-lit indigo ground, marigold/diya-gold accents | 4.5:1 |

All four conform to one `IndicaTheme` protocol, so a seasonal skin can never
introduce a token a screen does not already consume.

## API for feature screens (scorer, fixtures, stats, settings)

```swift
// 1. Install once at the root (already done in ContentView):
TabView { ... }
    .indicaTheme(selection)              // .automatic / .light / .dark / .sunlight / .festiveLights

// 2. Glance mode resolves its own drawing tokens AND system chrome to Sunlight.
// Do not only wrap a view in .indicaTheme(.sunlight) if it reads theme from
// @Environment in its own body: the wrapper changes descendants, not that body.

// 3. Read tokens inside a view:
@Environment(\.indicaTheme) private var theme
theme.palette.accentPrimary.color         // SwiftUI Color from an sRGB token
theme.palette.scoreboardForeground.color
theme.metrics.spacingMedium               // baseline metric, still scale with Dynamic Type
theme.isHighContrast                      // tune decoration for direct sunlight

// 4. Ready-made, contrast-audited components:
IndicaBannerHeader(title: "Match 4", subtitle: "Overs 12.3")
IndicaScoreboardPanel { Text("128/4").font(.largeTitle.weight(.heavy)) }
IndicaTeamChip(kit: IndicaKitColour(team.colour), label: team.colour.displayName)
IndicaStatusPill("Archived")

// 5. Text and surfaces:
Text("Run rate").indicaSecondaryText()
List { ... }.indicaScreenBackground().indicaPrimaryText()
Section { ... }.indicaRowBackground()
```

`IndicaKitColour` mirrors `WicketKit.TeamKitColour` one-for-one (same raw
values, asserted by test) so the domain layer never carries presentation
concerns and the design system never depends on storage.

## Navigation seam for Stats / Backup settings

`ContentView` is generic over an `AdditionalTabs` view and takes a
`@ViewBuilder additionalTabs:` closure. Extra tabs are appended after Setup and
inherit the Indica theme, the Dynamic Type clamp, and the shared error alert,
so wiring new screens needs no change inside `ContentView.swift`:

```swift
ContentView(
    model: .live(),
    additionalTabs: {
        NavigationStack { StatsView(stats: stats, teamNames: names) }
            .tabItem { Label("Stats", systemImage: "chart.bar") }

        NavigationStack { BackupSettingsView(store: store) }
            .tabItem { Label("Settings", systemImage: "gear") }
    }
)
```

`WicketTallyApp.swift` supplies the Stats and Data tabs through this seam.
`ContentView()` and `ContentView(model:)` remain available for previews.

The root theme also sets the SwiftUI colour scheme and preferred presentation
appearance for explicit Light, Dark, Sunlight, and festive choices. Automatic
still follows the system. Native navigation chrome, pickers, alerts, and sheet
controls therefore use the same light/dark appearance as the tokens, while
Lists and Forms use token backgrounds and row surfaces. Glance mode changes
both the scorer's own drawing tokens and its presentation to Sunlight.

## Accessibility contract

- **Dynamic Type**: components use semantic fonts (`.caption`, `.title3`, …)
  and `@ScaledMetric` padding. Metrics tokens are *baselines*, never frozen
  sizes; the app root keeps `.dynamicTypeSize(.xSmall ... .accessibility5)`.
- **VoiceOver**: the restyle preserved every existing label/value/hint.
  `IndicaTeamChip` keeps `accessibilityElement(children: .ignore)` plus the
  "Jersey colour <name>" label; decorative banner stripes and the trophy glow
  are `accessibilityHidden`.
- **Colour is never the only signal**: kit chips always render the colour name
  next to the swatch; status is carried by text (`Archived`), not hue.
- **Reduce Motion**: `IndicaScoreboardPanel` damps the trophy glow.
- **Hit targets**: every theme asserts `metrics.minimumHitTarget >= 44`
  (Sunlight raises it to 48).

## Contrast matrix

Measured by `IndicaColor.contrastRatio(to:)` (WCAG 2.1 relative luminance) and
regenerated by `Packages/IndicaTheme` test `contrast matrix evidence`.
Requirements: body text 4.5:1 (7:1 on Sunlight), large text and non-text UI
3:1. Chip rows cover the team-colour chips over every surface.

| Theme | Pair | Requirement | Measured |
| --- | --- | --- | --- |
| Indica Light | textPrimary on background | body text (4.5:1) | 17.58:1 |
| Indica Light | textPrimary on surface | body text (4.5:1) | 18.52:1 |
| Indica Light | textPrimary on surfaceElevated | body text (4.5:1) | 16.68:1 |
| Indica Light | textSecondary on background | body text (4.5:1) | 8.85:1 |
| Indica Light | textSecondary on surface | body text (4.5:1) | 9.32:1 |
| Indica Light | textSecondary on surfaceElevated | body text (4.5:1) | 8.40:1 |
| Indica Light | accentPrimary on background | body text (4.5:1) | 6.21:1 |
| Indica Light | accentPrimary on surface | body text (4.5:1) | 6.54:1 |
| Indica Light | accentSecondary on background | body text (4.5:1) | 5.76:1 |
| Indica Light | accentSecondary on surface | body text (4.5:1) | 6.07:1 |
| Indica Light | accentTertiary on background | body text (4.5:1) | 6.23:1 |
| Indica Light | positive on surface | body text (4.5:1) | 6.56:1 |
| Indica Light | warning on surface | body text (4.5:1) | 5.93:1 |
| Indica Light | destructive on surface | body text (4.5:1) | 6.54:1 |
| Indica Light | textOnAccent on accentPrimary | large text (3:1) | 6.21:1 |
| Indica Light | scorer action on accentPrimary | body text (4.5:1) | 6.21:1 |
| Indica Light | scorer wicket on destructive | body text (4.5:1) | 6.21:1 |
| Indica Light | bannerForeground on bannerBackground | body text (4.5:1) | 6.21:1 |
| Indica Light | scoreboardForeground on scoreboardBackground | body text (4.5:1) | 17.07:1 |
| Indica Light | trophyGlow on scoreboardBackground | non-text UI (3:1) | 11.93:1 |
| Indica Light | bannerStripe on bannerBackground | non-text UI (3:1) | 3.05:1 |
| Indica Light | separator on background | non-text UI (3:1) | 4.22:1 |
| Indica Light | separator on surface | non-text UI (3:1) | 4.45:1 |
| Indica Light | chip cricketRed label on fill | body text (4.5:1) | 5.46:1 |
| Indica Light | chip cricketRed fill on background | non-text UI (3:1) | 5.18:1 |
| Indica Light | chip saffron label on fill | body text (4.5:1) | 4.61:1 |
| Indica Light | chip saffron fill on background | non-text UI (3:1) | 4.38:1 |
| Indica Light | chip wicketGreen label on fill | body text (4.5:1) | 4.65:1 |
| Indica Light | chip wicketGreen fill on background | non-text UI (3:1) | 4.42:1 |
| Indica Light | chip royalPurple label on fill | body text (4.5:1) | 6.30:1 |
| Indica Light | chip royalPurple fill on background | non-text UI (3:1) | 5.98:1 |
| Indica Light | chip skyBlue label on fill | body text (4.5:1) | 5.02:1 |
| Indica Light | chip skyBlue fill on background | non-text UI (3:1) | 4.77:1 |
| Indica Light | chip marigold label on fill | body text (4.5:1) | 4.67:1 |
| Indica Light | chip marigold fill on background | non-text UI (3:1) | 4.44:1 |
| Indica Light | chip sunsetOrange label on fill | body text (4.5:1) | 4.62:1 |
| Indica Light | chip sunsetOrange fill on background | non-text UI (3:1) | 4.38:1 |
| Indica Light | chip peacockTeal label on fill | body text (4.5:1) | 5.59:1 |
| Indica Light | chip peacockTeal fill on background | non-text UI (3:1) | 5.30:1 |
| Indica Dark | textPrimary on background | body text (4.5:1) | 16.55:1 |
| Indica Dark | textPrimary on surface | body text (4.5:1) | 14.87:1 |
| Indica Dark | textPrimary on surfaceElevated | body text (4.5:1) | 13.30:1 |
| Indica Dark | textSecondary on background | body text (4.5:1) | 9.29:1 |
| Indica Dark | textSecondary on surface | body text (4.5:1) | 8.34:1 |
| Indica Dark | textSecondary on surfaceElevated | body text (4.5:1) | 7.46:1 |
| Indica Dark | accentPrimary on background | body text (4.5:1) | 6.76:1 |
| Indica Dark | accentPrimary on surface | body text (4.5:1) | 6.07:1 |
| Indica Dark | accentSecondary on background | body text (4.5:1) | 10.68:1 |
| Indica Dark | accentSecondary on surface | body text (4.5:1) | 9.60:1 |
| Indica Dark | accentTertiary on background | body text (4.5:1) | 10.01:1 |
| Indica Dark | positive on surface | body text (4.5:1) | 8.99:1 |
| Indica Dark | warning on surface | body text (4.5:1) | 10.55:1 |
| Indica Dark | destructive on surface | body text (4.5:1) | 6.68:1 |
| Indica Dark | textOnAccent on accentPrimary | large text (3:1) | 6.76:1 |
| Indica Dark | scorer action on accentPrimary | body text (4.5:1) | 6.76:1 |
| Indica Dark | scorer wicket on destructive | body text (4.5:1) | 7.43:1 |
| Indica Dark | bannerForeground on bannerBackground | body text (4.5:1) | 9.56:1 |
| Indica Dark | scoreboardForeground on scoreboardBackground | body text (4.5:1) | 17.90:1 |
| Indica Dark | trophyGlow on scoreboardBackground | non-text UI (3:1) | 12.51:1 |
| Indica Dark | bannerStripe on bannerBackground | non-text UI (3:1) | 4.94:1 |
| Indica Dark | separator on background | non-text UI (3:1) | 4.46:1 |
| Indica Dark | separator on surface | non-text UI (3:1) | 4.01:1 |
| Indica Dark | chip cricketRed label on fill | body text (4.5:1) | 4.62:1 |
| Indica Dark | chip cricketRed fill on background | non-text UI (3:1) | 4.16:1 |
| Indica Dark | chip saffron label on fill | body text (4.5:1) | 4.61:1 |
| Indica Dark | chip saffron fill on background | non-text UI (3:1) | 4.11:1 |
| Indica Dark | chip wicketGreen label on fill | body text (4.5:1) | 4.65:1 |
| Indica Dark | chip wicketGreen fill on background | non-text UI (3:1) | 4.07:1 |
| Indica Dark | chip royalPurple label on fill | body text (4.5:1) | 4.60:1 |
| Indica Dark | chip royalPurple fill on background | non-text UI (3:1) | 4.15:1 |
| Indica Dark | chip skyBlue label on fill | body text (4.5:1) | 4.62:1 |
| Indica Dark | chip skyBlue fill on background | non-text UI (3:1) | 4.17:1 |
| Indica Dark | chip marigold label on fill | body text (4.5:1) | 4.67:1 |
| Indica Dark | chip marigold fill on background | non-text UI (3:1) | 4.05:1 |
| Indica Dark | chip sunsetOrange label on fill | body text (4.5:1) | 4.62:1 |
| Indica Dark | chip sunsetOrange fill on background | non-text UI (3:1) | 4.10:1 |
| Indica Dark | chip peacockTeal label on fill | body text (4.5:1) | 4.63:1 |
| Indica Dark | chip peacockTeal fill on background | non-text UI (3:1) | 4.17:1 |
| Direct Sunlight | textPrimary on background | body text (4.5:1) | 21.00:1 |
| Direct Sunlight | textPrimary on surface | body text (4.5:1) | 21.00:1 |
| Direct Sunlight | textPrimary on surfaceElevated | body text (4.5:1) | 18.26:1 |
| Direct Sunlight | textSecondary on background | body text (4.5:1) | 11.20:1 |
| Direct Sunlight | textSecondary on surface | body text (4.5:1) | 11.20:1 |
| Direct Sunlight | textSecondary on surfaceElevated | body text (4.5:1) | 9.74:1 |
| Direct Sunlight | accentPrimary on background | body text (4.5:1) | 7.11:1 |
| Direct Sunlight | accentPrimary on surface | body text (4.5:1) | 7.11:1 |
| Direct Sunlight | accentSecondary on background | body text (4.5:1) | 7.12:1 |
| Direct Sunlight | accentSecondary on surface | body text (4.5:1) | 7.12:1 |
| Direct Sunlight | accentTertiary on background | body text (4.5:1) | 7.10:1 |
| Direct Sunlight | positive on surface | body text (4.5:1) | 7.10:1 |
| Direct Sunlight | warning on surface | body text (4.5:1) | 8.06:1 |
| Direct Sunlight | destructive on surface | body text (4.5:1) | 7.11:1 |
| Direct Sunlight | textOnAccent on accentPrimary | large text (3:1) | 7.11:1 |
| Direct Sunlight | scorer action on accentPrimary | body text (4.5:1) | 7.11:1 |
| Direct Sunlight | scorer wicket on destructive | body text (4.5:1) | 7.11:1 |
| Direct Sunlight | bannerForeground on bannerBackground | body text (4.5:1) | 21.00:1 |
| Direct Sunlight | scoreboardForeground on scoreboardBackground | body text (4.5:1) | 21.00:1 |
| Direct Sunlight | trophyGlow on scoreboardBackground | non-text UI (3:1) | 14.67:1 |
| Direct Sunlight | bannerStripe on bannerBackground | non-text UI (3:1) | 4.65:1 |
| Direct Sunlight | separator on background | non-text UI (3:1) | 17.40:1 |
| Direct Sunlight | separator on surface | non-text UI (3:1) | 17.40:1 |
| Direct Sunlight | chip cricketRed label on fill | body text (4.5:1) | 7.06:1 |
| Direct Sunlight | chip cricketRed fill on background | non-text UI (3:1) | 7.06:1 |
| Direct Sunlight | chip saffron label on fill | body text (4.5:1) | 7.07:1 |
| Direct Sunlight | chip saffron fill on background | non-text UI (3:1) | 7.07:1 |
| Direct Sunlight | chip wicketGreen label on fill | body text (4.5:1) | 7.09:1 |
| Direct Sunlight | chip wicketGreen fill on background | non-text UI (3:1) | 7.09:1 |
| Direct Sunlight | chip royalPurple label on fill | body text (4.5:1) | 7.01:1 |
| Direct Sunlight | chip royalPurple fill on background | non-text UI (3:1) | 7.01:1 |
| Direct Sunlight | chip skyBlue label on fill | body text (4.5:1) | 7.08:1 |
| Direct Sunlight | chip skyBlue fill on background | non-text UI (3:1) | 7.08:1 |
| Direct Sunlight | chip marigold label on fill | body text (4.5:1) | 7.00:1 |
| Direct Sunlight | chip marigold fill on background | non-text UI (3:1) | 7.00:1 |
| Direct Sunlight | chip sunsetOrange label on fill | body text (4.5:1) | 7.04:1 |
| Direct Sunlight | chip sunsetOrange fill on background | non-text UI (3:1) | 7.04:1 |
| Direct Sunlight | chip peacockTeal label on fill | body text (4.5:1) | 7.08:1 |
| Direct Sunlight | chip peacockTeal fill on background | non-text UI (3:1) | 7.08:1 |
| Festival of Lights | textPrimary on background | body text (4.5:1) | 16.61:1 |
| Festival of Lights | textPrimary on surface | body text (4.5:1) | 14.57:1 |
| Festival of Lights | textPrimary on surfaceElevated | body text (4.5:1) | 12.44:1 |
| Festival of Lights | textSecondary on background | body text (4.5:1) | 11.42:1 |
| Festival of Lights | textSecondary on surface | body text (4.5:1) | 10.02:1 |
| Festival of Lights | textSecondary on surfaceElevated | body text (4.5:1) | 8.55:1 |
| Festival of Lights | accentPrimary on background | body text (4.5:1) | 10.21:1 |
| Festival of Lights | accentPrimary on surface | body text (4.5:1) | 8.95:1 |
| Festival of Lights | accentSecondary on background | body text (4.5:1) | 8.40:1 |
| Festival of Lights | accentSecondary on surface | body text (4.5:1) | 7.36:1 |
| Festival of Lights | accentTertiary on background | body text (4.5:1) | 11.26:1 |
| Festival of Lights | positive on surface | body text (4.5:1) | 9.87:1 |
| Festival of Lights | warning on surface | body text (4.5:1) | 10.46:1 |
| Festival of Lights | destructive on surface | body text (4.5:1) | 7.02:1 |
| Festival of Lights | textOnAccent on accentPrimary | large text (3:1) | 10.21:1 |
| Festival of Lights | scorer action on accentPrimary | body text (4.5:1) | 10.21:1 |
| Festival of Lights | scorer wicket on destructive | body text (4.5:1) | 8.00:1 |
| Festival of Lights | bannerForeground on bannerBackground | body text (4.5:1) | 11.72:1 |
| Festival of Lights | scoreboardForeground on scoreboardBackground | body text (4.5:1) | 16.20:1 |
| Festival of Lights | trophyGlow on scoreboardBackground | non-text UI (3:1) | 13.75:1 |
| Festival of Lights | bannerStripe on bannerBackground | non-text UI (3:1) | 7.20:1 |
| Festival of Lights | separator on background | non-text UI (3:1) | 4.08:1 |
| Festival of Lights | separator on surface | non-text UI (3:1) | 3.58:1 |
| Festival of Lights | chip cricketRed label on fill | body text (4.5:1) | 4.88:1 |
| Festival of Lights | chip cricketRed fill on background | non-text UI (3:1) | 4.26:1 |
| Festival of Lights | chip saffron label on fill | body text (4.5:1) | 6.90:1 |
| Festival of Lights | chip saffron fill on background | non-text UI (3:1) | 6.02:1 |
| Festival of Lights | chip wicketGreen label on fill | body text (4.5:1) | 4.87:1 |
| Festival of Lights | chip wicketGreen fill on background | non-text UI (3:1) | 4.25:1 |
| Festival of Lights | chip royalPurple label on fill | body text (4.5:1) | 4.86:1 |
| Festival of Lights | chip royalPurple fill on background | non-text UI (3:1) | 4.24:1 |
| Festival of Lights | chip skyBlue label on fill | body text (4.5:1) | 4.87:1 |
| Festival of Lights | chip skyBlue fill on background | non-text UI (3:1) | 4.25:1 |
| Festival of Lights | chip marigold label on fill | body text (4.5:1) | 8.46:1 |
| Festival of Lights | chip marigold fill on background | non-text UI (3:1) | 7.38:1 |
| Festival of Lights | chip sunsetOrange label on fill | body text (4.5:1) | 5.87:1 |
| Festival of Lights | chip sunsetOrange fill on background | non-text UI (3:1) | 5.12:1 |
| Festival of Lights | chip peacockTeal label on fill | body text (4.5:1) | 4.83:1 |
| Festival of Lights | chip peacockTeal fill on background | non-text UI (3:1) | 4.21:1 |

## Evidence

```
cd Packages/IndicaTheme && swift test        # 14 tests, contrast audit + matrix
./scripts/check_indica_tokens.sh             # fails on hardcoded colours in any feature view
xcodebuild -scheme WicketTally -destination 'generic/platform=iOS Simulator' build
```

Layout/visual snapshot tests for the scorer and glance mode in the Sunlight
theme are **pending-human-field-check**: outdoor legibility needs a
real-sunlight check on device, and automated layout screenshots still need
an iPhone simulator UI-test target on the pinned Apple runner. The
token-level contrast audit above is automated and runs on every change.

## Feature-view token enforcement

`scripts/check_indica_tokens.sh` **auto-discovers every SwiftUI view under
`WicketTally/`** (excluding `WicketTally/Theme/`), so a newly added screen is
scanned the moment it lands. The gate fails CI on any hardcoded colour in
ContentView, Fixtures, Scorer, Stats, Backup, the rules editor, or future views.
The theme directory is the only place where colours are authored.

Detector coverage is self-tested: `.foregroundStyle(.orange)`,
`.foregroundStyle(.secondary)`, `.foregroundStyle(.white)`, `.tint(.indigo)`,
`Color.red`, `Color(red:…)` and `Color(hexRGB:)` are all caught.
