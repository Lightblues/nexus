// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NexusSync",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NexusSync", targets: ["NexusSync"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")],
    targets: [
        .target(name: "NexusSync", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "NexusSyncTests", dependencies: ["NexusSync"]),
    ]
)
