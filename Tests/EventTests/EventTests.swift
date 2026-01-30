import Testing
@testable import Event

@Suite("Event Tests")
struct EventTests {
    @Test("EventLoop can be created")
    func eventLoopCreation() {
        let loop = EventLoop()
        #expect(loop.base != nil)
    }
    
    @Test("SocketAddress can create IPv4 address")
    func socketAddressIPv4() throws {
        let address = try SocketAddress.ipv4("127.0.0.1", port: 8080)
        #expect(address.port == 8080)
    }
    
    @Test("SocketAddress can create any IPv4 address")
    func socketAddressAnyIPv4() {
        let address = SocketAddress.anyIPv4(port: 9090)
        #expect(address.port == 9090)
    }
    
    @Test("SocketAddress rejects invalid address")
    func socketAddressInvalid() {
        #expect(throws: SocketError.self) {
            _ = try SocketAddress.ipv4("not.an.ip.address", port: 8080)
        }
    }
    
    @Test("EventLoop uses optimal backend")
    func eventLoopBackend() {
        let loop = EventLoop()
        let method = loop.backendMethod
        
        #if os(Linux)
        #expect(method == "epoll", "Expected epoll on Linux, got \(method)")
        #elseif os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        #expect(method == "kqueue", "Expected kqueue on Apple platforms, got \(method)")
        #endif
    }
}
