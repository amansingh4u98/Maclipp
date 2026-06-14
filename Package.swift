// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Maclipp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Maclipp", targets: ["Maclipp"])
    ],
    targets: [
        .executableTarget(
            name: "Maclipp",
            path: "Sources/Maclipp"
        )
    ]
)
