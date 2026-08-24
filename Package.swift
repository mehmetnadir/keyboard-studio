// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "keyboard-studio",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "K86Kit", targets: ["K86Kit"]),
    .library(name: "StatsCore", targets: ["StatsCore"]),
    .executable(name: "kstudio", targets: ["kstudio"]),
    .executable(name: "KeyboardStudioApp", targets: ["KeyboardStudioApp"]),
  ],
  targets: [
    .target(name: "K86Kit"),
    .target(name: "StatsCore"),
    .target(name: "StatsScreen", dependencies: ["K86Kit", "StatsCore"]),
    .executableTarget(name: "kstudio", dependencies: ["K86Kit", "StatsCore", "StatsScreen"]),
    .executableTarget(name: "KeyboardStudioApp", dependencies: ["K86Kit", "StatsCore", "StatsScreen"]),
    .testTarget(name: "K86KitTests", dependencies: ["K86Kit"]),
    .testTarget(name: "StatsCoreTests", dependencies: ["StatsCore"]),
    .testTarget(name: "StatsScreenTests", dependencies: ["StatsScreen"]),
  ]
)
