// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "copyWorld",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "copyWorld"
        ),
        .testTarget(
            name: "copyWorldTests",
            dependencies: ["copyWorld"]
        ),
    ]
)
