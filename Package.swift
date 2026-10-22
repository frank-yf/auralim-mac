// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuskShift",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DuskShift", targets: ["DuskShift"])],
    targets: [
        .target(name: "DuskShiftCore"),
        .executableTarget(name: "DuskShift", dependencies: ["DuskShiftCore"], resources: [.process("Resources")]),
        .testTarget(name: "DuskShiftCoreTests", dependencies: ["DuskShiftCore"]),
        .testTarget(name: "DuskShiftTests", dependencies: ["DuskShift"])
    ]
)
