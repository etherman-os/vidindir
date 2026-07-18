// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Vidindir",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "VidindirDomain", targets: ["VidindirDomain"]),
        .library(name: "VidindirPersistence", targets: ["VidindirPersistence"]),
        .executable(name: "Vidindir", targets: ["Vidindir"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.10.0"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle.git",
            exact: "2.9.4"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            exact: "0.10.0"
        ),
    ],
    targets: [
        .target(
            name: "VidindirDomain",
            path: "Modules/Domain/Sources"
        ),
        .target(
            name: "VidindirPersistence",
            dependencies: [
                "VidindirDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Modules/Persistence/Sources"
        ),
        .executableTarget(
            name: "Vidindir",
            dependencies: [
                "VidindirDomain",
                "VidindirPersistence",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Vidindir"
        ),
        .testTarget(
            name: "VidindirDomainTests",
            dependencies: [
                "VidindirDomain",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Modules/Domain/Tests"
        ),
        .testTarget(
            name: "VidindirPersistenceTests",
            dependencies: [
                "VidindirDomain",
                "VidindirPersistence",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Modules/Persistence/Tests"
        ),
        .testTarget(
            name: "VidindirTests",
            dependencies: [
                "Vidindir",
                "VidindirDomain",
                "VidindirPersistence",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/VidindirTests"
        ),
    ]
)
