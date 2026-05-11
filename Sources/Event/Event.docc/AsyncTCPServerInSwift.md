# How to Write an Async TCP Server in Swift

@Metadata {
    @TitleHeading("Article")
}

A complete async TCP server in Swift 6, end-to-end — bind, listen, accept, per-connection handler tasks, graceful close — without channel pipelines or `EventLoopFuture` plumbing.

## Overview

If you came here from a search for "swift tcp server," the worked example below is the entire program. It compiles on macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, visionOS 1+, and Linux (Ubuntu 22.04+) using Swift 6.1's strict concurrency. There is no `ChannelHandler`, no `executeThenClose`, no `ByteBuffer`, no `EventLoopGroup` to size, and no Future-to-async bridging.

@Snippet(path: "swift-event/Snippets/EchoServer")

This is a complete echo server. Drop it into a `swift-tools-version:6.1` package with `Event` as a dependency, run `swift run`, and connect with `nc 127.0.0.1 8080`.

### What each piece is doing

The server is four primitives: `listen`, `connections`, `Task`, and the read/write loop. Each one maps to a single libevent or POSIX concept.

**``Socket/listen(port:backlog:loop:)``** allocates a non-blocking IPv4 socket, applies `SO_REUSEADDR`, calls `bind(2)` with `INADDR_ANY` and `listen(2)` with the supplied backlog (default `128`), and returns a ``ServerSocket``. Errors surface as ``SocketError/socketCreationFailed(_:)``, ``SocketError/bindFailed(_:)``, or ``SocketError/listenFailed(_:)`` — each carrying the raw `errno` from the failing syscall.

**``ServerSocket/connections``** is an `AsyncThrowingStream<Socket, Error>`. Each iteration awaits a single libevent `EV_READ`-ready callback on the listening descriptor, calls `accept(2)`, and yields the resulting ``Socket``. The `for try await` loop terminates when the stream throws — typically via ``ServerSocket/close()`` or `deinit`.

**`Task { … }`** dispatches each accepted client onto its own child task — the structured-concurrency replacement for NIO's `EventLoopGroup` thread fanout. The example above takes the happy-path shortcut of letting any thrown error terminate the connection silently. Production code should wrap the inner read/write loop in `do { while true { … } } catch SocketError.connectionClosed { … } catch { … }` to distinguish orderly peer EOF from transport failures — see <doc:GettingStarted> ("Detecting Socket Close and Errors") for the full pattern. For threading-model implications, see <doc:SwiftEventVsSwiftNIOVsHummingbirdVsNetworkFramework>.

> Important: There is no separate close-callback to register on a ``Socket``. The close event arrives through the normal error-throwing path as ``SocketError/connectionClosed`` from the next ``Socket/read(maxBytes:timeout:)``. Forum questions asking "where do I register `socket.onClose`?" reflect a callback-era mental model that doesn't apply in `async`/`await` Swift.

### Binding to a specific interface

The `port:` overload binds to all interfaces. To bind only to localhost (or a specific LAN address), use ``Socket/listen(on:backlog:loop:)``:

```swift
let address = try SocketAddress.ipv4("127.0.0.1", port: 8080)
let server = try await Socket.listen(on: address)
```

Pass `port: 0` to either overload to ask the kernel for an ephemeral port — useful in tests where you don't want hard-coded port collisions. Read the assigned port back via ``ServerSocket/localPort``:

```swift
let server = try await Socket.listen(port: 0)
print("listening on \(server.localPort)")  // e.g. 53941
// ``ServerSocket/localAddress`` returns the full SocketAddress if you need
// the bound interface too.
```

### Per-connection timeouts

Bound each client's request/response cycle by passing a `timeout:` to every ``Socket/read(maxBytes:timeout:)`` and ``Socket/write(_:timeout:)`` call. The default is `nil` (wait indefinitely); typical server-side values are seconds-to-minutes.

@Snippet(path: "swift-event/Snippets/PerConnectionTimeoutServer")

Per-operation timeouts surface as ``SocketError/timeout`` and leave the socket usable for retry. No partial writes are consumed when a write times out — the `write(2)` syscall is never issued until the kernel reports write-readiness, so a timeout simply means "the kernel didn't make us writable in time."

> Note: The timeout applies to *each* I/O call, not to the connection as a whole. A 30-second `read` timeout followed by a 30-second `write` timeout gives the client up to 60 seconds. To bound the total per-connection time, wrap the whole handler in a `Task` and cancel it from a parent timeout.

### Graceful shutdown

Cancelling the outer task that iterates ``ServerSocket/connections`` terminates the `for try await` loop in your code, but does **not** currently propagate `Task` cancellation down into the outstanding libevent accept callback (a known limitation — see <doc:ProductionConsiderations>). The reliable shutdown shape uses ``EventLoop/signalStream(_:)`` to react to `SIGTERM` / `SIGINT` and explicitly tear down the listener:

@Snippet(path: "swift-event/Snippets/GracefulShutdownWithSignals")

The first signal causes the `for await` to yield, we close the listener and cancel the accept-loop task, then `break` out of the loop — which triggers `AsyncStream`'s `onTermination`, which unregisters libevent's signal handlers via `event_del(3)`. Calling ``ServerSocket/close()`` is safe to invoke from any task and is idempotent.

This pattern composes directly with [`swift-service-lifecycle`](https://github.com/swift-server/swift-service-lifecycle) — a service's `run()` body can iterate ``EventLoop/signalStream(_:)`` and call its `gracefulShutdown()` instead of the manual close + cancel above.

### Threading model — what you don't have to think about

`Event` runs on **one thread** by default: a single ``EventLoop`` (default ``EventLoop/shared``) drives the listening socket and all per-connection I/O. There is no `EventLoopGroup` to size, no `MultiThreadedEventLoopGroup` warning from Xcode's Thread Performance Checker (a recurring complaint against `swift-nio` — see [swift-nio#2223](https://github.com/apple/swift-nio/issues/2223), 29 comments), and no thread-affinity bookkeeping in your application code.

The underlying multiplexer is platform-optimal: kqueue on Apple platforms, epoll on Linux. See <doc:BackendAndPlatforms> for the per-platform story.

> Important: A single loop scales to the order of thousands of concurrent connections, not hundreds of thousands. If you need to saturate a many-core machine with raw connection throughput, SwiftNIO's `MultiThreadedEventLoopGroup` is the right answer. For internal services, app backends, daemons, and embedded brokers, a single loop is enough.

### Common server-side patterns

Four patterns server authors hit immediately, ordered by how often they come up:

**Connection limits.** There is no built-in concurrent-client cap. Throttle by counting active tasks yourself with a custom actor (the example below uses an illustrative `ConnectionLimiter` — not a type the package ships):

```swift
let limiter = ConnectionLimiter(max: 1000)   // your own actor
for try await client in server.connections {
    if await limiter.tryEnter() {
        Task {
            defer { Task { await limiter.leave() } }
            try await handle(client)
        }
    } else {
        await client.close()
    }
}
```

**Per-client timeouts** (already shown above). Apply via `timeout:` on every `read`/`write`.

**Backpressure.** Not built in — see the <doc:ProductionConsiderations> "Backpressure and Partial Writes" section. For protocols where this matters (large file transfers, streaming), chunk explicitly and respect `EAGAIN`-style re-registration manually until the planned helper lands.

**Logging.** No logger ships with the package. Use whatever you already have (`os.log`, `swift-log`, custom). The library never logs internally.

## See Also

- <doc:GettingStarted>
- <doc:TCPClientForIOSWithSwift>
- <doc:SwiftEventVsSwiftNIOVsHummingbirdVsNetworkFramework>
- <doc:ProductionConsiderations>
- ``ServerSocket``
- ``Socket``
- ``EventLoop``
