// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiscScanner",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DiscScannerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DiscScanner",
            dependencies: ["DiscScannerCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DiscScannerCoreTests",
            dependencies: ["DiscScannerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
