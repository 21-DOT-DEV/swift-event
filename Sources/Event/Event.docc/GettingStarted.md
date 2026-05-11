# Getting Started with Event in Swift

@Metadata {
    @TitleHeading("Article")
}

A task-oriented walkthrough of the three shipping capabilities in `Event`: inspecting the I/O backend, writing an async TCP client, and writing an async TCP server.

## Overview

Each section below solves one concrete task. Every executable example comes from a file under `Snippets/` that compiles on every `swift build`, so the code you see here stays in lock-step with the public API.

### Adding Event to Your Project

Add `swift-event` as a Swift Package Manager dependency. Because the package is pre-1.0 and no version tag has been published yet, pin to the `main` branch:

```swift
// Package.swift
.package(url: "https://github.com/21-DOT-DEV/swift-event.git", branch: "main"),
```

```swift
// Target dependencies
.target(name: "<target>", dependencies: [
    .product(name: "Event", package: "swift-event"),
]),
```

Then `import Event` in any Swift file that needs it. For the raw `libevent` C binding product (used when linking libevent into another Swift package that exposes its own C sources), see <doc:ChoosingLibeventVsEvent>. For production-readiness caveats before depending on the package, read <doc:ProductionConsiderations>.

### Inspecting the Event-Loop Backend

Every ``EventLoop`` wraps a libevent `event_base` configured with the platform's most efficient I/O multiplexer. ``EventLoop/backendMethod`` returns the canonical method name; swift-event's own test suite asserts that this is `"kqueue"` on Apple platforms and `"epoll"` on Linux. See <doc:BackendAndPlatforms> for the per-platform story and the reasons other backends are excluded.

@Snippet(path: "swift-event/Snippets/EventLoopBackend")

Most applications will use ``EventLoop/shared``, a process-wide singleton, and never need to construct their own loop. Allocate a dedicated loop only when you need isolation — for example, in tests that must not contend with application traffic.

### Writing an Async TCP Client

``Socket`` exposes an async TCP client via two factory methods: ``Socket/connect(to:port:loop:timeout:)`` for numeric IPv4 endpoints and ``Socket/connect(to:loop:timeout:)`` for pre-built ``SocketAddress`` values (including IPv6). The returned `Socket` owns its file descriptor and is ready for ``Socket/read(maxBytes:timeout:)`` / ``Socket/write(_:timeout:)`` without additional setup.

@Snippet(path: "swift-event/Snippets/EchoClient")

The example above assumes a server is listening on `127.0.0.1:8080`. All four operations (`connect`, `write`, `read`, `close`) are `async throws`; errors surface through ``SocketError`` with a raw errno payload you can pattern-match to distinguish transient failures from permanent ones.

### Writing an Async TCP Server

The server side exposes a ``ServerSocket`` produced by ``Socket/listen(port:backlog:loop:)``. Accept connections one at a time with ``ServerSocket/accept()``, or iterate the ``ServerSocket/connections`` async stream to service each client as it arrives.

@Snippet(path: "swift-event/Snippets/EchoServer")

The `connections` stream is the idiomatic entry point for long-running servers — it composes with Swift structured concurrency so you can dispatch each accepted client onto a child task. Cancellation of the outer task terminates the `for try await` loop but does not currently unregister the outstanding libevent accept callback; call ``ServerSocket/close()`` or drop the last strong reference to the `ServerSocket` to fully tear the listener down. See <doc:ProductionConsiderations>.

### Detecting Socket Close and Errors

In an `async`/`await` socket API there is no "register a close handler" step — the close event arrives through the same `try`/`catch` you already use for I/O. ``Socket/read(maxBytes:timeout:)`` throws ``SocketError/connectionClosed`` when the peer performs an orderly shutdown (`read(2)` returns 0), and ``SocketError/readFailed(_:)`` (with the raw `errno` payload) when the transport breaks. ``Socket/write(_:timeout:)`` throws ``SocketError/writeFailed(_:)`` for write-side failures (e.g. `EPIPE`). Both throw ``SocketError/timeout`` when their optional `timeout:` parameter elapses.

The idiomatic shape for "consume bytes until the peer closes" is a single `do { while true { … } } catch` — no observer, no callback registration, and no separate close hook to wire up:

```swift
do {
    while true {
        let chunk = try await socket.read()
        process(chunk)
    }
} catch SocketError.connectionClosed {
    // Peer closed cleanly — terminate the read loop.
} catch SocketError.timeout {
    // Optional timeout elapsed — decide whether to retry or give up.
} catch SocketError.readFailed(let errno) {
    // Transport-level failure (e.g. ECONNRESET). The errno payload is from
    // the failing read(2) syscall; pass through strerror(_:) for a message.
    log("read failed: \(String(cString: strerror(errno)))")
} catch {
    // Cancellation or unrelated thrown error.
    throw error
}
```

If you need to bound how long a single read waits, pass `timeout:` directly:

```swift
let chunk = try await socket.read(timeout: .seconds(5))
```

The same pattern applies to ``Socket/write(_:timeout:)`` and ``Socket/connect(to:loop:timeout:)`` — every async I/O call in `Event` accepts an optional `timeout:` and surfaces ``SocketError/timeout`` on expiry. The socket itself remains usable for retry; the partial-write case is documented in <doc:ProductionConsiderations>.

### Scheduling Timers on the Event Loop

When you need a delay or a one-shot future task that shares scheduling with the same multiplexer driving your I/O, use ``EventLoop/sleep(for:)`` or ``EventLoop/schedule(after:_:)`` instead of `Task.sleep(for:)`. The former routes through libevent's timer wheel (so wake-ups happen as part of the same event-dispatch pass that delivers your read/write callbacks), while the latter is a fire-and-forget callback shape useful for background work that must not block the calling task.

```swift
// Async sleep, driven by the loop:
await loop.sleep(for: .milliseconds(250))

// Fire-and-forget timer:
loop.schedule(after: .seconds(1)) {
    print("one second later")
}
```

### Constructing Socket Addresses

``SocketAddress`` is a value-type wrapper over `sockaddr_storage`. Three factory methods cover the common cases:

- ``SocketAddress/ipv4(_:port:)`` for numeric IPv4 endpoints.
- ``SocketAddress/ipv6(_:port:)`` for IPv6 (including IPv4-mapped IPv6).
- ``SocketAddress/anyIPv4(port:)`` for binding servers to `0.0.0.0` on any local interface.

@Snippet(path: "swift-event/Snippets/SocketAddresses")

Parsing uses `inet_pton(3)` under the hood, so **DNS names are not resolved** — pass a literal IP address. Invalid input surfaces as ``SocketError/invalidAddress(_:)`` with the original host string as the payload.

### When to Reach for Event Instead of SwiftNIO

`Event` is a thin, libevent-direct, async/await wrapper; [SwiftNIO](https://github.com/apple/swift-nio) is a complete event-loop stack with channel pipelines, protocol handlers, and an ecosystem of ready-made modules for HTTP/1, HTTP/2, WebSocket, and TLS. Use this decision table:

| Use case | Framework |
| --- | --- |
| Minimal wrapper over `kqueue`/`epoll` with async/await | `Event` |
| Plain TCP client or server in a small dependency footprint | `Event` |
| Interop with existing libevent-based C or C++ code | `libevent` (this package) |
| HTTP/1, HTTP/2, WebSocket, TLS out of the box | SwiftNIO |
| Back-pressure-aware channel pipelines | SwiftNIO |
| UDP, Unix-domain sockets, raw sockets | SwiftNIO (swift-event TCP-only today) |

### Using swift-event as a Runtime Dependency

Other Swift packages can consume `libevent` from this package directly without going through the `Event` Swift API. The concrete example is [`swift-tor`](https://github.com/21-DOT-DEV/swift-tor), whose `libtor` target links both `libevent` and swift-openssl's `libcrypto` / `libssl`:

```swift
// From swift-tor's Package.swift
dependencies: [
    .package(url: "https://github.com/21-DOT-DEV/swift-openssl.git", branch: "main"),
    .package(url: "https://github.com/21-DOT-DEV/swift-event.git", branch: "main"),
],
targets: [
    .target(
        name: "libtor",
        dependencies: [
            .product(name: "libcrypto", package: "swift-openssl"),
            .product(name: "libssl", package: "swift-openssl"),
            .product(name: "libevent", package: "swift-event"),
        ],
        // ...
    ),
],
```

This pattern is the intended way to bring libevent into a Swift package that has its own C sources without bundling a duplicate libevent build. See <doc:ChoosingLibeventVsEvent> for the full product-selection rationale.

## See Also

- <doc:BackendAndPlatforms>
- <doc:ChoosingLibeventVsEvent>
- <doc:ProductionConsiderations>
- ``SocketError``
