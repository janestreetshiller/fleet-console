import PackageDescription

let package = Package(
    name: "FleetConsole",
    platforms: [.macOS(.v14)],
    dependencies: [
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
            resources: [.copy("Brand/fleet-letter.png")],
            swiftSettings: [.swiftLanguageMode(.v6)],
            plugins: [.plugin(name: "VerifyDesignCore")]
        ),
        .testTarget(
            name: "FleetCoreTests",
            dependencies: ["FleetCore"]
        ),
        .testTarget(
            name: "FleetConsoleAppTests",
            dependencies: ["FleetConsoleApp"]
        ),
        .plugin(name: "VerifyDesignCore", capability: .buildTool()),
    ]
)
