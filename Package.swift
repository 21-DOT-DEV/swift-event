// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-event",
    products: [
        .library(name: "libevent", targets: ["libevent"]),
        .library(name: "Event", targets: ["Event"])
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.7")
    ],
    targets: [
        .target(
            name: "libevent",
            linkerSettings: [
                .linkedLibrary("bsd", .when(platforms: [.linux]))
            ]
        ),
        .target(
            name: "Event",
            dependencies: ["libevent"]
        ),
        .testTarget(
            name: "libeventTests",
            dependencies: ["libevent"]
        ),
        .testTarget(
            name: "EventTests",
            dependencies: ["Event"]
        )
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .gnu89
)
