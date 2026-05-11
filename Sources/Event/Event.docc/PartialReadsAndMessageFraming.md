# Handling Partial Reads in Swift TCP Sockets: Length-Prefix and Delimiter Framing

@Metadata {
    @TitleHeading("Article")
}

Why a single `read()` call rarely returns a full message, and the two framing patterns (length-prefix and delimiter) every TCP application ends up writing.

## Overview

**One `send()` does not produce one `recv()` in TCP.** This is the single most common newcomer mistake across every language and every library, going back to the 1980s. TCP is a byte stream, not a message channel — the kernel is free to coalesce, split, or reorder the bytes you write into whatever number of `read()`-side return values the receiver's kernel sees fit.

The classic write-up of this is [Stephen Cleary's 2009 "Message Framing"](https://blog.stephencleary.com/2009/04/message-framing.html), still the top Google result for "tcp message framing" because nothing about the underlying protocol has changed in seventeen years.

``Event``'s ``Socket/read(maxBytes:timeout:)`` returns a `Data` containing whatever the *next* `read(2)` syscall returned. That might be 12 bytes, 4096 bytes, or 1 byte. If your application protocol expects discrete messages, **you** have to add the framing — built on top of ``Socket`` and ``Socket/write(_:timeout:)``.

This article shows the two patterns that cover ~95% of real-world TCP protocols: length-prefix framing (used by Redis RESP, gRPC, many binary protocols) and delimiter framing (used by SMTP, HTTP/1, IRC, line-oriented protocols).

### Why a single `read()` is not a message

```swift
// Sender side:
try await socket.write(Data("Hello, world!".utf8))     // 13 bytes
try await socket.write(Data("Goodbye!".utf8))           // 8 bytes

// Receiver side:
let chunk1 = try await socket.read()
let chunk2 = try await socket.read()
```

You might expect `chunk1` to be `"Hello, world!"` and `chunk2` to be `"Goodbye!"`. In practice you might get any of:

- `chunk1` = `"Hello, world!Goodbye!"`, `chunk2` = blocks forever (TCP coalesced both writes into one segment)
- `chunk1` = `"Hello, world!"`, `chunk2` = `"Goodbye!"` (what you expected — likely on localhost, less likely on a real network)
- `chunk1` = `"Hello, "`, `chunk2` = `"world!Goodbye!"` (split mid-message)
- `chunk1` = `"H"`, `chunk2` = `"ello, world!Goodbye!"` (extreme but legal)

All four behaviors are valid TCP. The kernel guarantees order and reliability of bytes; it makes no promise about which bytes arrive together.

### Pattern 1 — Length-prefix framing

**Length-prefix framing is the default choice for new TCP protocols.** Every message starts with a fixed-size length field, followed by exactly that many payload bytes. The receiver knows up front how many bytes to expect and loops on `read()` until it has them all. The full helper extension lives in this snippet:

@Snippet(path: "swift-event/Snippets/LengthPrefixFraming")

**Why concatenate before `write`** — ``Socket/write(_:timeout:)`` issues a single `write(2)` syscall covering the supplied buffer. Sending the length and payload as one buffer avoids any chance of the kernel sending the length without the payload (which would force the receiver to do two reads and complicates timing). If you write them separately, the receiver still works (`readLengthPrefixedFrame` handles arbitrary partial reads), but the wire is slightly less efficient.

**Why a 4-byte length** — gives you a 4 GiB max message size, which is more than enough for almost everything except video streaming. For protocols that need larger messages, use a 64-bit length. For protocols where messages are guaranteed small (< 64 KiB), a 2-byte length saves bandwidth.

**Endianness** — network byte order is big-endian. Swift's `bigEndian` accessor on integer types handles the host-to-network conversion regardless of the platform's native endianness.

### Pattern 2 — Delimiter framing

**Delimiter framing fits text protocols where messages can't legally contain the delimiter byte sequence.** Used by HTTP/1 headers, SMTP, IRC, and REPL-style protocols — messages are separated by a known sequence (typically `\r\n` or `\n`). The bytes read past a delimiter on a single underlying `read()` are held in a `LineBuffer` until the next `readLine` call:

@Snippet(path: "swift-event/Snippets/DelimiterFraming")

**Why a buffer is required** — when `read()` returns 200 bytes and there are 3 newlines in those bytes, you need to return one line and hold the other two for the next `readLine` call. There is no way around this: you cannot un-read bytes back to the kernel.

> Warning: Delimiter framing breaks the moment a payload legally contains the delimiter byte sequence (e.g., binary data with a `\r\n` in it). Length-prefix framing is immune to this. If your protocol payload could contain anything, **prefer length-prefix framing.**

### Choosing between length-prefix and delimiter

| | Length-prefix | Delimiter |
|---|---|---|
| Payload can contain any bytes | ✅ | ❌ (delimiter must be escaped) |
| Receiver knows total size up front | ✅ | ❌ |
| Easy to debug from `tcpdump` output | ⚠️ (need to parse the length) | ✅ (text-readable) |
| Handles streaming / unknown-size payloads | ❌ (need a length first) | ✅ (read until delimiter) |
| Common in binary protocols | ✅ (Redis, gRPC, MQTT) | ❌ |
| Common in text protocols | ❌ | ✅ (HTTP, SMTP, IRC) |

For new protocols: **length-prefix unless you have a reason not to**. Debugging convenience is rarely worth the escape-handling complexity that delimiter framing forces on you the first time a payload contains the delimiter.

### Combining with timeouts

**The `timeout:` parameter applies per `read(2)` call, not to the entire framing helper.** Both helpers above accept the same `timeout: Duration?` shape as the underlying ``Socket/read(maxBytes:timeout:)``.

If you read a 10 MiB length-prefixed frame in 4 KiB chunks with `timeout: .seconds(5)`, the helper can spend up to `5s × ⌈10_485_760 / 4096⌉ = ~12_800s` total in the worst case (no chunk arrives within 5s of the previous chunk). To bound total framing time, wrap the call in a `Task` with `Task.cancel()` from a parent timeout — Swift Concurrency's structured-cancellation will propagate into the in-flight ``Socket/read(maxBytes:timeout:)`` (subject to the cancellation caveats in <doc:ProductionConsiderations>). On timeout the helper throws ``SocketError/timeout``.

### Testing your framing code

**Test for "kernel splits a message across two reads" — that's the failure mode framing code exists to handle.** Simulate it explicitly by writing the message in two halves from the producer side, with a small `Task.sleep` between writes to force the receiver to read each half separately:

```swift
@Test("readLengthPrefixedFrame reassembles a split message")
func splitMessage() async throws {
    let serverLoop = EventLoop()
    let clientLoop = EventLoop()
    let server = try await Socket.listen(port: 0, loop: serverLoop)
    let port = server.localPort
    async let acceptedFuture = server.accept()
    let sender = try await Socket.connect(to: "127.0.0.1", port: port, loop: clientLoop)
    let receiver = try await acceptedFuture

    // Construct a 13-byte payload with a 4-byte big-endian length prefix.
    let payload = Data("Hello, world!".utf8)
    var header = UInt32(payload.count).bigEndian
    var frame = Data()
    withUnsafeBytes(of: &header) { frame.append(contentsOf: $0) }
    frame.append(payload)

    // Write it in two halves to force a split read on the receiver side.
    try await sender.write(frame.prefix(8))
    try await Task.sleep(for: .milliseconds(20))
    try await sender.write(frame.suffix(from: 8))

    let received = try await receiver.readLengthPrefixedFrame()
    #expect(received == payload)

    await sender.close()
    await receiver.close()
    server.close()
}
```

The test uses two ``EventLoop`` instances (one per side), ``Socket/listen(port:backlog:loop:)`` with `port: 0` to grab an ephemeral port, ``ServerSocket/localPort`` to read it back, and ``Socket/connect(to:port:loop:timeout:)`` on the client side.

> Note: Two separate ``EventLoop`` instances (one for the server side, one for the client side) avoid libevent's `event_base_loop: reentrant invocation` warning. Concurrent ``EventLoop/runOnce()`` on a single loop violates libevent's single-owner invariant — see <doc:ProductionConsiderations>.

## See Also

- <doc:GettingStarted>
- <doc:AsyncTCPServerInSwift>
- <doc:TCPClientForIOSWithSwift>
- <doc:ProductionConsiderations>
- ``Socket``
- ``Socket/read(maxBytes:timeout:)``
- ``Socket/write(_:timeout:)``
- ``SocketError/timeout``
- ``SocketError/connectionClosed``
- [Stephen Cleary — Message Framing (2009)](https://blog.stephencleary.com/2009/04/message-framing.html)
