// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Configuration",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MudConfiguration", targets: ["MudConfiguration"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "MudConfiguration",
            dependencies: [
                .product(name: "MudCore", package: "Core"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MudConfigurationTests",
            dependencies: ["MudConfiguration"],
            path: "Tests"
        ),
    ]
)
