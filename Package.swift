// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XYLaunch",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "XYLaunch",
            targets: ["XYLaunch"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "XYLaunch"
        ),
    ]
)
