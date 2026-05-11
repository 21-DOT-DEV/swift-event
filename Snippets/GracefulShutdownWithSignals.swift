// snippet.hide
import Foundation
import Event

@main
struct GracefulShutdownWithSignals {
    static func main() async throws {
// snippet.end

// Wire SIGTERM and SIGINT into a graceful shutdown path. The signalStream
// yields the signal number on every fire; on the first one we close the
// listener, cancel the accept-loop task, and break out — that triggers
// AsyncStream.onTermination, which calls event_del() to unregister
// libevent's signal handlers cleanly.
let loop = EventLoop.shared
let server = try await Socket.listen(port: 8080, loop: loop)

let serverTask = Task {
    for try await client in server.connections {
        Task { try await handle(client) }
    }
}

for await sig in loop.signalStream(SIGTERM, SIGINT) {
    print("received signal \(sig); shutting down gracefully")
    server.close()
    serverTask.cancel()
    break
}

// snippet.hide
    }

    static func handle(_ client: Socket) async throws {
        let payload = try await client.read()
        try await client.write(payload)
        await client.close()
    }
}
// snippet.end
