// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ComebackCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ComebackCore", targets: ["ComebackCore"])
    ],
    targets: [
        .target(name: "ComebackCore"),
        .testTarget(name: "ComebackCoreTests", dependencies: ["ComebackCore"]),
    ]
)
