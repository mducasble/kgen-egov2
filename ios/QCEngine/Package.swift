// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "QCEngine",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "QCEngine", targets: ["QCEngine"]),
    ],
    targets: [
        .target(name: "QCEngine"),
        .testTarget(name: "QCEngineTests", dependencies: ["QCEngine"]),
    ]
)
