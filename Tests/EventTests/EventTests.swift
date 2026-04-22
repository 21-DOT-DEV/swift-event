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

    @Test("SocketAddress can create IPv6 address")
    func socketAddressIPv6() throws {
        let address = try SocketAddress.ipv6("::1", port: 9090)
        #expect(address.port == 9090)
    }

    @Test("SocketAddress rejects invalid IPv6 address")
    func socketAddressIPv6Invalid() {
        #expect(throws: SocketError.self) {
            _ = try SocketAddress.ipv6("not.ipv6", port: 80)
        }
    }

    @Test("SocketError.invalidAddress preserves the user-supplied host string")
    func socketErrorInvalidAddressPayload() {
        do {
            _ = try SocketAddress.ipv4("definitely.not.an.ip", port: 8080)
            Issue.record("Expected SocketAddress.ipv4 to throw for non-numeric host")
        } catch let SocketError.invalidAddress(host) {
            #expect(host == "definitely.not.an.ip")
        } catch {
            Issue.record("Unexpected error type: \(error)")
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
