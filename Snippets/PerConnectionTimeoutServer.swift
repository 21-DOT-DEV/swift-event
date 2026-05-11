// snippet.hide
import Foundation
import Event

@main
struct PerConnectionTimeoutServer {
    static func main() async throws {
        try await run()
    }

    static func run() async throws {
// snippet.end

// Bound each request/response cycle to 30 seconds so a slow client cannot
// pin a server task indefinitely. SocketError.timeout leaves the socket
// usable for retry; on this code path we just drop the connection.
let server = try await Socket.listen(port: 8080)

for try await client in server.connections {
    Task {
        do {
            let request = try await client.read(timeout: .seconds(30))
            // ... handle the request, build a response ...
            try await client.write(request, timeout: .seconds(30))
        } catch SocketError.timeout {
            // Slow client — drop the connection.
        } catch SocketError.connectionClosed {
            // Peer disconnected before we could reply.
        } catch {
            // Other transport error — log and drop.
        }
        await client.close()
    }
}

// snippet.hide
    }
}
// snippet.end
