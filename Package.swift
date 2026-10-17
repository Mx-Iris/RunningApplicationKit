// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RunningApplicationKit",
    platforms: [.macOS(.v12)],
    products: [
        .library(
            name: "RunningApplicationKit",
            targets: ["RunningApplicationKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Mx-Iris/swift-proc.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "RunningApplicationKit",
            dependencies: [
                .product(name: "ProcessInformation", package: "swift-proc"),
                .product(name: "ProcessInformationPrivate", package: "swift-proc"),
            ]
        ),
        .testTarget(
            name: "RunningApplicationKitTests",
            dependencies: ["RunningApplicationKit"]
        ),
    ],
    swiftLanguageModes: [.v6],
)
