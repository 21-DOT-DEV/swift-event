[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

# 🌐 swift-event

Swift event loop and async TCP socket library. Cross-platform I/O multiplexing with kqueue and epoll. Uses Swift's C interoperability with [libevent](https://github.com/libevent/libevent).

## Contents

- [Features](#features)
- [Installation](#installation)
- [Usage Examples](#usage-examples)
- [License](#license)

## Features

- Provide event-driven async I/O with Swift concurrency (async/await)
- Support cross-platform I/O backends: kqueue on Apple platforms, epoll on Linux
- Expose TCP client and server with non-blocking sockets
- Offer lightweight C interop with direct libevent bindings via Swift's C module system
- Include a two-layer design: raw `libevent` C module and idiomatic `Event` Swift API
- Maintain Swift 6 strict concurrency compliance
- Ensure availability for Linux and Apple platform ecosystems

## Installation

Add the following to your `Package.swift` file:

```swift
.package(url: "https://github.com/21-DOT-DEV/swift-event", branch: "main"),
```

> [!NOTE]
> Version-based dependencies will be available after the first release. Until then, use `branch: "main"`.

Then, include `Event` as a dependency in your target:

```swift
.target(name: "<target>", dependencies: [
    .product(name: "Event", package: "swift-event")
]),
```

## Usage Examples

### Event Loop
```swift
import Event

let loop = EventLoop()

// The I/O backend in use (e.g., "kqueue" on macOS, "epoll" on Linux)
print(loop.backendMethod)
```

### TCP Client
```swift
import Event

let socket = try await Socket.connect(to: "127.0.0.1", port: 8080)
try await socket.write("Hello, server!".data(using: .utf8)!)
let response = try await socket.read()
print(String(data: response, encoding: .utf8)!)
await socket.close()
```

### TCP Server
```swift
import Event

let server = try await Socket.listen(port: 8080)

for try await client in server.connections {
    let data = try await client.read()
    try await client.write(data) // Echo back
}
```

## License

`swift-event` is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
