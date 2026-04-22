import Foundation
import libevent

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A listening TCP server socket built on a non-blocking file descriptor and an ``EventLoop``.
///
/// ## Overview
///
/// `ServerSocket` represents a socket that has already been `bind(2)`-ed to a local
/// address and `listen(2)`-ed on. It accepts incoming client connections through two
/// ergonomic shapes:
///
/// - ``accept()`` — awaits exactly one incoming connection and returns a connected
///   ``Socket``. Use this when your protocol is request/response and you want explicit
///   control over when to service the next connection.
/// - ``connections`` — an `AsyncThrowingStream<Socket, Error>` that yields each accepted
///   `Socket` as it arrives, until the stream is cancelled or errors. Use this for
///   server loops like `for try await client in server.connections { ... }`.
///
/// Construct a `ServerSocket` via ``Socket/listen(port:backlog:loop:)`` or
/// ``Socket/listen(on:backlog:loop:)``; direct construction is not part of the public API.
///
/// ### Cancellation
///
/// The `connections` stream does **not** currently propagate `Task` cancellation down
/// into the outstanding `accept` event registration. Cancelling the owning task
/// terminates the `for-try-await` loop in your code but leaves the libevent callback
/// registered until the next activity or until the `ServerSocket` is deallocated.
/// Workarounds: call ``close()`` explicitly to tear down the listener, or drop the
/// last strong reference so `deinit` runs. See <doc:ProductionConsiderations>.
///
/// ### Concurrency
///
/// Marked `@unchecked Sendable` to permit handoff of ownership across task boundaries.
/// Concurrent `accept()` calls or simultaneous iteration of ``connections`` from multiple
/// tasks are **undefined behavior** — libevent state is not locked, and the stored
/// descriptor is closed unilaterally in `deinit`. The single-owner-per-scope discipline
/// from <doc:ProductionConsiderations> applies.
public final class ServerSocket: @unchecked Sendable {
    /// The listening file descriptor, configured non-blocking at init time.
    let fd: Int32

    /// The event loop that schedules accept-ready callbacks on the descriptor.
    let loop: EventLoop

    /// Creates a server socket from an already-listening file descriptor.
    ///
    /// Internal — consumers obtain `ServerSocket` instances via
    /// ``Socket/listen(port:backlog:loop:)``. The initializer flips the descriptor to
    /// non-blocking mode (`O_NONBLOCK`) so that kernel reads on `accept(2)` return
    /// `EAGAIN` instead of parking the thread.
    init(fd: Int32, loop: EventLoop) {
        self.fd = fd
        self.loop = loop
        
        // Set non-blocking
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    /// Unconditionally closes the descriptor on deallocation.
    ///
    /// Unlike ``Socket``, a `ServerSocket` always owns its descriptor — it's created
    /// by ``Socket/listen(on:backlog:loop:)`` with no `ownsDescriptor` escape hatch.
    deinit {
        #if canImport(Darwin)
        Darwin.close(fd)
        #else
        Glibc.close(fd)
        #endif
    }

    /// Awaits and returns a single incoming TCP connection.
    ///
    /// Registers a one-shot `EV_READ` event on the listening descriptor, drives the
    /// event loop via ``EventLoop/runOnce()``, then calls `accept(2)` in the ready
    /// callback. The returned ``Socket`` owns its descriptor and is configured for
    /// non-blocking I/O; read/write it via the normal ``Socket/read(maxBytes:)`` /
    /// ``Socket/write(_:)`` APIs.
    ///
    /// - Returns: A connected ``Socket`` for the newly-accepted client.
    /// - Throws: ``SocketError/acceptFailed(_:)`` if `accept(2)` returns a negative
    ///   value.
    /// - SeeAlso: ``connections`` for a streaming alternative.
    public func accept() async throws -> Socket {
        try await withCheckedThrowingContinuation { continuation in
            let event = event_new(loop.base, fd, Int16(EV_READ), { fd, _, ctx in
                let cont = Unmanaged<AnyObject>.fromOpaque(ctx!).takeRetainedValue() as! AcceptContinuationBox
                
                var clientAddr = sockaddr_storage()
                var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                
                let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        #if canImport(Darwin)
                        Darwin.accept(fd, sockaddrPtr, &addrLen)
                        #else
                        Glibc.accept(fd, sockaddrPtr, &addrLen)
                        #endif
                    }
                }
                
                if clientFd >= 0 {
                    let clientSocket = Socket(fd: clientFd, loop: cont.loop)
                    cont.continuation.resume(returning: clientSocket)
                } else {
                    cont.continuation.resume(throwing: SocketError.acceptFailed(errno))
                }
            }, Unmanaged.passRetained(AcceptContinuationBox(continuation: continuation, loop: loop)).toOpaque())
            
            event_add(event, nil)
            loop.runOnce()
        }
    }
    
    /// An async stream of incoming connections, yielding each accepted ``Socket``.
    ///
    /// Loops ``accept()`` in a detached `Task` and yields the resulting sockets via an
    /// `AsyncThrowingStream`. The stream terminates when ``accept()`` throws, propagating
    /// the error to the consumer. A typical server loop looks like:
    ///
    /// ```swift
    /// let server = try await Socket.listen(port: 8080)
    /// for try await client in server.connections {
    ///     Task { try await handleClient(client) }
    /// }
    /// ```
    ///
    /// > Note: Cancellation of the iterating task does not currently unregister the
    /// > outstanding libevent accept callback. Drop the `ServerSocket` or call
    /// > ``close()`` to ensure the listener is fully torn down.
    public var connections: AsyncThrowingStream<Socket, Error> {
        AsyncThrowingStream { continuation in
            Task {
                while true {
                    do {
                        let client = try await self.accept()
                        continuation.yield(client)
                    } catch {
                        continuation.finish(throwing: error)
                        break
                    }
                }
            }
        }
    }
    
    /// Closes the listening file descriptor immediately.
    ///
    /// Safe to call multiple times — the kernel will return `EBADF` on the second
    /// `close(2)`, which this wrapper ignores. Subsequent ``accept()`` calls will fail
    /// with ``SocketError/acceptFailed(_:)``.
    public func close() {
        #if canImport(Darwin)
        Darwin.close(fd)
        #else
        Glibc.close(fd)
        #endif
    }
}

// MARK: - Helper Classes

/// Retained continuation box for the `accept(2)` callback path.
///
/// `@unchecked Sendable` because its stored properties are used exclusively from a
/// single libevent callback invocation; Unmanaged retain/release bookends the
/// lifetime so there is no concurrent access in practice.
private final class AcceptContinuationBox: @unchecked Sendable {
    let continuation: CheckedContinuation<Socket, Error>
    let loop: EventLoop
    
    init(continuation: CheckedContinuation<Socket, Error>, loop: EventLoop) {
        self.continuation = continuation
        self.loop = loop
    }
}
