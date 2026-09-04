// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Yuhe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yuhe", targets: ["Yuhe"]),
    ],
    targets: [
        .executableTarget(
            name: "Yuhe",
            path: "Sources/Yuhe",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
