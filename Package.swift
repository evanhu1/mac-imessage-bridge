// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DelMacBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DelMacBridge", targets: ["DelMacBridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
    ],
    targets: [
        .executableTarget(
            name: "DelMacBridge",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
