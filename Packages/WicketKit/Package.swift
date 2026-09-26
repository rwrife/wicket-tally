// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WicketKit",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "WicketKit", targets: ["WicketKit"]),
        .library(name: "WicketStore", targets: ["WicketStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "WicketKit",
            dependencies: []
        ),
        .target(
            name: "WicketStore",
            dependencies: [
                "WicketKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "WicketKitTests",
            dependencies: ["WicketKit"]
        ),
        .testTarget(
            name: "WicketStoreTests",
            dependencies: [
                "WicketStore",
                "WicketKit",
            ],
            resources: [
                .copy("Fixtures/wicket-store-v1.sqlite"),
            ]
        ),
    ]
)
