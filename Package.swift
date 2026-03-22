// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Copool",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Copool", targets: ["Copool"])
    ],
    targets: [
        .executableTarget(
            name: "Copool",
            path: "Sources/Copool",
            exclude: [
                "Copool.icon"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CopoolTests",
            dependencies: ["Copool"],
            path: "Tests/CopoolTests"
        )
    ]
)
