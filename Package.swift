// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swift-lambdacalculus",
    products: [
        .library(name: "LambdaCalculus", targets: ["LambdaCalculus"])
    ],
    targets: [
        .target(name: "LambdaCalculus", path: "Sources/LambdaCalculus"),
        .testTarget(
            name: "LambdaCalculusTests",
            dependencies: ["LambdaCalculus"],
            path: "Tests/LambdaCalculusTests"
        )
    ]
)
