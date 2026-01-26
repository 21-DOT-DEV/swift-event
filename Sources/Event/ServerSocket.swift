import Foundation
import libevent

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A TCP server socket that accepts incoming connections.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class ServerSocket: @unchecked Sendable {
    /// The underlying file descriptor.
    let fd: Int32
    
    /// The event loop this socket uses.
    let loop: EventLoop
    
    /// Creates a server socket from an existing file descriptor.
    init(fd: Int32, loop: EventLoop) {
        self.fd = fd
        self.loop = loop
        
        // Set non-blocking
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
    
    deinit {
        #if canImport(Darwin)
        Darwin.close(fd)
        #else
        Glibc.close(fd)
        #endif
    }
    
    /// Accepts a single incoming connection.
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
    
    /// An async sequence of incoming connections.
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
    
    /// Closes the server socket.
    public func close() {
        #if canImport(Darwin)
        Darwin.close(fd)
        #else
        Glibc.close(fd)
        #endif
    }
}

// MARK: - Helper Classes

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private final class AcceptContinuationBox: @unchecked Sendable {
    let continuation: CheckedContinuation<Socket, Error>
    let loop: EventLoop
    
    init(continuation: CheckedContinuation<Socket, Error>, loop: EventLoop) {
        self.continuation = continuation
        self.loop = loop
    }
}
