import Foundation

/// A network socket address (IPv4 or IPv6).
public struct SocketAddress: Sendable {
    /// The underlying socket address storage.
    var storage: sockaddr_storage
    
    /// The address length.
    var length: socklen_t
    
    /// Creates an IPv4 socket address.
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
    
    /// Creates an IPv6 socket address.
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
    
    /// Creates an address for any interface on the given port.
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
    
    /// The port number.
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
