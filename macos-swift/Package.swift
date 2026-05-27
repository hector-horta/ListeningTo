// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ListeningTo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ListeningTo", targets: ["ListeningTo"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ListeningTo",
            dependencies: [],
            path: "Sources/ListeningTo"
        )
    ]
)
