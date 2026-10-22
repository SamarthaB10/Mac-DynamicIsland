// swift-tools-version: 6.0
import Foundation
import PackageDescription

let rustLibraryPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .appendingPathComponent("core/target/link").path

let package = Package(
  name: "MacIsland",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "MacIsland", targets: ["MacIsland"])],
  targets: [
    .target(name: "IslandCore", publicHeadersPath: "include"),
    .executableTarget(
      name: "MacIsland", dependencies: ["IslandCore"],
      linkerSettings: [.unsafeFlags(["-L", rustLibraryPath, "-lisland_core"])]),
  ],
  swiftLanguageModes: [.v5]
)
