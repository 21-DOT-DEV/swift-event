// snippet.hide
import Foundation
import Event

@main
struct DelimiterFraming {
    static func main() async throws {
        let serverLoop = EventLoop()
        let clientLoop = EventLoop()
        let server = try await Socket.listen(port: 0, loop: serverLoop)
        let port = server.localPort   // kernel-assigned ephemeral port

        async let acceptedFuture = server.accept()
        let sender = try await Socket.connect(to: "127.0.0.1", port: port, loop: clientLoop)
        let receiver = try await acceptedFuture

        try await sender.write(Data("HELLO\r\nWORLD\r\n".utf8))
        let buffer = LineBuffer()
        let line1 = try await receiver.readLine(into: buffer)
        let line2 = try await receiver.readLine(into: buffer)
        print(String(decoding: line1, as: UTF8.self))
        print(String(decoding: line2, as: UTF8.self))

        await sender.close()
        await receiver.close()
        server.close()
    }
}

// snippet.end

// Delimiter framing for line-oriented protocols (HTTP/1, SMTP, IRC, REPL
// shells). Bytes that arrive past a delimiter on a single read(2) are held
// in `LineBuffer` so they can be returned on the next readLine call.

extension Socket {
    /// Reads bytes until `\r\n` is encountered. Returns the data preceding
    /// the delimiter; the delimiter itself is consumed but not returned.
    /// Throws `SocketError.connectionClosed` if the peer disconnects before
    /// sending one.
    func readLine(timeout: Duration? = nil, into buffer: LineBuffer) async throws -> Data {
        let crlf = Data("\r\n".utf8)
        while true {
            if let lineEnd = buffer.data.range(of: crlf) {
                let line = buffer.data.subdata(in: 0..<lineEnd.lowerBound)
                buffer.data.removeSubrange(0..<lineEnd.upperBound)
                return line
            }
            let chunk = try await read(timeout: timeout)
            if chunk.isEmpty { throw SocketError.connectionClosed }
            buffer.data.append(chunk)
        }
    }
}

/// Holds bytes read past a delimiter so they can be returned on the next
/// `readLine` call. Single-owner-per-scope as elsewhere in `Event`.
final class LineBuffer: @unchecked Sendable {
    var data = Data()
}
