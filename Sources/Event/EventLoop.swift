import libevent

/// A libevent-backed event loop owning an `event_base` for async I/O dispatch.
///
/// ## Overview
///
/// `EventLoop` wraps libevent's [`event_base`][event_base] — the per-loop data
/// structure that watches file descriptors for readiness using the platform's most
/// efficient I/O multiplexer (kqueue on Apple platforms, epoll on Linux, with POSIX
/// `poll(2)` as a fallback). ``Socket`` and ``ServerSocket`` use an `EventLoop` to
/// schedule read- and write-ready callbacks and drive them to completion.
///
/// [event_base]: https://libevent.org/doc/structevent__base.html
///
/// ### Shared vs. owned loops
///
/// Most callers use the ``shared`` singleton. Create a dedicated loop only when you
/// need isolation — for example, in tests that must not contend with application
/// traffic, or when you want distinct fd-watch sets per subsystem. The singleton is
/// fine for the common "one loop per process" pattern; it's not a locking construct
/// and does not synchronize concurrent use from multiple tasks.
///
/// ### Lifecycle
///
/// The typical flow is:
///
/// 1. Acquire a loop (``shared`` or ``init()``).
/// 2. Register I/O via ``Socket`` / ``ServerSocket`` methods — each method drives the
///    loop internally via ``runOnce()``.
/// 3. Call ``run()`` when you want a long-lived event-dispatch loop in a dedicated
///    task, or rely on per-operation ``runOnce()`` for one-shot use.
/// 4. ``stop()`` signals ``run()`` to exit at its next dispatch boundary.
///
/// ### Backend selection
///
/// The runtime backend is exposed via ``backendMethod``. swift-event asserts at test
/// time that this is `"kqueue"` on Apple platforms and `"epoll"` on Linux — see
/// <doc:BackendAndPlatforms> for the full backend story and the reasons
/// Windows IOCP, Solaris `devpoll`/`evport`, and OpenSSL bufferevents are excluded.
///
/// ### Concurrency
///
/// Marked `@unchecked Sendable` to permit handoff of ownership across task boundaries.
/// The underlying `event_base` is **not** thread-safe: swift-event does not invoke
/// `evthread_use_pthreads()`, so concurrent calls into a single `EventLoop` from
/// multiple tasks are **undefined behavior at the libevent level**. The invariant is
/// single-owner-per-scope — hand off, do not share. See <doc:ProductionConsiderations>
/// "Concurrency Model" for the full honest description.
public final class EventLoop: @unchecked Sendable {
    /// A process-wide shared event loop.
    ///
    /// Initialized lazily on first access and retained for the lifetime of the process.
    /// Use this when you have no reason to prefer an isolated loop. For tests that want
    /// freshness or subsystems that want independence, create a fresh `EventLoop()`.
    public static let shared = EventLoop()

    /// The underlying libevent `event_base` pointer.
    ///
    /// Kept `internal` — consumers never see or manipulate the raw C handle through
    /// the public `Event` API (constitution Principle IV). ``Socket`` and
    /// ``ServerSocket`` access it via `internal` visibility within the module.
    let base: OpaquePointer

    /// Whether the loop is currently running (tracked for informational purposes).
    private var isRunning = false

    /// Creates a new event loop with a default backend configuration.
    ///
    /// Calls libevent's `event_base_new()` internally. The backend (kqueue / epoll)
    /// is selected by libevent based on the host OS; swift-event does not override
    /// this selection.
    ///
    /// Traps (via `fatalError`) if `event_base_new()` returns `NULL`, which indicates
    /// catastrophic allocation failure. This behavior matches libevent's own C-side
    /// expectations and avoids propagating a `try?` through every consumer.
    public init() {
        guard let base = event_base_new() else {
            fatalError("Failed to create event_base")
        }
        self.base = base
    }

    /// Releases the underlying `event_base` via `event_base_free(3)`.
    ///
    /// Any events still registered with the loop at deallocation time are torn down
    /// by libevent. Callers should ensure `Socket` / `ServerSocket` instances referencing
    /// this loop have been released first to avoid use-after-free on their retained
    /// callback state.
    deinit {
        event_base_free(base)
    }

    /// Runs the event loop once, processing any currently-ready events.
    ///
    /// Corresponds to `event_base_loop(base, EVLOOP_ONCE)`. Used internally by each
    /// async method in ``Socket`` / ``ServerSocket`` so that per-operation awaiters
    /// drive the loop forward without requiring a caller-managed ``run()`` task.
    ///
    /// If no events are ready, libevent blocks until one becomes ready and then returns.
    public func runOnce() {
        event_base_loop(base, EVLOOP_ONCE)
    }

    /// Runs the event loop until no more events remain or ``stop()`` is called.
    ///
    /// Corresponds to `event_base_dispatch(3)`. This is the right choice for long-lived
    /// servers: spawn a task that calls ``run()``, register events from other tasks,
    /// and call ``stop()`` from a signal handler or shutdown hook.
    public func run() {
        isRunning = true
        event_base_dispatch(base)
        isRunning = false
    }

    /// Signals ``run()`` to exit at its next dispatch boundary.
    ///
    /// Corresponds to `event_base_loopbreak(3)`. Safe to call from any context that
    /// already owns the loop; not safe to call concurrently with ``run()`` from a
    /// different task without external synchronization (see class-level concurrency
    /// discussion).
    public func stop() {
        event_base_loopbreak(base)
    }

    /// The I/O multiplexer method libevent selected at initialization time.
    ///
    /// - Returns: `"kqueue"` on Apple platforms, `"epoll"` on Linux, `"poll"` or
    ///   `"select"` as fallbacks, or `"unknown"` if libevent reports no method.
    /// - SeeAlso: <doc:BackendAndPlatforms> for the invariant enforced by the
    ///   `EventLoop uses optimal backend` test.
    public var backendMethod: String {
        guard let method = event_base_get_method(base) else {
            return "unknown"
        }
        return String(cString: method)
    }
}
