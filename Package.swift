// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DynamacIsland",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DynamacIsland", targets: ["DynamacIsland"])],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(
            name: "DynamacIsland",
            dependencies: ["IslandCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
