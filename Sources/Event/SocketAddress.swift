import Foundation

/// A network socket address backed by `sockaddr_storage` (IPv4 or IPv6).
///
/// ## Overview
///
/// `SocketAddress` is a value-type Swift wrapper over POSIX `sockaddr_storage` — the
/// address-family-agnostic container defined in [RFC 2553 §3.10][rfc2553] and the
/// [POSIX sys/socket.h specification][posix]. It is large enough to hold any supported
/// address family (`sockaddr_in` for IPv4, `sockaddr_in6` for IPv6) without heap
/// allocation, and is safe to pass across task boundaries thanks to its `Sendable`
/// conformance (all stored properties are value types).
///
/// [rfc2553]: https://datatracker.ietf.org/doc/html/rfc2553#section-3.10
/// [posix]: https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/sys_socket.h.html
///
/// ### Byte order
///
/// The `port` property and the ``port`` accessor transparently handle the network-to-host
/// byte-order conversion: input to ``ipv4(_:port:)`` / ``ipv6(_:port:)`` / ``anyIPv4(port:)``
/// is in **host byte order**, stored internally in **network byte order** (big-endian),
/// and returned in host byte order. Callers never need to touch `htons` / `ntohs`.
///
/// ### Address parsing
///
/// Parsing is delegated to `inet_pton(3)`, which accepts standard numeric notation
/// (`"127.0.0.1"`, `"::1"`, `"2001:db8::1"`). Hostname resolution via DNS is **not**
/// performed — pass a literal IP address. For DNS, perform the lookup separately
/// (e.g. via `Foundation` / `Network.framework`) and feed the resulting address string
/// into one of the factory methods.
///
/// ### Usage
///
/// ```swift
/// import Event
///
/// let loopback4 = try SocketAddress.ipv4("127.0.0.1", port: 8080)
/// let loopback6 = try SocketAddress.ipv6("::1", port: 8080)
/// let wildcard = SocketAddress.anyIPv4(port: 8080)
/// print(loopback4.port)  // 8080
/// ```
///
/// - SeeAlso: ``Socket/connect(to:loop:)``, ``Socket/listen(on:backlog:loop:)``,
///   ``SocketError/invalidAddress(_:)``.
public struct SocketAddress: Sendable {
    /// The underlying `sockaddr_storage` container.
    ///
    /// Value-typed — cheap to copy, no pointer aliasing. The storage is interpreted
    /// according to its `ss_family` field (`AF_INET` vs `AF_INET6`).
    var storage: sockaddr_storage

    /// The meaningful prefix length of the storage (e.g. `sizeof(sockaddr_in)` for IPv4).
    ///
    /// Passed directly to kernel syscalls (`bind(2)`, `connect(2)`). Not the full size of
    /// `sockaddr_storage` — a smaller family-specific size so the kernel reads only the
    /// valid bytes.
    var length: socklen_t

    /// Creates an IPv4 socket address from a dotted-quad string.
    ///
    /// - Parameters:
    ///   - host: A numeric IPv4 address such as `"127.0.0.1"` or `"192.168.1.1"`. DNS
    ///     names are **not** accepted.
    ///   - port: A port number in host byte order (1-65535).
    /// - Returns: A ready-to-use `SocketAddress` backed by `sockaddr_in`.
    /// - Throws: ``SocketError/invalidAddress(_:)`` if `inet_pton(3)` rejects `host`.
    /// - SeeAlso: ``ipv6(_:port:)``, ``anyIPv4(port:)``.
    public static func ipv4(_ host: String, port: UInt16) throws -> SocketAddress {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            throw SocketError.invalidAddress(host)
        }
        
        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: &addr) { src in
                dest.copyMemory(from: src)
            }
        }
        
        return SocketAddress(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in>.size))
    }
    
    /// Creates an IPv6 socket address from a colon-notation string.
    ///
    /// - Parameters:
    ///   - host: A numeric IPv6 address such as `"::1"` or `"2001:db8::1"`. DNS names are
    ///     **not** accepted; IPv4-mapped IPv6 (`"::ffff:192.0.2.1"`) is accepted per
    ///     [RFC 4291 §2.5.5.2][rfc4291].
    ///   - port: A port number in host byte order (1-65535).
    /// - Returns: A ready-to-use `SocketAddress` backed by `sockaddr_in6`.
    /// - Throws: ``SocketError/invalidAddress(_:)`` if `inet_pton(3)` rejects `host`.
    ///
    /// [rfc4291]: https://datatracker.ietf.org/doc/html/rfc4291#section-2.5.5.2
    ///
    /// - SeeAlso: ``ipv4(_:port:)``, ``anyIPv4(port:)``.
    public static func ipv6(_ host: String, port: UInt16) throws -> SocketAddress {
        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        
        guard inet_pton(AF_INET6, host, &addr.sin6_addr) == 1 else {
            throw SocketError.invalidAddress(host)
        }
        
        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: &addr) { src in
                dest.copyMemory(from: src)
            }
        }
        
        return SocketAddress(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in6>.size))
    }
    
    /// Creates an IPv4 wildcard address (`0.0.0.0` / `INADDR_ANY`) for the given port.
    ///
    /// Used when binding a listening server that should accept connections on **any**
    /// local interface. The wildcard semantics are defined by the platform kernel — see
    /// `ip(4)` / RFC 1122 §3.2.1.3 for details.
    ///
    /// - Parameter port: A port number in host byte order (1-65535). Passing `0` asks
    ///   the kernel to assign an ephemeral port, which you can retrieve via `getsockname(2)`
    ///   — though swift-event does not currently expose that helper.
    /// - Returns: A wildcard `SocketAddress` suitable for ``Socket/listen(on:backlog:loop:)``.
    /// - SeeAlso: ``ipv4(_:port:)``.
    public static func anyIPv4(port: UInt16) -> SocketAddress {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: &addr) { src in
                dest.copyMemory(from: src)
            }
        }
        
        return SocketAddress(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in>.size))
    }
    
    /// The port number in host byte order.
    ///
    /// Inspects the underlying storage's `ss_family` and reads `sin_port` or `sin6_port`
    /// accordingly, converting from network byte order (big-endian) back to host byte
    /// order. Returns `0` if the address family is neither `AF_INET` nor `AF_INET6` —
    /// a defensive fallback that should not occur for addresses produced by this API.
    public var port: UInt16 {
        var mutableStorage = storage
        return withUnsafePointer(to: &mutableStorage) { ptr in
            let family = Int32(storage.ss_family)
            if family == AF_INET {
                return ptr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_port.bigEndian }
            } else if family == AF_INET6 {
                return ptr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_port.bigEndian }
            }
            return 0
        }
    }
}
