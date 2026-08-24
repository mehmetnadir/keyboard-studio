// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "keyboard-studio",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "K86Kit", targets: ["K86Kit"]),
    .executable(name: "kstudio", targets: ["kstudio"]),
  ],
  targets: [
    .target(name: "K86Kit"),
    .executableTarget(name: "kstudio", dependencies: ["K86Kit"]),
    .testTarget(name: "K86KitTests", dependencies: ["K86Kit"]),
  ]
)
