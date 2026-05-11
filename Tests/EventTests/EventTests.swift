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
        // Default SIGUSR1 disposition is process termination; flip to SIG_IGN
        // before signalStream installs libevent's handler, so a race during
        // setup (signal arriving before the libevent handler is in place)
        // can't kill the test runner.
        signal(SIGUSR1, SIG_IGN)
        defer { signal(SIGUSR1, SIG_DFL) }

        let stream = loop.signalStream(SIGUSR1)

        // Drive the loop on a detached task so the test thread is free to
        // raise the signal and await the iterator. event_base_loop blocks in
        // epoll_wait/kevent until something fires; without a separate thread
        // doing that work, no Task that needs to fire the signal could ever
        // get CPU under cooperative concurrency on Linux. (Previous attempt
        // interleaved runOnce() and iterator.next() on the same task and
        // deadlocked on Linux for this reason.)
        //
        // We deliberately do NOT synchronize teardown — event_base_loopbreak
        // only wakes a parked event_base_loop when evthread_use_pthreads has
        // been called, which this package omits by design. The driver's
        // strong reference to `loop` keeps the event_base alive past test
        // return; the OS reclaims resources at process exit. Acceptable for
        // a one-off test asserting signal delivery; not a pattern for
        // production code.
        Task.detached { loop.run() }

        // Yield + sleep so the driver task is scheduled and libevent's
        // handler is installed before we raise. 50 ms is well above what's
        // needed in practice but keeps the test stable on slow CI runners.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        // Use kill(getpid(), …) rather than raise(): raise() is
        // thread-directed (equivalent to pthread_kill(pthread_self())) and
        // delivers only to the calling thread. On Linux that's the test
        // thread, which may have SIGUSR1 in a state that doesn't dispatch
        // — the libevent driver thread never sees it and the test hangs.
        // kill(getpid(), …) is process-directed and any thread without the
        // signal blocked can pick it up.
        kill(getpid(), SIGUSR1)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == SIGUSR1)
    }
}

/// Simple `Sendable` flag used by tests that need to assert a callback fired.
private final class FiredFlag: @unchecked Sendable {
    private var _value = false
    func set() { _value = true }
    var value: Bool { _value }
}
