// snippet.hide
import Foundation
import Event

@main
struct EchoClient {
    static func main() async throws {
        try await run()
    }

    static func run() async throws {
// snippet.end

// Connect to a plain-TCP echo server listening on 127.0.0.1:8080,
// send a greeting, read the echoed bytes, and close.
let client = try await Socket.connect(to: "127.0.0.1", port: 8080)

try await client.write(Data("Hello, server!".utf8))
let response = try await client.read()
print(String(decoding: response, as: UTF8.self))

await client.close()

// snippet.hide
    }
}
// snippet.end
