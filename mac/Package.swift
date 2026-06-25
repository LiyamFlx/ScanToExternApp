// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScanToExternApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The production app is a macOS .app bundle built in Xcode (see CLAUDE.md Phase 1.1)
        // This provides the core target for SPM builds / tests of non-UI logic.
        .library(name: "ScanToExternAppCore", targets: ["ScanToExternAppCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", from: "5.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/armadsen/ORSSerialPort", from: "2.1.0"),
    ],
    targets: [
        // Note: Full macOS app bundle (with LSUIElement, entitlements, custom Info.plist) 
        // must be built via Xcode project. This SPM target is for compiling core logic 
        // and libraries during development. Use Xcode to create macOS App target 
        // pointing at mac/ScanToExternApp sources, add the listed dependencies via SPM in Xcode.
        .target(
            name: "ScanToExternAppCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftyJSON", package: "SwiftyJSON"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "ORSSerial", package: "ORSSerialPort"),
            ],
            path: "ScanToExternApp",
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "ScanToExternAppTests",
            dependencies: ["ScanToExternAppCore"],
            path: "Tests/ScanToExternAppTests"
        )
    ]
)
