import Foundation
import libevent

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// An async non-blocking TCP socket backed by libevent.
///
/// ## Overview
///
/// `Socket` wraps a POSIX file descriptor configured for non-blocking I/O and drives
/// it through an ``EventLoop`` so that ``read(maxBytes:timeout:)`` and ``write(_:timeout:)`` resume
/// their callers only when the kernel indicates data readiness. The async surface
/// (`async throws` methods) composes naturally with Swift structured concurrency;
/// the underlying mechanism is libevent callbacks bridging to `CheckedContinuation`s.
///
/// `Socket` covers three roles:
///
/// - **TCP client** — acquired via ``connect(to:port:loop:timeout:)`` or
///   ``connect(to:loop:timeout:)``.
/// - **Accepted server connection** — delivered by ``ServerSocket/accept()`` or the
///   ``ServerSocket/connections`` stream.
/// - **Wrapping an existing descriptor** — not exposed publicly (the initializer is
///   `internal`), but used by the library itself when an external fd must be adopted.
///
/// Server-listener construction lives on ``Socket/listen(port:backlog:loop:)`` and
/// ``Socket/listen(on:backlog:loop:)``, which return a ``ServerSocket`` — not a `Socket`.
///
/// ### Resource ownership
///
/// A `Socket` owns its descriptor by default: `deinit` calls `close(2)`. The
/// `ownsDescriptor` initializer flag exists so callers can wrap an externally-owned
/// fd without double-close risk; this path is internal today. The single-ownership
/// invariant is a constitution Principle II concern — see <doc:ProductionConsiderations>.
///
/// ### Concurrency
///
/// Marked `@unchecked Sendable` to permit handoff of ownership across task boundaries.
/// Concurrent I/O on the same `Socket` from multiple tasks (e.g. `read` from one task
/// while `write` from another) is **undefined behavior**: the libevent callback state
/// is not synchronized, and `fd` is mutated unconditionally in `deinit`. Use
/// structured concurrency scopes to bound ownership. See <doc:ProductionConsiderations>
/// "Concurrency Model" for the honest description.
public final class Socket: @unchecked Sendable {
    /// The underlying non-blocking file descriptor.
    ///
    /// Set once at init time and never mutated afterwards
    /// (except by `close(2)` in ``close()`` / `deinit`).
    let fd: Int32

    /// The event loop that schedules read/write-ready callbacks on the descriptor.
    let loop: EventLoop

    /// Whether `deinit` should close the underlying descriptor.
    ///
    /// `true` for descriptors allocated by this class (the common case); `false` when
    /// adopting an externally-owned descriptor that another party intends to close.
    private let ownsDescriptor: Bool

    /// Creates a socket from an existing file descriptor.
    ///
    /// Internal — public entry points are ``connect(to:port:loop:timeout:)`` /
    /// ``connect(to:loop:timeout:)`` / ``ServerSocket/accept()``. Flips the descriptor to
    /// non-blocking mode (`O_NONBLOCK`).
    ///
    /// - Parameters:
    ///   - fd: The descriptor to adopt. Must be a valid open socket.
    ///   - loop: The event loop to schedule callbacks on. Defaults to
    ///     ``EventLoop/shared``.
    ///   - ownsDescriptor: If `true`, the socket closes `fd` in `deinit`.
    init(fd: Int32, loop: EventLoop = .shared, ownsDescriptor: Bool = true) {
        self.fd = fd
        self.loop = loop
        self.ownsDescriptor = ownsDescriptor
        
        // Set non-blocking
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    /// Closes the descriptor if and only if this socket owns it.
    ///
    /// The `ownsDescriptor == false` path is reserved for internal fd-adoption
    /// scenarios where the original allocator retains responsibility for closing.
    deinit {
        if ownsDescriptor {
            #if canImport(Darwin)
            Darwin.close(fd)
#else
            Glibc.close(fd)
#endif
        }
    }
    
    // MARK: - TCP Client

    /// Connects to a remote IPv4 host by numeric address.
    ///
    /// Convenience shorthand that parses `host` via ``SocketAddress/ipv4(_:port:)`` and
    /// delegates to ``connect(to:loop:timeout:)``. For IPv6 endpoints or pre-parsed
    /// addresses, use ``connect(to:loop:timeout:)`` directly.
    ///
    /// - Parameters:
    ///   - host: Numeric IPv4 address (DNS names are **not** resolved).
    ///   - port: TCP port in host byte order.
    ///   - loop: The event loop to drive. Defaults to ``EventLoop/shared``.
    ///   - timeout: Maximum time to wait for the kernel to complete the handshake.
    ///     `nil` (the default) waits indefinitely. On expiry the call throws
    ///     ``SocketError/timeout``.
    /// - Returns: A connected `Socket` ready for ``read(maxBytes:timeout:)`` / ``write(_:timeout:)``.
    /// - Throws: ``SocketError/invalidAddress(_:)``,
    ///   ``SocketError/socketCreationFailed(_:)``,
    ///   ``SocketError/connectionFailed(_:)``, or ``SocketError/timeout``.
    public static func connect(to host: String, port: UInt16, loop: EventLoop = .shared, timeout: Duration? = nil) async throws -> Socket {
        let address = try SocketAddress.ipv4(host, port: port)
        return try await connect(to: address, loop: loop, timeout: timeout)
    }

    /// Connects to a remote ``SocketAddress``.
    ///
    /// Creates a fresh non-blocking TCP socket, calls `connect(2)`, and (for
    /// `EINPROGRESS`) registers an `EV_WRITE` event to resume the continuation when
    /// the kernel completes the handshake — bounded by `timeout` if provided.
    ///
    /// - Parameters:
    ///   - address: A pre-built endpoint from ``SocketAddress``.
    ///   - loop: The event loop to drive. Defaults to ``EventLoop/shared``.
    ///   - timeout: Maximum time to wait for handshake completion. `nil` (default)
    ///     waits indefinitely. On expiry the call throws ``SocketError/timeout``;
    ///     the partially-connected descriptor is closed before the error is thrown.
    /// - Returns: A connected `Socket`.
    /// - Throws: ``SocketError/socketCreationFailed(_:)`` if `socket(2)` fails;
    ///   ``SocketError/connectionFailed(_:)`` if `connect(2)` fails with anything
    ///   other than `EINPROGRESS`; ``SocketError/timeout`` if `timeout` elapses
    ///   before the kernel reports write-readiness.
    public static func connect(to address: SocketAddress, loop: EventLoop = .shared, timeout: Duration? = nil) async throws -> Socket {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
#else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
#endif
        guard fd >= 0 else {
            throw SocketError.socketCreationFailed(errno)
        }

        let sock = Socket(fd: fd, loop: loop)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var addr = address.storage
            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    #if canImport(Darwin)
                    Darwin.connect(fd, sockaddrPtr, address.length)
#else
                    Glibc.connect(fd, sockaddrPtr, address.length)
#endif
                }
            }

            if result == 0 {
                continuation.resume()
                return
            }

            if errno == EINPROGRESS {
                let event = event_new(loop.base, fd, Int16(EV_WRITE), { _, events, ctx in
                    let cont = Unmanaged<AnyObject>.fromOpaque(ctx!).takeRetainedValue() as! CheckedContinuationBox<Void, Error>
                    if events & Int16(libevent.EV_TIMEOUT) != 0 {
                        cont.continuation.resume(throwing: SocketError.timeout)
                    } else {
                        cont.continuation.resume()
                    }
                }, Unmanaged.passRetained(CheckedContinuationBox(continuation)).toOpaque())

                if var tv = timeout.map(EventLoop.timeval(for:)) {
                    event_add(event, &tv)
                } else {
                    event_add(event, nil)
                }
                loop.runOnce()
            } else {
                continuation.resume(throwing: SocketError.connectionFailed(errno))
            }
        }

        return sock
    }
    
    // MARK: - TCP Server

    /// Creates a listening server socket bound to any local IPv4 interface on `port`.
    ///
    /// Shorthand for `listen(on: SocketAddress.anyIPv4(port:), ...)`.
    ///
    /// - Parameters:
    ///   - port: TCP port in host byte order. Passing `0` asks the kernel to assign an
    ///     ephemeral port.
    ///   - backlog: The `listen(2)` backlog size. Default `128` matches common Linux
    ///     tuning.
    ///   - loop: The event loop to drive. Defaults to ``EventLoop/shared``.
    /// - Returns: A ``ServerSocket`` ready to accept connections.
    /// - Throws: ``SocketError/socketCreationFailed(_:)``,
    ///   ``SocketError/bindFailed(_:)``, or ``SocketError/listenFailed(_:)``.
    public static func listen(port: UInt16, backlog: Int32 = 128, loop: EventLoop = .shared) async throws -> ServerSocket {
        let address = SocketAddress.anyIPv4(port: port)
        return try await listen(on: address, backlog: backlog, loop: loop)
    }

    /// Creates a listening server socket bound to a specific ``SocketAddress``.
    ///
    /// Applies `SO_REUSEADDR` before `bind(2)` so that restart-after-crash doesn't
    /// block on `TIME_WAIT` sockets. On failure, closes the allocated fd before
    /// throwing, so no descriptor leaks (constitution Principle II).
    ///
    /// - Parameters:
    ///   - address: The local endpoint to bind. Only IPv4 is currently supported —
    ///     passing an IPv6 address will succeed at bind time only if the caller has
    ///     previously coerced the kernel's `AF_INET` socket to accept it (generally
    ///     not recommended; IPv6 server support is a future enhancement).
    ///   - backlog: The `listen(2)` backlog size.
    ///   - loop: The event loop to drive.
    /// - Returns: A ``ServerSocket`` ready to accept connections.
    /// - Throws: ``SocketError/socketCreationFailed(_:)``,
    ///   ``SocketError/bindFailed(_:)``, or ``SocketError/listenFailed(_:)``.
    public static func listen(on address: SocketAddress, backlog: Int32 = 128, loop: EventLoop = .shared) async throws -> ServerSocket {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
#else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
#endif
        guard fd >= 0 else {
            throw SocketError.socketCreationFailed(errno)
        }
        
        // Set SO_REUSEADDR
        var reuseAddr: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        
        // Bind
        var addr = address.storage
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, address.length)
            }
        }
        
        guard bindResult == 0 else {
            #if canImport(Darwin)
            Darwin.close(fd)
#else
            Glibc.close(fd)
#endif
            throw SocketError.bindFailed(errno)
        }
        
        // Listen
        #if canImport(Darwin)
        let listenResult = Darwin.listen(fd, backlog)
        #else
        let listenResult = Glibc.listen(fd, backlog)
        #endif
        guard listenResult == 0 else {
            #if canImport(Darwin)
            Darwin.close(fd)
            #else
            Glibc.close(fd)
            #endif
            throw SocketError.listenFailed(errno)
        }
        
        return ServerSocket(fd: fd, loop: loop)
    }
    
    // MARK: - I/O Operations

    /// Reads up to `maxBytes` bytes from the socket, awaiting readiness.
    ///
    /// Registers an `EV_READ` event and drives the loop until the descriptor is
    /// readable, then issues a single `read(2)` syscall.
    ///
    /// > Important: The `maxBytes` parameter is currently advisory — the internal
    /// > buffer is fixed at 4096 bytes regardless. This is a known limitation; the
    /// > parameter is preserved for ABI stability so a future release can honor it
    /// > without breaking callers.
    ///
    /// - Parameters:
    ///   - maxBytes: Requested maximum byte count (ignored today; see note).
    ///   - timeout: Maximum time to wait for readability. `nil` (default) waits
    ///     indefinitely. On expiry the call throws ``SocketError/timeout`` and the
    ///     socket remains usable for retry.
    /// - Returns: The data read from the socket.
    /// - Throws: ``SocketError/connectionClosed`` on orderly peer shutdown
    ///   (`read(2)` returns 0), ``SocketError/readFailed(_:)`` with the errno
    ///   payload on transport failure, or ``SocketError/timeout`` if `timeout`
    ///   elapses before data arrives.
    public func read(maxBytes: Int = 4096, timeout: Duration? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let event = event_new(loop.base, fd, Int16(EV_READ), { fd, events, ctx in
                let cont = Unmanaged<AnyObject>.fromOpaque(ctx!).takeRetainedValue() as! CheckedContinuationBox<Data, Error>

                if events & Int16(libevent.EV_TIMEOUT) != 0 {
                    cont.continuation.resume(throwing: SocketError.timeout)
                    return
                }

                var buffer = [UInt8](repeating: 0, count: 4096)
                #if canImport(Darwin)
                let bytesRead = Darwin.read(fd, &buffer, buffer.count)
                #else
                let bytesRead = Glibc.read(fd, &buffer, buffer.count)
                #endif

                if bytesRead > 0 {
                    cont.continuation.resume(returning: Data(buffer[0..<bytesRead]))
                } else if bytesRead == 0 {
                    cont.continuation.resume(throwing: SocketError.connectionClosed)
                } else {
                    cont.continuation.resume(throwing: SocketError.readFailed(errno))
                }
            }, Unmanaged.passRetained(CheckedContinuationBox(continuation)).toOpaque())

            if var tv = timeout.map(EventLoop.timeval(for:)) {
                event_add(event, &tv)
            } else {
                event_add(event, nil)
            }
            loop.runOnce()
        }
    }

    /// Writes all bytes in `data` to the socket, awaiting write-readiness.
    ///
    /// Registers an `EV_WRITE` event and drives the loop until the descriptor is
    /// writable, then issues a single `write(2)` syscall covering the full buffer.
    ///
    /// > Warning: This implementation does **not** handle partial writes — if the
    /// > kernel accepts fewer bytes than requested the remainder is silently
    /// > discarded (the callback just reports success). In practice, small writes
    /// > on connected TCP sockets complete in one syscall on all supported platforms,
    /// > but callers writing large buffers should chunk explicitly until the
    /// > planned backpressure helper lands. See <doc:ProductionConsiderations>.
    ///
    /// - Parameters:
    ///   - data: The bytes to send.
    ///   - timeout: Maximum time to wait for write-readiness. `nil` (default) waits
    ///     indefinitely. On expiry the call throws ``SocketError/timeout`` without
    ///     having written any bytes.
    /// - Throws: ``SocketError/writeFailed(_:)`` with the errno payload if
    ///   `write(2)` returns a negative value (e.g. `EPIPE` when the peer closed),
    ///   or ``SocketError/timeout`` if `timeout` elapses first.
    public func write(_ data: Data, timeout: Duration? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let event = event_new(loop.base, fd, Int16(EV_WRITE), { fd, events, ctx in
                let box = Unmanaged<AnyObject>.fromOpaque(ctx!).takeRetainedValue() as! WriteBox

                if events & Int16(libevent.EV_TIMEOUT) != 0 {
                    box.continuation.resume(throwing: SocketError.timeout)
                    return
                }

                let result = box.data.withUnsafeBytes { ptr in
                    #if canImport(Darwin)
                    Darwin.write(fd, ptr.baseAddress!, ptr.count)
#else
                    Glibc.write(fd, ptr.baseAddress!, ptr.count)
#endif
                }

                if result >= 0 {
                    box.continuation.resume()
                } else {
                    box.continuation.resume(throwing: SocketError.writeFailed(errno))
                }
            }, Unmanaged.passRetained(WriteBox(data: data, continuation: continuation)).toOpaque())

            if var tv = timeout.map(EventLoop.timeval(for:)) {
                event_add(event, &tv)
            } else {
                event_add(event, nil)
            }
            loop.runOnce()
        }
    }
    
    // MARK: - Address Introspection

    /// The local endpoint of this socket, as reported by `getsockname(2)`.
    ///
    /// For an accepted server-side socket this is the listener's address; for
    /// a connected client socket this is the kernel-assigned ephemeral local
    /// endpoint. Returns `nil` if the syscall fails (e.g. the descriptor is
    /// closed).
    public var localAddress: SocketAddress? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &length)
            }
        }
        guard result == 0 else { return nil }
        return SocketAddress.from(storage: storage, length: length)
    }

    /// The local TCP port of this socket (host byte order).
    ///
    /// Convenience over ``localAddress``. Returns `0` if the address is not
    /// available or the family is not `AF_INET` / `AF_INET6`.
    public var localPort: UInt16 {
        localAddress?.port ?? 0
    }

    /// The peer's endpoint, as reported by `getpeername(2)`.
    ///
    /// On an accepted server-side socket this is the connecting client; on a
    /// connected client socket this is the server. Returns `nil` if the
    /// syscall fails (e.g. the socket is not connected, or has been closed).
    public var remoteAddress: SocketAddress? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getpeername(fd, sa, &length)
            }
        }
        guard result == 0 else { return nil }
        return SocketAddress.from(storage: storage, length: length)
    }

    /// The peer's TCP port (host byte order).
    ///
    /// Convenience over ``remoteAddress``. Returns `0` if the peer address is
    /// not available.
    public var remotePort: UInt16 {
        remoteAddress?.port ?? 0
    }

    /// Closes the socket's descriptor immediately.
    ///
    /// `async` for API symmetry with other methods; the underlying `close(2)` is
    /// synchronous. Safe to call even when `ownsDescriptor == false` — the caller is
    /// acknowledging ownership at call time. Subsequent I/O will fail with the
    /// appropriate errno-carrying error.
    public func close() async {
        #if canImport(Darwin)
            Darwin.close(fd)
#else
            Glibc.close(fd)
#endif
    }
}

// MARK: - Helper Classes

/// Retained continuation box for the read callback path.
///
/// `@unchecked Sendable` because its stored `CheckedContinuation` is consumed exactly
/// once by a single libevent callback invocation; Unmanaged retain/release bookends
/// the lifetime so there is no concurrent access in practice.
private final class CheckedContinuationBox<T, E: Error>: @unchecked Sendable {
    let continuation: CheckedContinuation<T, E>
    
    init(_ continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }
}

/// Retained continuation + payload box for the write callback path.
///
/// `@unchecked Sendable` for the same reasons as ``CheckedContinuationBox``. The
/// stored `Data` is never mutated after construction.
private final class WriteBox: @unchecked Sendable {
    let data: Data
    let continuation: CheckedContinuation<Void, Error>
    
    init(data: Data, continuation: CheckedContinuation<Void, Error>) {
        self.data = data
        self.continuation = continuation
    }
}
