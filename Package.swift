// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirDraw",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AirDraw",
            path: "Sources/AirDraw"
        )
    ]
)
