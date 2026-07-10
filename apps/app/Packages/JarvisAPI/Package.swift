// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JarvisAPI",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "JarvisAPI", targets: ["JarvisAPI"])
    ],
    targets: [
        .target(name: "JarvisAPI"),
        .testTarget(name: "JarvisAPITests", dependencies: ["JarvisAPI"]),
    ]
)
