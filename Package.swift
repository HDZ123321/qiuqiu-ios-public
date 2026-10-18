// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HermesCore", platforms: [.macOS(.v13), .iOS(.v16)], products: [.library(name: "HermesCore", targets: ["HermesCore"])], targets: [
    .target(name: "HermesCore", path: "Sources/Core"),
    .target(name: "HermesTransport", dependencies: ["HermesCore"], path: "Sources/App", exclude: ["QiuQiuApp.swift", "CompanionView.swift"]),
    .testTarget(name: "HermesCoreTests", dependencies: ["HermesCore", "HermesTransport"], path: "Tests")
])
