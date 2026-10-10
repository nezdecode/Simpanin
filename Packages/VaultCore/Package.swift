// swift-tools-version: 6.2
// Tools 6.x builds in the Swift 6 language mode, which turns on complete strict
// concurrency checking.

import PackageDescription

let package = Package(
    name: "VaultCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "VaultCore", targets: ["VaultCore"])
    ],
    dependencies: [
        // The only third-party dependency allowed. On Apple platforms it re-exports
        // CryptoKit. Never add the CryptoExtras product: it bundles BoringSSL.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "VaultCore",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VaultCoreTests",
            dependencies: ["VaultCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
