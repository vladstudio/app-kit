// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacAppKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MacAppKit", targets: ["MacAppKit"]),
    ],
    targets: [
        .target(name: "MacAppKit", path: "Sources/MacAppKit"),
    ]
)
