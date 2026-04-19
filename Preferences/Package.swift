// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Preferences",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MudPreferences", targets: ["MudPreferences"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "MudPreferences",
            dependencies: [
                .product(name: "MudCore", package: "Core"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MudPreferencesTests",
            dependencies: ["MudPreferences"],
            path: "Tests"
        ),
    ]
)
