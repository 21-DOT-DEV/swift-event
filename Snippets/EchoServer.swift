// snippet.hide
import Foundation
import Event

@main
struct EchoServer {
    static func main() async throws {
        try await run()
    }

    static func run() async throws {
// snippet.end

// Listen on port 8080 and echo every incoming payload back to its sender.
// Each accepted connection is handled on its own child task so clients
// don't block each other.
let server = try await Socket.listen(port: 8080)

for try await client in server.connections {
    Task {
        let payload = try await client.read()
        try await client.write(payload)
        await client.close()
    }
}

// snippet.hide
    }
}
// snippet.end
