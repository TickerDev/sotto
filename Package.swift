// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SottoKit", platforms: [.macOS(.v14)], products: ["SottoAgent", "SottoProviders", "SottoTools", "SottoIntegrations", "SottoPersistence", "SottoSecurity", "SottoAudio", "SottoUI"].map { .library(name: $0, targets: [$0]) }, dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0"),
    .package(url: "https://github.com/Jakubantalik/Libraries.dev", branch: "main")
], targets: [
.target(name: "SottoTools"),
.target(name: "SottoSecurity", dependencies: ["SottoTools"]),
.target(name: "SottoProviders", dependencies: ["SottoTools"]),
.target(name: "SottoPersistence", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
.target(name: "SottoAgent", dependencies: ["SottoTools", "SottoSecurity", "SottoProviders"]),
.target(name: "SottoDocumentBridge", linkerSettings: [.linkedLibrary("z")]),
.target(name: "SottoIntegrations", dependencies: ["SottoTools", "SottoDocumentBridge"]),
.target(name: "SottoAudioBridge"),
.target(name: "SottoAudio", dependencies: ["SottoAudioBridge"]),
.target(name: "SottoUI", dependencies: ["SottoAgent", "SottoAudio", "SottoTools", "SottoSecurity", "SottoProviders", "SottoIntegrations", "SottoPersistence", .product(name: "VoiceGlowKit", package: "Libraries.dev")]),
.target(name: "SottoAudioBridgeFixtures", dependencies: ["SottoAudioBridge"], path: "Tests/SottoAudioBridgeFixtures"),
.testTarget(name: "SottoTests", dependencies: ["SottoAudioBridgeFixtures", "SottoAgent", "SottoProviders", "SottoSecurity", "SottoTools", "SottoPersistence", "SottoIntegrations", "SottoAudio", "SottoUI"], resources: [.copy("Fixtures/Documents")])
])
