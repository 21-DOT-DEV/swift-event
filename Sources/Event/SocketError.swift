import Foundation

/// An error surfaced by ``SocketAddress``, ``Socket``, and ``ServerSocket`` operations.
///
/// ## Overview
///
/// `SocketError` is the sole error type thrown by the idiomatic ``Event`` API for TCP
/// I/O and address parsing. Every case carries either a user-supplied string (for
/// input-validation failures) or the raw `errno` value captured at the point of failure,
/// so callers can disambiguate transient conditions (e.g. `EINPROGRESS`, `EAGAIN`) from
/// permanent failures (e.g. `ECONNREFUSED`).
///
/// ### Interpreting the errno payload
///
/// The `Int32` payload attached to `.connectionFailed`, `.bindFailed`, `.listenFailed`,
/// `.acceptFailed`, `.readFailed`, `.writeFailed`, and `.socketCreationFailed` is the
/// value of `errno` immediately after the failing `connect(2)` / `bind(2)` / `listen(2)` /
/// `accept(2)` / `read(2)` / `write(2)` / `socket(2)` syscall. It is **not** a POSIX
/// abstraction — it is the platform's raw errno. To render a human-readable string, pass
/// it through `strerror(_:)`; the default ``errorDescription`` does this for you.
///
/// ### When each case is thrown
///
/// - ``SocketError/invalidAddress(_:)`` — ``SocketAddress/ipv4(_:port:)`` or
///   ``SocketAddress/ipv6(_:port:)`` rejected the input string. The payload is the
///   original host string.
/// - ``SocketError/socketCreationFailed(_:)`` — `socket(2)` failed inside
///   ``Socket/connect(to:port:loop:)`` or ``Socket/listen(port:backlog:loop:)``.
/// - ``SocketError/connectionFailed(_:)`` — `connect(2)` returned a non-`EINPROGRESS`
///   error, or the socket's pending-write event reported failure.
/// - ``SocketError/bindFailed(_:)`` / ``SocketError/listenFailed(_:)`` — server-socket
///   setup failed after socket creation.
/// - ``SocketError/acceptFailed(_:)`` — `accept(2)` on a ``ServerSocket`` returned a
///   negative value.
/// - ``SocketError/readFailed(_:)`` / ``SocketError/writeFailed(_:)`` — the underlying
///   `read(2)` / `write(2)` returned a negative value.
/// - ``SocketError/connectionClosed`` — `read(2)` returned 0 (orderly shutdown by peer).
/// - ``SocketError/timeout`` — reserved for future timeout-based APIs; not emitted today.
///
/// - SeeAlso: <doc:ProductionConsiderations> for the current caveat list, including
///   behaviors not yet wrapped (UDP, TLS, timeouts, cancellation).
public enum SocketError: Error, Sendable {
    /// The host string could not be parsed as an IPv4 or IPv6 address.
    ///
    /// Thrown by ``SocketAddress/ipv4(_:port:)`` and ``SocketAddress/ipv6(_:port:)`` when
    /// the underlying `inet_pton(3)` call returns 0. The payload is the original host
    /// string so callers can log or surface it.
    case invalidAddress(String)

    /// The TCP `connect(2)` syscall failed with a non-recoverable error.
    ///
    /// - Parameter errno: The raw errno captured at failure. `EINPROGRESS` is handled
    ///   internally and does **not** surface as this error; values you can expect here
    ///   include `ECONNREFUSED`, `ETIMEDOUT`, `ENETUNREACH`, and `EHOSTUNREACH`.
    case connectionFailed(Int32)

    /// `bind(2)` failed while setting up a listening server socket.
    ///
    /// - Parameter errno: Typical values include `EADDRINUSE` (port already bound) and
    ///   `EACCES` (privileged port without permission).
    case bindFailed(Int32)

    /// `listen(2)` failed after a successful `bind(2)`.
    ///
    /// - Parameter errno: The raw errno captured at failure. Rare in practice.
    case listenFailed(Int32)

    /// `accept(2)` on a ``ServerSocket`` returned a negative result.
    ///
    /// - Parameter errno: Transient errors like `EAGAIN` are filtered by the event loop
    ///   and will not surface here; values you can expect include `ECONNABORTED` and
    ///   `EMFILE` (per-process fd limit reached).
    case acceptFailed(Int32)

    /// `read(2)` returned a negative value (not EOF).
    ///
    /// - Parameter errno: Typical values include `ECONNRESET` and `ETIMEDOUT`. For an
    ///   orderly peer-initiated shutdown see ``SocketError/connectionClosed``.
    case readFailed(Int32)

    /// `write(2)` returned a negative value.
    ///
    /// - Parameter errno: Typical values include `EPIPE` (peer closed read side) and
    ///   `ECONNRESET`. Note that swift-event does not install a `SIGPIPE` handler; see
    ///   <doc:ProductionConsiderations> for the platform-specific story.
    case writeFailed(Int32)

    /// `socket(2)` failed to allocate a new file descriptor.
    ///
    /// - Parameter errno: Typical values include `EMFILE` (per-process fd limit) and
    ///   `ENFILE` (system-wide fd limit).
    case socketCreationFailed(Int32)

    /// The peer performed an orderly shutdown of its write side (`read(2)` returned 0).
    ///
    /// Surfaced from ``Socket/read(maxBytes:)`` to distinguish EOF from a transport error.
    case connectionClosed

    /// A timeout fired on an operation that supports one.
    ///
    /// Reserved for future APIs; not currently emitted by any public method in this
    /// release. Included in the enum so that the ABI is stable when timeouts land.
    case timeout
}

extension SocketError: LocalizedError {
    /// A human-readable description of the error suitable for logging.
    ///
    /// Cases that carry an `errno` payload are rendered via `strerror(3)` so the message
    /// reflects the platform's canonical wording (e.g. `"Connection refused"` on both
    /// macOS and Linux for `ECONNREFUSED`).
    public var errorDescription: String? {
        switch self {
        case .invalidAddress(let addr):
            return "Invalid address: \(addr)"
        case .connectionFailed(let errno):
            return "Connection failed: \(String(cString: strerror(errno)))"
        case .bindFailed(let errno):
            return "Bind failed: \(String(cString: strerror(errno)))"
        case .listenFailed(let errno):
            return "Listen failed: \(String(cString: strerror(errno)))"
        case .acceptFailed(let errno):
            return "Accept failed: \(String(cString: strerror(errno)))"
        case .readFailed(let errno):
            return "Read failed: \(String(cString: strerror(errno)))"
        case .writeFailed(let errno):
            return "Write failed: \(String(cString: strerror(errno)))"
        case .socketCreationFailed(let errno):
            return "Socket creation failed: \(String(cString: strerror(errno)))"
        case .connectionClosed:
            return "Connection closed by remote"
        case .timeout:
            return "Operation timed out"
        }
    }
}
