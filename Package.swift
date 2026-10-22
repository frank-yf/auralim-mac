// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Auralim",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Auralim", targets: ["Auralim"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "CZoneDetect"),
        .target(name: "AuralimCore", dependencies: ["CZoneDetect"], resources: [.process("Resources")]),
        .executableTarget(name: "Auralim", dependencies: ["AuralimCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "AuralimCoreTests", dependencies: ["AuralimCore"]),
        .testTarget(name: "AuralimTests", dependencies: ["Auralim"])
    ]
)
