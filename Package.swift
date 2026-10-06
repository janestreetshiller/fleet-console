// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FleetConsole",
    platforms: [.macOS(.v14)],
    dependencies: [
        // The app's only external dependency, and it buys one thing this package
        // cannot honestly fake: a real VT100/xterm emulator for the chrome's
        // terminal and Yazi panels. Kept off FleetCore, fleetd and fleetctl so
        // the daemon and CLI stay dependency-free.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.15.0"),
    ],
    targets: [
        .target(
            name: "FleetCore",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "fleetd",
            dependencies: ["FleetCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "fleetctl",
            dependencies: ["FleetCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "FleetConsoleApp",
            dependencies: ["FleetCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FleetCoreTests",
            dependencies: ["FleetCore"]
        ),
    ]
)
