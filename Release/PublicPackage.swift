// swift-tools-version: 6.0
import PackageDescription

// Public snapshot: the desktop UI and SwiftTerm are not part of this package.
let package = Package(
    name: "FleetConsoleCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FleetCore", targets: ["FleetCore"]),
        .executable(name: "fleetd", targets: ["fleetd"]),
        .executable(name: "fleetctl", targets: ["fleetctl"]),
    ],
    targets: [
        .target(name: "FleetCore", swiftSettings: [.swiftLanguageMode(.v6)],
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "fleetd", dependencies: ["FleetCore"],
                          swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "fleetctl", dependencies: ["FleetCore"],
                          swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "FleetCoreTests", dependencies: ["FleetCore"]),
    ]
)
