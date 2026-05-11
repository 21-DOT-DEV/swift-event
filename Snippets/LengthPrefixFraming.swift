// snippet.hide
import Foundation
import Event

@main
struct LengthPrefixFraming {
    static func main() async throws {
        // Server and client use SEPARATE EventLoops to honor swift-event's
        // single-owner-per-scope invariant — concurrent runOnce() on a
        // shared loop triggers libevent's "reentrant invocation" warning.
        let serverLoop = EventLoop()
        let clientLoop = EventLoop()
        let server = try await Socket.listen(port: 0, loop: serverLoop)
        let port = server.localPort   // kernel-assigned ephemeral port

        async let acceptedFuture = server.accept()
        let sender = try await Socket.connect(to: "127.0.0.1", port: port, loop: clientLoop)
        let receiver = try await acceptedFuture

        try await sender.writeLengthPrefixedFrame(Data("Hello, framing!".utf8))
        let payload = try await receiver.readLengthPrefixedFrame()
        print(String(decoding: payload, as: UTF8.self))

        await sender.close()
        await receiver.close()
        server.close()
    }
}

// snippet.end

// A 4-byte big-endian length prefix followed by exactly that many payload
// bytes. The receiver loops on read() until it has the full message — a
// single read(2) syscall might return only part of any prefix or payload.

extension Socket {
    /// Reads exactly `count` bytes, looping until the kernel has delivered
    /// them all. Throws `SocketError.connectionClosed` if the peer
    /// disconnects mid-message.
    func readExactly(_ count: Int, timeout: Duration? = nil) async throws -> Data {
        var buffer = Data()
        buffer.reserveCapacity(count)
        while buffer.count < count {
            let chunk = try await read(maxBytes: count - buffer.count, timeout: timeout)
            if chunk.isEmpty { throw SocketError.connectionClosed }
            buffer.append(chunk)
        }
        return buffer
    }

    /// Reads a 4-byte big-endian length prefix followed by that many
    /// payload bytes.
    func readLengthPrefixedFrame(timeout: Duration? = nil) async throws -> Data {
        let header = try await readExactly(4, timeout: timeout)
        let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        return try await readExactly(Int(length), timeout: timeout)
    }

    /// Writes a 4-byte big-endian length prefix followed by `payload`,
    /// concatenated into a single buffer so the kernel sees one write(2).
    func writeLengthPrefixedFrame(_ payload: Data, timeout: Duration? = nil) async throws {
        var header = UInt32(payload.count).bigEndian
        var frame = Data()
        frame.reserveCapacity(4 + payload.count)
        withUnsafeBytes(of: &header) { frame.append(contentsOf: $0) }
        frame.append(payload)
        try await write(frame, timeout: timeout)
    }
}
