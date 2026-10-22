// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Auralim",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Auralim", targets: ["Auralim"])],
    targets: [
        .target(name: "CZoneDetect"),
        .target(name: "AuralimCore", dependencies: ["CZoneDetect"], resources: [.process("Resources")]),
        .executableTarget(name: "Auralim", dependencies: ["AuralimCore"], resources: [.process("Resources")]),
        .testTarget(name: "AuralimCoreTests", dependencies: ["AuralimCore"]),
        .testTarget(name: "AuralimTests", dependencies: ["Auralim"])
    ]
)
