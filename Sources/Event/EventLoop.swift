import libevent

/// A libevent-based event loop for async I/O operations.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class EventLoop: @unchecked Sendable {
    /// The shared event loop instance.
    public static let shared = EventLoop()
    
    /// The underlying libevent event_base.
    let base: OpaquePointer
    
    /// Whether the loop is currently running.
    private var isRunning = false
    
    /// Creates a new event loop.
    public init() {
        guard let base = event_base_new() else {
            fatalError("Failed to create event_base")
        }
        self.base = base
    }
    
    deinit {
        event_base_free(base)
    }
    
    /// Runs the event loop once, processing ready events.
    public func runOnce() {
        event_base_loop(base, EVLOOP_ONCE)
    }
    
    /// Runs the event loop until no more events are pending.
    public func run() {
        isRunning = true
        event_base_dispatch(base)
        isRunning = false
    }
    
    /// Stops the event loop.
    public func stop() {
        event_base_loopbreak(base)
    }
    
    /// The I/O backend method in use (e.g., "epoll" on Linux, "kqueue" on macOS).
    public var backendMethod: String {
        guard let method = event_base_get_method(base) else {
            return "unknown"
        }
        return String(cString: method)
    }
}
