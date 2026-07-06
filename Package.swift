// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mdview",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "mdview", resources: [.copy("Resources")])
    ]
)
