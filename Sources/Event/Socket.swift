import Foundation
import libevent

/// An async TCP socket backed by libevent.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class Socket: @unchecked Sendable {
    /// The underlying file descriptor.
    let fd: Int32
    
    /// The event loop this socket uses.
    let loop: EventLoop
    
    /// Whether this socket owns the file descriptor (should close on deinit).
    private let ownsDescriptor: Bool
    
    /// Creates a socket from an existing file descriptor.
    init(fd: Int32, loop: EventLoop = .shared, ownsDescriptor: Bool = true) {
        self.fd = fd
        self.loop = loop
        self.ownsDescriptor = ownsDescriptor
        
        // Set non-blocking
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
    
    deinit {
        if ownsDescriptor {
            Darwin.close(fd)
        }
    }
    
    // MARK: - TCP Client
    
    /// Connects to a remote host.
    public static func connect(to host: String, port: UInt16, loop: EventLoop = .shared) async throws -> Socket {
        let address = try SocketAddress.ipv4(host, port: port)
        return try await connect(to: address, loop: loop)
    }
    
    /// Connects to a remote address.
    public static func connect(to address: SocketAddress, loop: EventLoop = .shared) async throws -> Socket {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SocketError.socketCreationFailed(errno)
        }
        
        let sock = Socket(fd: fd, loop: loop)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var addr = address.storage
            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(fd, sockaddrPtr, address.length)
                }
            }
            
            if result == 0 {
                continuation.resume()
                return
            }
            
            if errno == EINPROGRESS {
                // Connection in progress, wait for write event
                let event = event_new(loop.base, fd, Int16(EV_WRITE), { _, _, ctx in
                    let cont = Unmanaged<AnyObject>.fromOpaque(ctx!).takeRetainedValue() as! CheckedContinuationBox<Void, Error>
                    cont.continuation.resume()
                }, Unmanaged.passRetained(CheckedContinuationBox(continuation)).toOpaque())
                
                event_add(event, nil)
            } else {
                continuation.resume(throwing: SocketError.connectionFailed(errno))
            }
        }
        
        return sock
    }
    
    // MARK: - TCP Server
    
    /// Creates a listening server socket.
    public static func listen(port: UInt16, backlog: Int32 = 128, loop: EventLoop = .shared) async throws -> ServerSocket {
        let address = SocketAddress.anyIPv4(port: port)
        return try await listen(on: address, backlog: backlog, loop: loop)
    }
    
    /// Creates a listening server socket on a specific address.
    public static func listen(on address: SocketAddress, backlog: Int32 = 128, loop: EventLoop = .shared) async throws -> ServerSocket {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
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
            Darwin.close(fd)
            throw SocketError.bindFailed(errno)
        }
        
        // Listen
        guard Darwin.listen(fd, backlog) == 0 else {
            Darwin.close(fd)
            throw SocketError.listenFailed(errno)
        }
        
        return ServerSocket(fd: fd, loop: loop)
    }
    
    // MARK: - I/O Operations
    
    /// Reads up to maxBytes from the socket.
    public func read(maxBytes: Int = 4096) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let event = event_new(loop.base, fd, Int16(EV_READ), { fd, _, ctx in
                let cont = Unmanaged<AnyObject>.fromOpaque(ctx!).takeRetainedValue() as! CheckedContinuationBox<Data, Error>
                
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = Darwin.read(fd, &buffer, buffer.count)
                
                if bytesRead > 0 {
                    cont.continuation.resume(returning: Data(buffer[0..<bytesRead]))
                } else if bytesRead == 0 {
                    cont.continuation.resume(throwing: SocketError.connectionClosed)
                } else {
                    cont.continuation.resume(throwing: SocketError.readFailed(errno))
                }
            }, Unmanaged.passRetained(CheckedContinuationBox(continuation)).toOpaque())
            
            event_add(event, nil)
            loop.runOnce()
        }
    }
    
    /// Writes data to the socket.
    public func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let event = event_new(loop.base, fd, Int16(EV_WRITE), { fd, _, ctx in
                let box = Unmanaged<AnyObject>.fromOpaque(ctx!).takeRetainedValue() as! WriteBox
                
                let result = box.data.withUnsafeBytes { ptr in
                    Darwin.write(fd, ptr.baseAddress!, ptr.count)
                }
                
                if result >= 0 {
                    box.continuation.resume()
                } else {
                    box.continuation.resume(throwing: SocketError.writeFailed(errno))
                }
            }, Unmanaged.passRetained(WriteBox(data: data, continuation: continuation)).toOpaque())
            
            event_add(event, nil)
            loop.runOnce()
        }
    }
    
    /// Closes the socket.
    public func close() async {
        Darwin.close(fd)
    }
}

// MARK: - Helper Classes

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private final class CheckedContinuationBox<T, E: Error>: @unchecked Sendable {
    let continuation: CheckedContinuation<T, E>
    
    init(_ continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private final class WriteBox: @unchecked Sendable {
    let data: Data
    let continuation: CheckedContinuation<Void, Error>
    
    init(data: Data, continuation: CheckedContinuation<Void, Error>) {
        self.data = data
        self.continuation = continuation
    }
}
