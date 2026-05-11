[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Apple Platforms](https://github.com/21-DOT-DEV/swift-event/actions/workflows/apple-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-event/actions/workflows/apple-builds.yml) [![Docker Builds](https://github.com/21-DOT-DEV/swift-event/actions/workflows/docker-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-event/actions/workflows/docker-builds.yml)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F21-DOT-DEV%2Fswift-event%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/21-DOT-DEV/swift-event) [![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F21-DOT-DEV%2Fswift-event%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/21-DOT-DEV/swift-event)

# 🌐 swift-event

Modern Swift bindings for [libevent](https://github.com/libevent/libevent) — a type-safe Swift 6.1 async/await API over `kqueue` on Apple platforms and `epoll` on Linux, plus a raw `libevent` product other Swift packages can link when they need libevent primitives directly.

📚 [Documentation](https://docs.21.dev/documentation/event/)

> [!CAUTION]
> This package is pre-1.0 ([SemVer major version zero](https://semver.org/#spec-item-4)). The public API should not be considered stable and may change with any release. Pin a version using `exact:` to avoid unexpected breaking changes. See the [Production Considerations](Sources/Event/Event.docc/ProductionConsiderations.md) guide for the concurrency model, resource-ownership rules, and the list of capabilities not yet shipping.

## Why swift-event?

`Event` is a thin, libevent-direct, async/await wrapper. It is not a replacement for [SwiftNIO](https://github.com/apple/swift-nio) — reach for NIO when you need channel pipelines, HTTP/2 / WebSocket / TLS out of the box, or back-pressure-aware protocol handlers. Reach for `Event` when you want minimal abstraction over the platform I/O multiplexer, a small dependency surface, or tight interop with C code that already speaks libevent. For packages like [swift-tor](https://github.com/21-DOT-DEV/swift-tor) that embed C code calling `event_base_*` / `evbuffer_*` symbols, the raw `libevent` product provides a statically linked, vendor-controlled runtime.

## Features

- **Async TCP client and server** with `async`/`await`: `Socket.connect`, `Socket.listen`, `ServerSocket.connections` (`AsyncThrowingStream`).
- **Platform-optimal multiplexer** — `kqueue` on Apple platforms, `epoll` on Linux — verified at runtime and enforced by the `EventLoop uses optimal backend` test.
- **libevent 2.1.12 statically vendored** via [subtree](https://github.com/21-DOT-DEV/subtree) — no system libevent dependency at runtime.
- **Raw `libevent` C binding product** for Swift packages that need libevent's full surface — used by [swift-tor](https://github.com/21-DOT-DEV/swift-tor) for its Tor daemon.
- **Swift 6.1 strict concurrency**, documented single-owner handoff invariant, zero raw `OpaquePointer` leakage in the public API.

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/21-DOT-DEV/swift-event.git", from: "0.2.1"),
```

> [!WARNING]
> Because the package is pre-1.0, prefer pinning with `exact:` instead of `from:` if you want to lock to a specific minor version (e.g. `exact: "0.2.1"`). `from:` will accept any 0.x release ≥ 0.2.1, and 0.x releases may include breaking changes per [SemVer 0.y.z](https://semver.org/#spec-item-4) semantics.

Include `Event` in your target:

```swift
.target(name: "<target>", dependencies: [
    .product(name: "Event", package: "swift-event"),
]),
```

Or use Xcode: **File → Add Packages…**, then enter `https://github.com/21-DOT-DEV/swift-event`.

## Quick Start

```swift
import Event

let loop = EventLoop()
print(loop.backendMethod)
// kqueue   (on macOS / iOS / tvOS / watchOS / visionOS)
// epoll    (on Linux)
```

*→ Full API: [docs.21.dev/documentation/event/eventloop](https://docs.21.dev/documentation/event/eventloop)*

For **TCP client and server walkthroughs**, **IPv6 addresses**, and the **product-selection guide** (`Event` vs `libevent`), explore the hosted documentation:

- [Getting Started](https://docs.21.dev/documentation/event/gettingstarted) — task-oriented walkthrough of every shipping capability
- [Backend & Platforms](https://docs.21.dev/documentation/event/backendandplatforms) — the `kqueue` / `epoll` story and the runtime invariant that enforces it
- [Production Considerations](https://docs.21.dev/documentation/event/productionconsiderations) — pre-1.0 caveats, concurrency model, capabilities not yet shipping

Every example in the DocC catalog under [`Sources/Event/Event.docc/`](Sources/Event/Event.docc/) is backed by an executable SwiftPM snippet, so nothing drifts from the code. Build the full hyperlinked archive locally with `swift package generate-documentation --target Event`.

## Requirements

| Tool | Minimum version |
| --- | --- |
| Swift | 6.1 |
| Xcode | 16.3 |
| macOS | 13 |
| iOS / iPadOS | 16 |
| tvOS | 16 |
| watchOS | 9 |
| visionOS | 1 |
| Linux | Ubuntu 22.04+ (glibc) |

## Contributing

Bug reports and pull requests are welcome. Start with:

- [AGENTS.md](AGENTS.md) — project architecture, Swift-target boundaries, extraction flow.
- [Vendor/AGENTS.md](Vendor/AGENTS.md) — libevent subtree sync rules.
- [21-DOT-DEV contributing guidelines](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) — branching and commit conventions.

## Security

For vulnerability reports, follow the private-disclosure process in [the 21-DOT-DEV SECURITY.md](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md). For shipped-today caveats — concurrency model, pre-1.0 SemVer status, and the list of capabilities not yet wrapped (TLS, UDP, timeouts, IPv6 server bind, cancellation) — see the [Production Considerations](Sources/Event/Event.docc/ProductionConsiderations.md) guide.

## License

Released under the MIT License — see [LICENSE](LICENSE). libevent itself is licensed under the [3-clause BSD License](https://github.com/libevent/libevent/blob/master/LICENSE).
