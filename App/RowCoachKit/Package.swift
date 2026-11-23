// swift-tools-version: 6.0
// RowCoachKit: plattformunabhängige Logik (Protokoll-Parser, Modelle, später Session und Strecke).
// Ohne CoreBluetooth/HealthKit, damit die Tests auch ohne Gerät laufen.
import PackageDescription

let package = Package(
    name: "RowCoachKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "RowCoachKit", targets: ["RowCoachKit"])],
    targets: [
        .target(name: "RowCoachKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "RowCoachKitTests", dependencies: ["RowCoachKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
