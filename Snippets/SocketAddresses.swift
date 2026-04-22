// snippet.hide
import Event
// snippet.end

// Three ways to build a SocketAddress. Parsing uses inet_pton(3) under
// the hood, so DNS names are NOT resolved — pass literal IP addresses.

let ipv4 = try SocketAddress.ipv4("127.0.0.1", port: 8080)
print(ipv4.port)
// Prints: 8080

let ipv6 = try SocketAddress.ipv6("::1", port: 9090)
print(ipv6.port)
// Prints: 9090

// Wildcard for server bind — 0.0.0.0:7000 on every local IPv4 interface.
let wildcard = SocketAddress.anyIPv4(port: 7000)
print(wildcard.port)
// Prints: 7000
