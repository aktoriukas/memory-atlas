// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MemoryAtlas", platforms: [.macOS(.v14)], products: [.executable(name: "MemoryAtlas", targets: ["MemoryAtlas"])], targets: [.executableTarget(name: "MemoryAtlas", swiftSettings: [.swiftLanguageMode(.v5)])])
