// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swift-lambdacalculus",
    products: [
        .library(name: "LambdaCalculus", targets: ["LambdaCalculus"]),
        .executable(name: "lambda", targets: ["lambda"])
    ],
    targets: [
        .target(name: "LambdaCalculus", path: "Sources/LambdaCalculus"),
        .executableTarget(name: "lambda", dependencies: ["LambdaCalculus"], path: "Sources/lambda"),
        .testTarget(
            name: "LambdaCalculusTests",
            dependencies: ["LambdaCalculus"],
            path: "Tests/LambdaCalculusTests"
        )
    ]
)
