// swift-tools-version: 6.0
// Server für Online-Rennen (docs/MULTIPLAYER.md „Server (Blaze)“): Aggregator der Feldübersicht, Ergebnisse
// festschreiben mit Plausibilitätsprüfung, virtuelle Teilnehmende auffüllen, Abo-Prüfung (Platzhalter).
// Swift auf Linux mit RowCoachKit – dieselbe Logik wie in der App, Ergebnisse bitgleich (DetMath), kein Nachbau.
// Läuft als Cloud-Run-Job (kein HTTP-Server nötig); spricht Firestore und Realtime Database über REST.
// Bauen/Testen auf Linux: `cd server && swift test`; Container: server/Dockerfile (Kontext = Repo-Wurzel).
import PackageDescription

let package = Package(
    name: "RowCoachServer",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "rowcoach-server", targets: ["rowcoach-server"])],
    dependencies: [.package(path: "../App/RowCoachKit")],
    targets: [
        .target(name: "RowCoachServerCore", dependencies: ["RowCoachKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "rowcoach-server", dependencies: ["RowCoachServerCore", "RowCoachKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "RowCoachServerCoreTests", dependencies: ["RowCoachServerCore", "RowCoachKit"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
