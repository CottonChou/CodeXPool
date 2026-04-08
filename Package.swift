// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeXPool",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeXPool", targets: ["CodeXPool"])
    ],
    targets: [
        .executableTarget(
            name: "CodeXPool",
            path: "Sources/CodeXPool",
            exclude: [
                "CodeXPool.icon",
                "Info-iOS.plist",
                "Info-macOS.plist"
            ],
            resources: [
                .process("Resources/LaunchScreen.storyboard"),
                .process("Resources/figure.pool.swim.png"),
                .process("Resources/de.lproj"),
                .process("Resources/en.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/fr.lproj"),
                .process("Resources/it.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/ko.lproj"),
                .process("Resources/nl.lproj"),
                .process("Resources/ru.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/zh-Hant.lproj"),
                .process("Resources/proxyd-src"),
                .copy("Resources/proxyd-prebuilt-archives"),
                .copy("Resources/proxyd-prebuilt")
            ]
        ),
        .testTarget(
            name: "CodeXPoolTests",
            dependencies: ["CodeXPool"],
            path: "Tests/CodeXPoolTests"
        )
    ]
)
