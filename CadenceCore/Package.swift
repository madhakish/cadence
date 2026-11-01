// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CadenceCore",
    // String form: a tools bump would also have to move the Linux swift:5.10 container.
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS("26.0")],
    products: [
        .library(name: "CadenceCore", targets: ["CadenceCore"]),
        // Local detector evaluation over exported motion recordings (#337).
        .executable(name: "cadence-motion-eval", targets: ["MotionEval"]),
    ],
    targets: [
        .target(name: "CadenceCore"),
        .executableTarget(name: "MotionEval", dependencies: ["CadenceCore"]),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"]),
    ]
)
