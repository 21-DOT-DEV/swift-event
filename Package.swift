// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-event",
    products: [
        .library(name: "libevent", targets: ["libevent"]),
        .library(name: "Event", targets: ["Event"])
    ],
    dependencies: Package.Dependency.developmentDependencies,
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

extension Package.Dependency {
    /// Development-only dependencies, excluded at tagged releases.
    ///
    /// When resolved at a tagged release, development tools (subtree sync tooling, etc.)
    /// are excluded so consumers aren't forced to download them.
    static var developmentDependencies: [Package.Dependency] {
        guard Context.gitInformation?.currentTag == nil else { return [] }
        return [
            .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.13")
        ]
    }
}
