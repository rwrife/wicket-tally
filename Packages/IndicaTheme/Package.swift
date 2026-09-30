// swift-tools-version:6.0
import PackageDescription

// Test harness for the Indica design system.
//
// The canonical sources live in `WicketTally/Theme` (compiled into the app
// target by the Xcode file-system-synchronized group). `Sources/IndicaTheme`
// is a symlink to that directory so the *same* token files can be unit-tested
// with `swift test` on macOS/CI without duplicating them.
let package = Package(
    name: "IndicaTheme",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "IndicaTheme", targets: ["IndicaTheme"]),
    ],
    targets: [
        .target(name: "IndicaTheme"),
        .testTarget(name: "IndicaThemeTests", dependencies: ["IndicaTheme"]),
    ]
)
