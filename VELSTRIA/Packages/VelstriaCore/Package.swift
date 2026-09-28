// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VelstriaCore",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VelstriaCore", targets: ["VelstriaCore"]),
    ],
    targets: [
        .target(
            name: "VelstriaCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VelstriaCoreTests",
            dependencies: ["VelstriaCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
