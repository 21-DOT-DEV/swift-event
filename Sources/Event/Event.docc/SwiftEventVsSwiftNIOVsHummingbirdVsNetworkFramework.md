# swift-event vs SwiftNIO vs Hummingbird vs Network.framework

@Metadata {
    @TitleHeading("Article")
}

A decision-tree comparison of the four common Swift networking choices, written from inside swift-event but trying not to mark its own homework.

## Overview

Four options keep coming up in "what should I use for networking in Swift?" forum threads:

- **``Event``** — this package. Thin async/await wrapper (``Socket``, ``ServerSocket``, ``EventLoop``) over libevent's kqueue/epoll multiplexer. Plain TCP, no built-in TLS/HTTP/WebSocket.
- **[SwiftNIO](https://github.com/apple/swift-nio)** — Apple's full event-loop networking stack. Channel pipelines, protocol handlers, an ecosystem of modules (HTTP/1, HTTP/2, WebSocket, TLS).
- **[Hummingbird](https://github.com/hummingbird-project/hummingbird)** — server-side Swift HTTP framework built on SwiftNIO. Routing, middleware, async/await-native APIs above NIO's channel layer.
- **[Network.framework](https://developer.apple.com/documentation/network)** — Apple's modern (2018) networking framework, callback-shaped, deeply integrated with the system network stack on Apple platforms only.

This article is a decision tree, not a tier list. Each is the right answer for a specific shape of problem.

### Decision tree

**Pick the framework by question shape, not feature checklist:** HTTP server → Hummingbird; Apple-only with TLS → Network.framework; plain TCP with async/await → ``Event``; 10k+ concurrent connections → SwiftNIO; embedding a libevent-based C library → ``Event``'s `libevent` product. The five-question tree below disambiguates the edges.

1. **Are you building an HTTP server (REST, GraphQL, WebSocket)?**
   - Yes → **Hummingbird** if you want async/await-first ergonomics. **SwiftNIO** + `swift-nio-http` if you want the lowest-level protocol control or you're integrating with existing NIO-based code.
   - No → continue.

2. **Are you Apple-platform-only and need TLS, multipath, or system-managed routing?**
   - Yes → **Network.framework**. The `NWConnection` callback shape is the price you pay for the platform integration.
   - No → continue.

3. **Are you doing plain TCP and you want async/await with a small dependency footprint?**
   - Yes → **``Event``** — see ``Socket/connect(to:port:loop:timeout:)`` and ``Socket/listen(port:backlog:loop:)``. If you also need cross-platform reach to Linux, this is the lane.
   - No → continue.

4. **Do you need extreme connection scale (10k+ concurrent connections, multi-core saturation)?**
   - Yes → **SwiftNIO** with `MultiThreadedEventLoopGroup`. The thread-fanout model is what NIO is built for.
   - No → **``Event``** is likely fine — it runs a single ``EventLoop`` per scope.

5. **Are you embedding a C library that already speaks libevent (Tor, libssh, custom C code)?**
   - Yes → **``Event``** ships the raw `libevent` C product as a re-exportable SwiftPM target. See <doc:ChoosingLibeventVsEvent> for the product-selection rationale and <doc:EmbeddingCLibrariesInSwiftPM> for the module-map pattern.

> Note: This decision tree shortcuts when the answer to question 1 is "yes" (HTTP server). Hummingbird and SwiftNIO + `swift-nio-http` are the only practical Swift choices for production HTTP servers — ``Event`` does not wrap HTTP and we have no plan to. Question 3 onward is for non-HTTP cases.

### Side-by-side comparison table

| Capability | ``Event`` | SwiftNIO | Hummingbird | Network.framework |
|---|---|---|---|---|
| Async/await native | ✅ | Partial (NIOAsyncChannel bridges) | ✅ | ❌ (callback-only) |
| Plain TCP client/server | ✅ | ✅ | (via NIO) | ✅ |
| HTTP/1 server | ❌ | ✅ (`swift-nio-http1`) | ✅ | ❌ |
| HTTP/2 server | ❌ | ✅ (`swift-nio-http2`) | ✅ | ❌ |
| WebSocket | ❌ | ✅ (`swift-nio-websocket`) | ✅ | Partial (`NWWebSocket`) |
| TLS | ❌ | ✅ (`swift-nio-ssl`) | ✅ | ✅ (built-in) |
| UDP | ❌ | ✅ | (server-focused) | ✅ |
| Unix-domain sockets | ❌ | ✅ | (via NIO) | ❌ |
| Linux support | ✅ | ✅ | ✅ | ❌ (Apple-only) |
| iOS support | ✅ | ✅ | ✅ (NIOTransportServices) | ✅ |
| Threading model | Single loop, single owner per scope | `MultiThreadedEventLoopGroup` (configurable) | NIO's ELG | System-managed |
| Backpressure | Manual (planned) | Built-in via channel pipeline | Built-in via NIO | Built-in via NWConnection state |
| Direct C-library embedding | ✅ (libevent product) | ❌ | ❌ | ❌ |
| Cancellation propagation | Partial (see <doc:ProductionConsiderations>) | Partial (NIOAsyncChannel known issues) | ✅ via async/await | N/A (callback model) |
| Pre-1.0 status | ✅ (0.x today) | ❌ (stable, 2.x) | ❌ (stable, 2.x) | ❌ (stable since iOS 12) |
| Approximate code size to "echo server" | ~10 lines | ~50 lines (channel pipeline) | ~10 lines | ~30 lines (callback bridging) |

### Code shape comparison: an echo server in each

The same problem — accept TCP connections and echo back received bytes — takes ~10 lines in ``Event``, ~50 lines in SwiftNIO, ~10 lines in Hummingbird (HTTP, not raw TCP), and ~30 lines in Network.framework. The line counts reflect the abstraction depth each library imposes, not the underlying capability.

**``Event``** — full compiled snippet using ``Socket/listen(port:backlog:loop:)``, ``ServerSocket/connections``, ``Socket/read(maxBytes:timeout:)``, and ``Socket/write(_:timeout:)``:

@Snippet(path: "swift-event/Snippets/EchoServer")

**SwiftNIO** (using NIOAsyncChannel, the post-2024 ergonomic shape):

```swift
let server = try await ServerBootstrap(group: NIOSingletons.posixEventLoopGroup)
    .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
    .bind(host: "0.0.0.0", port: 8080) { channel in
        channel.eventLoop.makeCompletedFuture {
            try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
        }
    }

try await withThrowingDiscardingTaskGroup { group in
    try await server.executeThenClose { connections in
        for try await connection in connections {
            group.addTask {
                try await connection.executeThenClose { inbound, outbound in
                    for try await chunk in inbound {
                        try await outbound.write(chunk)
                    }
                }
            }
        }
    }
}
```

**Hummingbird** (HTTP, not raw TCP — Hummingbird's domain is HTTP so the equivalent is "echo POST body"):

```swift
let router = Router()
router.post("/") { request, _ in
    let body = try await request.body.collect(upTo: .max)
    return Response(status: .ok, body: ResponseBody(byteBuffer: body))
}
let app = Application(router: router, configuration: .init(address: .hostname("0.0.0.0", port: 8080)))
try await app.runService()
```

**Network.framework:**

```swift
let listener = try NWListener(using: .tcp, on: 8080)
listener.newConnectionHandler = { connection in
    connection.start(queue: .global())
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
        guard let data = data else { return }
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
listener.start(queue: .global())
RunLoop.main.run()
```

### Choosing for specific scenarios

**"I'm writing an iOS app that needs to talk plain TCP to my server."** → ``Event`` via ``Socket/connect(to:port:loop:timeout:)``. See <doc:TCPClientForIOSWithSwift>. `Network.framework` works too but the callback shape is awkward in modern Swift.

**"I'm writing a Vapor-style web service."** → Hummingbird (or Vapor itself if you want the full ORM/template ecosystem). Both build on NIO under the hood.

**"I need to handle 50k concurrent WebSocket clients."** → SwiftNIO directly, with `MultiThreadedEventLoopGroup` sized to your core count, plus `swift-nio-websocket`.

**"I'm porting a C codebase that uses libevent (Tor, libssh, custom binary protocol library) to a Swift package."** → ``Event``. The package's `libevent` C product is consumable by other Swift packages exactly for this case. See <doc:ChoosingLibeventVsEvent> and <doc:EmbeddingCLibrariesInSwiftPM>.

**"I need TLS but don't want to depend on swift-nio-ssl."** → `Network.framework` on Apple platforms (TLS is built in). On Linux, you currently have to bring TLS yourself; ``Event`` does not wrap TLS today.

**"I want to write an MQTT broker / Redis-compatible server / custom binary-protocol daemon."** → Almost certainly ``Event`` is enough, especially if the protocol is length-prefixed binary (see <doc:PartialReadsAndMessageFraming>). Reach for SwiftNIO if the protocol is async-message-multiplexed in ways that benefit from a channel-pipeline architecture.

### Honest disclosures

> Important: This article is published in ``Event``'s own documentation. SwiftNIO and Hummingbird are mature, production-grade libraries with years of real deployment behind them; ``Event`` is pre-1.0 and ships a deliberately narrow surface. The decision tree above tries to recommend the right tool for the job rather than the home team — but you should weigh the source.

Two biases worth naming explicitly:

1. **Recency bias.** ``Event`` is pre-1.0; SwiftNIO and Hummingbird are mature stable libraries with years of production use. The capability gaps in the comparison table are not abstract — they reflect features ``Event`` has deliberately not yet shipped, and "we don't have your bug" can become "we don't have your feature" quickly. See <doc:ProductionConsiderations> for the full caveats list (and ``SocketError`` for the error surface).

2. **Scope bias.** Comparing a thin libevent wrapper (``Socket`` / ``ServerSocket`` / ``EventLoop``) to a full HTTP framework (Hummingbird) is comparing different layers. The decision tree above tries to surface this — the right comparison for "what HTTP server should I use" is Hummingbird vs Vapor, not Hummingbird vs ``Event``.

For the libevent vs ``Event`` choice specifically (when to drop down from the Swift API to the raw C product), see <doc:ChoosingLibeventVsEvent>.

## See Also

- <doc:ChoosingLibeventVsEvent>
- <doc:TCPClientForIOSWithSwift>
- <doc:AsyncTCPServerInSwift>
- <doc:EmbeddingCLibrariesInSwiftPM>
- <doc:ProductionConsiderations>
- ``Event``
- ``EventLoop``
- ``Socket``
- ``ServerSocket``
- ``SocketError``
- [SwiftNIO](https://github.com/apple/swift-nio)
- [Hummingbird](https://github.com/hummingbird-project/hummingbird)
- [Network.framework](https://developer.apple.com/documentation/network)
