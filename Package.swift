// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacXplorer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MacXplorer", targets: ["MacXplorer"])
    ],
    targets: [
        .executableTarget(
            name: "MacXplorer",
            path: "Sources/MacXplorer"
        )
    ]
)
