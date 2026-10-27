// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "StillwaterCore", platforms: [.macOS(.v14)],
    products: [.library(name: "VaultCore", targets: ["VaultCore"])],
    targets: [
        .binaryTarget(name: "Clibsodium", path: "Vendor/Clibsodium.xcframework"),
        .target(name: "VaultCore", dependencies: ["Clibsodium"]),
        .testTarget(name: "VaultCoreTests", dependencies: ["VaultCore"])
    ])
