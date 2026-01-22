import Foundation

/// Errors that can occur during socket operations.
public enum SocketError: Error, Sendable {
    case invalidAddress(String)
    case connectionFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case acceptFailed(Int32)
    case readFailed(Int32)
    case writeFailed(Int32)
    case socketCreationFailed(Int32)
    case connectionClosed
    case timeout
}

extension SocketError: LocalizedError {
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
