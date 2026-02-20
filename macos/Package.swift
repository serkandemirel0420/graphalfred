// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GraphAlfred",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GraphAlfred", targets: ["GraphAlfredApp"])
    ],
    targets: [
        .executableTarget(
            name: "GraphAlfredApp",
            path: "Sources/GraphAlfredApp"
        )
    ]
)
