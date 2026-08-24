// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "keyboard-studio",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "KeyboardKit", targets: ["KeyboardKit"]),
    .library(name: "StatsCore", targets: ["StatsCore"]),
    .library(name: "NowPlaying", targets: ["NowPlaying"]),
    .executable(name: "kstudio", targets: ["kstudio"]),
    .executable(name: "KeyboardStudioApp", targets: ["KeyboardStudioApp"]),
  ],
  targets: [
    .target(name: "KeyboardKit", resources: [.copy("Resources/Devices"), .copy("Resources/Layouts")]),
    .target(name: "StatsCore"),
    .target(name: "NowPlaying"),
    .target(name: "StatsScreen", dependencies: ["KeyboardKit", "StatsCore", "NowPlaying"]),
    .executableTarget(name: "kstudio", dependencies: ["KeyboardKit", "StatsCore", "StatsScreen"]),
    .executableTarget(
      name: "KeyboardStudioApp",
      dependencies: ["KeyboardKit", "StatsCore", "StatsScreen", "NowPlaying"],
      resources: [.process("Resources")]),
    .testTarget(name: "KeyboardKitTests", dependencies: ["KeyboardKit"]),
    .testTarget(name: "StatsCoreTests", dependencies: ["StatsCore"]),
    .testTarget(name: "StatsScreenTests", dependencies: ["StatsScreen"]),
    .testTarget(name: "NowPlayingTests", dependencies: ["NowPlaying"]),
  ]
)
