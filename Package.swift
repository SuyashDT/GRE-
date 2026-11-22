// swift-tools-version: 5.10
import PackageDescription

var products: [Product] = [
    .library(name: "GRECore", targets: ["GRECore"]),
]

var targets: [Target] = [
    // Platform-independent logic and content: models, scoring, adaptive routing,
    // spaced repetition, calculator, progress storage and essay grading.
    // Builds and tests on Linux as well as macOS.
    .target(
        name: "GRECore",
        resources: [.copy("Resources/Content")]
    ),
    .testTarget(
        name: "GRECoreTests",
        dependencies: ["GRECore"]
    ),
]

#if os(macOS)
// The SwiftUI app itself only builds on macOS.
products.append(.executable(name: "GREPrep", targets: ["GREPrep"]))
targets.append(
    .executableTarget(
        name: "GREPrep",
        dependencies: ["GRECore"],
        exclude: ["Info.plist"]
    )
)
#endif

let package = Package(
    name: "GREPrep",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
