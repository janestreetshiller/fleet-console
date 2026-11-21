import PackageDescription

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
