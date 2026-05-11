import Foundation
import Testing
@testable import Event

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

    @Test("EventLoop.sleep waits for at least the requested duration")
    func eventLoopSleep() async {
        let loop = EventLoop()
        let start = ContinuousClock.now
        await loop.sleep(for: .milliseconds(50))
        let elapsed = ContinuousClock.now - start
        #expect(elapsed >= .milliseconds(45), "sleep returned too early: \(elapsed)")
    }

    @Test("EventLoop.schedule fires the closure after the deadline")
    func eventLoopSchedule() async {
        let loop = EventLoop()
        let fired = FiredFlag()
        loop.schedule(after: .milliseconds(20)) {
            fired.set()
        }
        loop.runOnce()
        #expect(fired.value, "scheduled closure did not run after runOnce()")
    }

    @Test("Socket.read with timeout throws SocketError.timeout when no data arrives")
    func socketReadTimeout() async throws {
        // Server and client must use SEPARATE EventLoops: accept() on the server side
        // and connect() / read() on the client side both call runOnce() internally,
        // and concurrent runOnce() on a shared loop violates libevent's single-owner
        // invariant ("event_base_loop: reentrant invocation").
        let serverLoop = EventLoop()
        let clientLoop = EventLoop()
        let server = try await Socket.listen(port: 0, loop: serverLoop)
        let serverPort = server.localPort

        async let acceptedFuture = server.accept()
        let client = try await Socket.connect(to: "127.0.0.1", port: serverPort, loop: clientLoop)
        let accepted = try await acceptedFuture

        do {
            _ = try await client.read(maxBytes: 16, timeout: .milliseconds(50))
            Issue.record("Expected SocketError.timeout, got data")
        } catch SocketError.timeout {
            // expected
        } catch {
            Issue.record("Expected SocketError.timeout, got \(error)")
        }

        await client.close()
        await accepted.close()
        server.close()
    }

    @Test("ServerSocket.localPort returns the kernel-assigned ephemeral port for port 0 binds")
    func serverSocketLocalPort() async throws {
        let loop = EventLoop()
        let server = try await Socket.listen(port: 0, loop: loop)
        let port = server.localPort
        #expect(port != 0, "localPort should be a kernel-assigned non-zero port")
        let address = server.localAddress
        #expect(address != nil)
        #expect(address?.port == port)
        server.close()
    }

    @Test("Socket.remoteAddress reflects the connected peer endpoint")
    func socketRemoteAddress() async throws {
        let serverLoop = EventLoop()
        let clientLoop = EventLoop()
        let server = try await Socket.listen(port: 0, loop: serverLoop)
        let serverPort = server.localPort

        async let acceptedFuture = server.accept()
        let client = try await Socket.connect(to: "127.0.0.1", port: serverPort, loop: clientLoop)
        let accepted = try await acceptedFuture

        // The server's accepted socket sees the client's ephemeral local port as its remote.
        #expect(accepted.remotePort == client.localPort,
                "accepted.remotePort (\(accepted.remotePort)) should equal client.localPort (\(client.localPort))")
        // The client's remote port should be the server's listening port.
        #expect(client.remotePort == serverPort,
                "client.remotePort (\(client.remotePort)) should equal server's listening port \(serverPort)")

        await client.close()
        await accepted.close()
        server.close()
    }

    @Test("EventLoop.signalStream yields a self-sent SIGUSR1")
    func eventLoopSignalStream() async throws {
        let loop = EventLoop()
        // Ignore default disposition first — libevent will install its own
        // handler on event_add, but on Apple platforms SIGUSR1's default is
        // process termination, so a race between Task setup and our raise(2)
        // could otherwise kill the test runner.
        signal(SIGUSR1, SIG_IGN)
        defer { signal(SIGUSR1, SIG_DFL) }

        let stream = loop.signalStream(SIGUSR1)
        var iterator = stream.makeAsyncIterator()

        // Drive the loop while waiting for the signal: the iterator's `next()`
        // suspends until the stream yields, but the yield happens inside a
        // libevent callback driven by `runOnce()`. Spawn a Task to send the
        // signal once the loop is running.
        Task {
            // Tiny delay to let the iterator subscribe before we raise.
            try? await Task.sleep(for: .milliseconds(20))
            raise(SIGUSR1)
        }

        // Drive the loop until the signal fires (capped to avoid hanging tests).
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            loop.runOnce()
            // After runOnce returns, the SignalBox callback has yielded into
            // the stream. Try to consume the value with a short timeout.
            if let received = await iterator.next() {
                #expect(received == SIGUSR1)
                return
            }
        }
        Issue.record("signalStream did not yield within 2s")
    }
}

/// Simple `Sendable` flag used by tests that need to assert a callback fired.
private final class FiredFlag: @unchecked Sendable {
    private var _value = false
    func set() { _value = true }
    var value: Bool { _value }
}
