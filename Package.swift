// swift-tools-version: 6.2
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
    targets: [
        .target(
            name: "RunningApplicationKit"
        ),
    ],
    swiftLanguageModes: [.v6],
)
