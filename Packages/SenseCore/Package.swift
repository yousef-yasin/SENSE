// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SenseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SenseCore", targets: ["SenseCore"])
    ],
    targets: [
        .target(name: "SenseCore"),
        .testTarget(name: "SenseCoreTests", dependencies: ["SenseCore"])
    ]
)
