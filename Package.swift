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
            exclude: ["src/arc4random.c"],
            cSettings: [
                // Enable GNU extensions on Linux (glibc features like gethostbyname_r)
                .define("_GNU_SOURCE", .when(platforms: [.linux])),
            ]
            // Note: For optimized builds in downstream projects, consider adding:
            // swiftSettings: [.unsafeFlags(["-Xcc", "-fvisibility=hidden"])]
            // This reduces binary size and improves load times, but unsafeFlags
            // prevents use as a transitive dependency in other packages.
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
