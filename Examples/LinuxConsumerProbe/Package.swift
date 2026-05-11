// swift-tools-version: 6.1
import PackageDescription

// External-consumer regression coverage for swift-event's `libevent`
// modulemap. Three targets exercise the three real consumption paths:
//
//   1. CxxConsumer — pure C++ target with `#include <event2/event.h>`.
//      Catches modulemap regressions that re-claim event2/*.h (e.g.
//      reverting to `umbrella "."`), which would error with
//      "module 'libevent' is incompatible with feature 'cplusplus'".
//
//   2. SwiftConsumer — plain Swift target with `import libevent`.
//      Catches regressions that leave the libevent module empty
//      (e.g. dropping the shim header from the modulemap), which
//      would silently break access to libevent C symbols from Swift.
//
//   3. SwiftCxxInteropConsumer + CxxLibeventShim — Swift target with
//      `.interoperabilityMode(.Cxx)` consuming a C++ shim that
//      `#include`s event2/*.h. Mirrors the swift-bitcoin path exactly:
//      Swift C++ interop forces -fmodules in C++ mode, so this is the
//      path that broke swift-bitcoin in swift-event 0.2.0.
//
// All targets depend on swift-event via `path: "../.."`, so the probe
// always builds against the working tree.

let package = Package(
    name: "LinuxConsumerProbe",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "CxxConsumer", targets: ["CxxConsumer"]),
        .library(name: "SwiftConsumer", targets: ["SwiftConsumer"]),
        .library(name: "SwiftCxxInteropConsumer", targets: ["SwiftCxxInteropConsumer"]),
    ],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(
            name: "CxxConsumer",
            dependencies: [.product(name: "libevent", package: "swift-event")]
        ),
        .target(
            name: "SwiftConsumer",
            dependencies: [.product(name: "libevent", package: "swift-event")]
        ),
        .target(
            name: "CxxLibeventShim",
            dependencies: [.product(name: "libevent", package: "swift-event")]
        ),
        .target(
            name: "SwiftCxxInteropConsumer",
            dependencies: ["CxxLibeventShim"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
