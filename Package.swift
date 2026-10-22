// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuskShift",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DuskShift", targets: ["DuskShift"])],
    targets: [
        .target(name: "DuskShiftCore"),
        .executableTarget(name: "DuskShift", dependencies: ["DuskShiftCore"]),
        .testTarget(name: "DuskShiftCoreTests", dependencies: ["DuskShiftCore"]),
        .testTarget(name: "DuskShiftTests", dependencies: ["DuskShift"])
    ]
)
