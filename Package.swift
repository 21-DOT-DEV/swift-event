// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-event",
    products: [
        .library(name: "libevent", targets: ["libevent"])
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.7")
    ],
    targets: [
        .target(
            name: "libevent",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "libeventTests",
            dependencies: ["libevent"]
        )
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .gnu89
)
