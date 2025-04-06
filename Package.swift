// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RunningApplicationKit",
    platforms: [.macOS(.v11)],
    products: [
        .library(
            name: "RunningApplicationKit",
            targets: ["RunningApplicationKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/MxIris-Reverse-Engineering/LaunchServicesPrivate", branch: "main"),
    ],
    targets: [
        .target(
            name: "RunningApplicationKit",
            dependencies: [
                .product(name: "LaunchServicesPrivate", package: "LaunchServicesPrivate")
            ]
        ),
    ]
)
