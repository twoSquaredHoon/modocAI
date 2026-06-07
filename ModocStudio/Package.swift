// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ModocStudio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ModocStudio", targets: ["ModocStudio"]),
    ],
    targets: [
        .executableTarget(
            name: "ModocStudio",
            path: "Sources/ModocStudio"
        ),
    ]
)
