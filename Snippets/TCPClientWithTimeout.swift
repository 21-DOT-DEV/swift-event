// snippet.hide
import Foundation
import Event

@main
struct TCPClientWithTimeout {
    static func main() async throws {
        try await sendCommand("PING\r\n", to: "127.0.0.1", port: 8080)
    }

    @discardableResult
    static func sendCommand(_ command: String, to host: String, port: UInt16) async throws -> String {
// snippet.end

// Connects with a 5-second handshake budget, writes the command, reads one
// reply, and closes — all four operations bounded by the same timeout.
let socket = try await Socket.connect(
    to: host,
    port: port,
    timeout: .seconds(5)
)
defer { Task { await socket.close() } }

try await socket.write(Data(command.utf8), timeout: .seconds(5))
let response = try await socket.read(timeout: .seconds(5))
return String(decoding: response, as: UTF8.self)

// snippet.hide
    }
}
// snippet.end
