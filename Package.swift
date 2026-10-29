// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Arafel",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Arafel", path: "Sources/Arafel")
    ],
    // Swift 5 mode: Core Image types aren't Sendable, so Swift 6 checking only adds noise.
    swiftLanguageModes: [.v5]
)
