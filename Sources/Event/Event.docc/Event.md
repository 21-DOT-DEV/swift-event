# ``Event``

@Metadata {
    @TitleHeading("Framework")
}

Async TCP sockets and event-loop primitives for Swift, backed by a vendored build of [libevent](https://github.com/libevent/libevent).

## Overview

`Event` is the idiomatic Swift face of this package. It wraps libevent 2.1.12's event-dispatch machinery behind Swift 6.1 structured concurrency so you can write `async`/`await` code against non-blocking TCP sockets on macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, visionOS 1+, and Linux (Ubuntu 22.04+). The package selects the most efficient I/O multiplexer available at runtime — **kqueue** on Apple platforms, **epoll** on Linux — and exposes it through a small, typed surface with no raw `OpaquePointer` leakage.

Direct-use capabilities shipping today:

- **Event-loop control** — create a loop, drive it per-operation or long-lived, inspect the backend. See ``EventLoop``.
- **Async TCP client** — `async throws` `connect` / `read` / `write` / `close`. See ``Socket``.
- **Async TCP server** — `bind` / `listen` / `accept` and an `AsyncThrowingStream` of incoming connections. See ``ServerSocket``.
- **Address construction** — numeric IPv4 / IPv6 / wildcard factories over `sockaddr_storage`. See ``SocketAddress``.

```swift
import Event

let loop = EventLoop()
print(loop.backendMethod)
// kqueue   (on macOS / iOS / tvOS / watchOS / visionOS)
// epoll    (on Linux)
```

### Foundation Runtime for Swift Network Stacks

Beyond its direct API, this package ships the raw `libevent` C binding product that other Swift packages link against when they need libevent primitives this Swift API hasn't wrapped yet (timer events via `evtimer_*`, signal events via `evsignal_*`, custom bufferevents, DNS resolution via `evdns_*`). The concrete example is [`swift-tor`](https://github.com/21-DOT-DEV/swift-tor), whose `libtor` target depends on `libevent` (from this package) alongside `libcrypto` / `libssl` (from [`swift-openssl`](https://github.com/21-DOT-DEV/swift-openssl)) to build a Swift-native Tor daemon. See <doc:ChoosingLibeventVsEvent> for product-selection guidance.

API positioning: `Event` is a thin, libevent-direct, async/await wrapper. It is not a replacement for [SwiftNIO](https://github.com/apple/swift-nio) — if you need NIO's channel pipelines, back-pressure protocol handlers, or HTTP/2 / WebSocket / TLS off-the-shelf, reach for NIO. Reach for `Event` when you want minimal abstraction over the platform multiplexer, a small dependency surface, or tight interop with C code that already speaks libevent.

## Topics

### Essentials

- <doc:GettingStarted>
- ``EventLoop``
- ``Socket``
- ``ServerSocket``

### Addresses

- ``SocketAddress``

### Errors

- ``SocketError``

### Guides

- <doc:ChoosingLibeventVsEvent>

### Concepts

- <doc:BackendAndPlatforms>
- <doc:ProductionConsiderations>
