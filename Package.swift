// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Vidindir",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "Vidindir", targets: ["Vidindir"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            exact: "0.10.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Vidindir",
            path: "Sources/Vidindir"
        ),
        .testTarget(
            name: "VidindirTests",
            dependencies: [
                "Vidindir",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/VidindirTests"
        ),
    ]
)
