# Async TCP Client for iOS in Swift

@Metadata {
    @TitleHeading("Article")
}

A working TCP client that compiles for iOS (and iPadOS, tvOS, visionOS), with the simulator-localhost gotchas explicit and the `NWConnection` callback dance avoided.

## Overview

Most "Swift TCP client" answers on the public web today push you toward Apple's [`NWConnection`](https://developer.apple.com/documentation/network/nwconnection) — which is the right call when you need TLS, multipath, or platform integration with the system network stack, but is callback-shaped in a world that expects `async`/`await`. The official guidance for bridging it is variations of `withCheckedContinuation` plus `withTaskCancellationHandler` (see [Apple DevForums #719402](https://developer.apple.com/forums/thread/719402) — "How to use network sockets with async/await?" — where Quinn keeps re-explaining the pattern years after the question first surfaced).

``Event`` exposes ``Socket/connect(to:port:loop:timeout:)`` directly as `async throws`. There is no continuation-bridging glue. The code below compiles and runs unchanged on macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, and visionOS 1+.

### A complete TCP client

@Snippet(path: "swift-event/Snippets/TCPClientWithTimeout")

The four operations — ``Socket/connect(to:port:loop:timeout:)``, ``Socket/write(_:timeout:)``, ``Socket/read(maxBytes:timeout:)``, ``Socket/close()`` — are all `async`. Errors propagate through ``SocketError``. Timeouts are first-class; `nil` (the default) waits indefinitely. The `Task { await socket.close() }` deferred close is the idiomatic shape for "best-effort close on scope exit" — ``Socket/close()`` is `async` for API symmetry but the underlying `close(2)` is synchronous, so the spawned task completes immediately.

### iOS-specific gotchas

iOS TCP clients fail in three predictable ways: the simulator-vs-device localhost confusion, the ATS misconception, and silent socket loss when the app backgrounds. None are library-specific — they bite SwiftNIO and Network.framework users equally.

> Important: When testing against a server running on your Mac, **iOS Simulator** sees your Mac's `127.0.0.1`. **A real iOS device** does not — `127.0.0.1` on the device means the device itself. Use your Mac's LAN IP (e.g. `192.168.1.42`) instead.

**1. The simulator's `localhost` is not your Mac's `localhost`.** When your iOS app runs in the simulator, `127.0.0.1` resolves to the simulator's own loopback, which is shared with the host — connecting to a server you launched on your Mac works because the simulator inherits the host's network namespace. On a physical device `127.0.0.1` resolves to the device itself; use your Mac's LAN IP. This trips up enough developers that [swift-nio#1626](https://github.com/apple/swift-nio/issues/1626) accumulated 30 comments on essentially this issue before being closed.

**2. App Transport Security (ATS) does not block plain TCP — but `NSURLSession` does.** ATS is enforced for `URL`-based loaders. Raw socket APIs (``Event``, `NWConnection` in raw mode, BSD sockets) are not subject to ATS. You do not need `NSAppTransportSecurity` plist exceptions to connect plain TCP from an iOS app. If you still see connection failures, check for ad-hoc network sandboxing on managed devices.

**3. Backgrounded apps lose their sockets.** When iOS suspends your app, open sockets are torn down. There is no graceful "background socket" mode for raw TCP — you'd need [`NEAppProxyProvider`](https://developer.apple.com/documentation/networkextension/neappproxyprovider) or one of the other Network Extension entitlements, and those require special Apple approval. For typical foreground app use, structure your code to reconnect on `applicationWillEnterForeground` rather than expecting the socket to persist.

### Cancellation and timeouts

Two mechanisms bound how long an `Event` client waits: per-operation timeouts (built into every I/O method) and Swift Concurrency `Task.cancel()` from a parent scope. Use the first for tight per-call SLAs, the second for "give up the whole sequence."

```swift
// Per-operation timeout (built into the API):
let response = try await socket.read(timeout: .seconds(5))

// Outer task cancellation (Swift structured concurrency):
let task = Task {
    try await sendCommand("PING", to: host, port: port)
}
// elsewhere:
task.cancel()
```

Per-operation timeouts surface as ``SocketError/timeout``. Task cancellation propagates as `CancellationError` from any in-flight ``Socket/read(maxBytes:timeout:)`` / ``Socket/write(_:timeout:)``.

> Note: ``Event``'s cancellation does not currently unregister the outstanding libevent event from the ``EventLoop`` until the next dispatch pass (see <doc:ProductionConsiderations>). For most app-level use cases this is invisible; for tight cancellation guarantees, prefer per-operation `timeout:` parameters over relying on `Task.cancel()`.

### Why not `NWConnection`?

`NWConnection` is the right answer when:

- You need TLS without bringing your own — `NWParameters.tls` is built in.
- You want multipath, low-data mode, or proxy-aware routing.
- You're integrating with Network.framework's path-monitoring APIs to react to interface changes.

``Event`` is the right answer when:

- You want plain TCP without the callback-bridging boilerplate — ``Socket/connect(to:port:loop:timeout:)`` returns a ready-to-use ``Socket``.
- You need cross-platform reach to Linux (Network.framework is Apple-only).
- You want a small dependency footprint and a flat surface — no channel pipelines, no protocol framers, no `NWParameters` knob discovery.
- You're embedding C code that already speaks libevent (the ``Event`` package ships the raw `libevent` C product alongside the Swift API — see <doc:EmbeddingCLibrariesInSwiftPM>).

For a pairwise comparison including SwiftNIO, Hummingbird, and Network.framework, see <doc:SwiftEventVsSwiftNIOVsHummingbirdVsNetworkFramework>.

### A real example: a length-prefixed protocol client

Real-world TCP protocols frame their payloads — usually with a length prefix followed by exactly that many bytes. The `Event` snippet below shows the full pattern (reader, writer, and a sender/receiver demo running on two separate event loops):

@Snippet(path: "swift-event/Snippets/LengthPrefixFraming")

> Important: TCP is a byte stream, not a message channel. **A single ``Socket/read(maxBytes:timeout:)`` call returns whatever the kernel had ready** — it might be a partial message, a coalesced chunk of two messages, or a single byte. If your application protocol expects discrete messages, *you* have to add the framing. This is the most common newcomer-TCP bug across every language; <doc:PartialReadsAndMessageFraming> covers it in depth.

This pattern is generic enough to apply to any length-prefixed protocol (Redis RESP, custom binary formats, many game-server protocols). The deeper discussion of the alternate delimiter-framing pattern for line-oriented protocols (HTTP/1, SMTP, IRC) also lives in <doc:PartialReadsAndMessageFraming>.

## See Also

- <doc:GettingStarted>
- <doc:AsyncTCPServerInSwift>
- <doc:PartialReadsAndMessageFraming>
- <doc:SwiftEventVsSwiftNIOVsHummingbirdVsNetworkFramework>
- <doc:ProductionConsiderations>
- ``Socket``
- ``Socket/connect(to:port:loop:timeout:)``
- ``Socket/read(maxBytes:timeout:)``
- ``Socket/write(_:timeout:)``
- ``SocketError``
- ``SocketError/timeout``
- ``SocketError/connectionClosed``
