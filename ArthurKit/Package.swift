// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ArthurKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ArthurKit", targets: ["ArthurKit"])
    ],
    targets: [
        .target(name: "ArthurKit", path: "Sources/ArthurKit")
    ]
)
