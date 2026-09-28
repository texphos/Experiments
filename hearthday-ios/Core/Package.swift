// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HearthdayCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HearthdayCore", targets: ["HearthdayCore"]),
    ],
    targets: [
        .target(name: "HearthdayCore"),
        .executableTarget(name: "hearthday-fixtures", dependencies: ["HearthdayCore"]),
        .testTarget(name: "HearthdayCoreTests", dependencies: ["HearthdayCore"]),
    ]
)
