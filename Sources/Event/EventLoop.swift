import libevent

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

    // MARK: - Timers

    /// Schedules `work` to run once after `duration` elapses, then returns immediately.
    ///
    /// Wraps libevent's `event_base_once(3)` with `EV_TIMEOUT`. The closure runs on
    /// whichever task next drives the loop (via ``run()`` or any ``Socket`` /
    /// ``ServerSocket`` operation that calls ``runOnce()`` internally). If nothing
    /// drives the loop before the deadline, the callback is queued but does not fire
    /// until something does.
    ///
    /// - Parameters:
    ///   - duration: How long to wait. Negative or zero durations fire on the next
    ///     loop iteration.
    ///   - work: Closure to invoke. Runs in the loop's callback context.
    /// - SeeAlso: ``sleep(for:)`` for an `async` shape that suspends the calling task.
    public func schedule(after duration: Duration, _ work: @Sendable @escaping () -> Void) {
        let box = TimerBox(work: work)
        let opaque = Unmanaged.passRetained(box).toOpaque()
        var tv = EventLoop.timeval(for: duration)

        let result = event_base_once(base, -1, Int16(libevent.EV_TIMEOUT), { _, _, ctx in
            let box = Unmanaged<TimerBox>.fromOpaque(ctx!).takeRetainedValue()
            box.work()
        }, opaque, &tv)

        if result != 0 {
            Unmanaged<TimerBox>.fromOpaque(opaque).release()
        }
    }

    /// Suspends the current task for `duration`, driven by this event loop.
    ///
    /// Unlike `Task.sleep(for:)`, which goes through the global Swift concurrency
    /// clock, this routes the wait through libevent's timer wheel — useful when you
    /// want sleeps to share scheduling with the same multiplexer that's driving your
    /// I/O. Internally registers a one-shot timer via ``schedule(after:_:)`` and
    /// drives the loop until it fires.
    ///
    /// - Parameter duration: How long to suspend. Negative or zero durations return
    ///   on the next loop iteration.
    public func sleep(for duration: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            schedule(after: duration) {
                continuation.resume()
            }
            runOnce()
        }
    }

    // MARK: - Signal Events

    /// Yields the signal number each time one of `signals` fires on this loop.
    ///
    /// Backed by libevent's `evsignal_*` machinery. libevent installs its own
    /// signal-safe handler internally (the C-side handler only notes the
    /// signal and lets the loop dispatch the callback in normal context), so
    /// the closure body runs in regular Swift Concurrency context — none of
    /// the async-signal-safety restrictions of raw `signal(2)` handlers
    /// apply. This mirrors the safety story of Apple's
    /// [`DispatchSource.makeSignalSource(_:queue:)`][ds], which also defers
    /// callbacks off the signal handler.
    ///
    /// [ds]: https://developer.apple.com/documentation/dispatch/dispatchsource/1781941-makesignalsource
    ///
    /// The stream is unbuffered by default (matches `AsyncStream`'s no-arg
    /// constructor): values are delivered to the iterator if it is currently
    /// awaiting, or buffered until it does. Stream termination —
    /// `for await … break`, the iterating task being cancelled, or the
    /// returned stream being dropped — calls `event_del(3)` on each
    /// registered signal event, restoring the prior signal disposition.
    ///
    /// > Important: libevent permits at most one `event_base` to claim a given
    /// > signal at a time. If two ``EventLoop`` instances in the same process
    /// > call `signalStream` for the same signal number, the second
    /// > registration's behavior is undefined. In practice you should
    /// > register process-global signals on a single event loop —
    /// > ``shared`` is the typical choice.
    ///
    /// > Tip: When unit-testing code that consumes a signal stream, fire
    /// > signals with `kill(getpid(), SIGUSR1)` rather than `raise(SIGUSR1)`.
    /// > `raise()` is thread-directed (equivalent to
    /// > `pthread_kill(pthread_self(), …)`) and only delivers to the calling
    /// > thread; if the loop is being driven on a different thread — the
    /// > typical test pattern — libevent's handler never sees the signal and
    /// > the test hangs. `kill(getpid(), …)` is process-directed so any
    /// > unblocked thread, including the loop's driver, can receive it.
    /// > Production users whose signals come from external processes
    /// > (`kill -TERM <pid>`, `Ctrl-C` from a shell) never hit this — those
    /// > are already process-directed.
    ///
    /// Composes cleanly with
    /// [`swift-service-lifecycle`](https://github.com/swift-server/swift-service-lifecycle):
    /// a service's `run()` body can iterate this stream and call
    /// `gracefulShutdown()` on the first value, breaking out of the loop to
    /// trigger automatic teardown.
    ///
    /// - Parameter signals: One or more signal numbers to observe (e.g.
    ///   `SIGTERM`, `SIGINT`, `SIGHUP`, `SIGUSR1`).
    /// - Returns: An `AsyncStream<Int32>` yielding the signal number each time
    ///   any of the requested signals fires.
    public func signalStream(_ signals: Int32...) -> AsyncStream<Int32> {
        AsyncStream { continuation in
            let registration = SignalRegistration(loop: self)
            for signum in signals {
                let box = SignalBox(signum: signum, continuation: continuation)
                let opaque = Unmanaged.passRetained(box).toOpaque()
                let ev = event_new(base, signum, Int16(EV_SIGNAL | EV_PERSIST), { _, _, ctx in
                    let box = Unmanaged<SignalBox>.fromOpaque(ctx!).takeUnretainedValue()
                    box.continuation.yield(box.signum)
                }, opaque)
                if let ev {
                    event_add(ev, nil)
                    registration.events.append((event: ev, retained: opaque))
                } else {
                    Unmanaged<SignalBox>.fromOpaque(opaque).release()
                }
            }
            continuation.onTermination = { _ in
                // Runs on stream cancellation / drop — tear down each event.
                registration.tearDown()
            }
        }
    }

    /// Converts a `Duration` to a POSIX `timeval` suitable for libevent.
    ///
    /// Truncates sub-microsecond precision (timeval has no nanosecond field).
    /// Negative durations clamp to zero so libevent fires immediately rather than
    /// rejecting the timeval.
    static func timeval(for duration: Duration) -> timeval {
        let comps = duration.components
        let seconds = max(comps.seconds, 0)
        let microseconds = comps.seconds < 0 ? 0 : comps.attoseconds / 1_000_000_000_000
        #if canImport(Darwin)
        return Darwin.timeval(tv_sec: Int(seconds), tv_usec: Int32(microseconds))
        #else
        return Glibc.timeval(tv_sec: Int(seconds), tv_usec: Int(microseconds))
        #endif
    }
}

/// Retained box for a fire-and-forget timer closure.
///
/// `@unchecked Sendable` because the stored closure is consumed exactly once by a
/// single libevent callback invocation; Unmanaged retain/release bookends its lifetime.
private final class TimerBox: @unchecked Sendable {
    let work: @Sendable () -> Void

    init(work: @Sendable @escaping () -> Void) {
        self.work = work
    }
}

/// Retained context for a persistent libevent signal callback.
///
/// `@unchecked Sendable` because mutation is bounded to a single callback
/// invocation per fire and the stored continuation is itself `Sendable`.
private final class SignalBox: @unchecked Sendable {
    let signum: Int32
    let continuation: AsyncStream<Int32>.Continuation

    init(signum: Int32, continuation: AsyncStream<Int32>.Continuation) {
        self.signum = signum
        self.continuation = continuation
    }
}

/// Owns the libevent signal events registered for a single
/// ``EventLoop/signalStream(_:)`` invocation. Holds a strong reference to
/// the loop so the underlying `event_base` outlives the stream, and tears
/// down every registered event on stream termination.
///
/// `@unchecked Sendable` because all mutation happens either at construction
/// (single owner) or inside `tearDown()` (single call from the stream
/// continuation's `onTermination` hook).
private final class SignalRegistration: @unchecked Sendable {
    let loop: EventLoop
    var events: [(event: UnsafeMutablePointer<event>, retained: UnsafeMutableRawPointer)] = []
    private var torndown = false

    init(loop: EventLoop) {
        self.loop = loop
    }

    func tearDown() {
        guard !torndown else { return }
        torndown = true
        for entry in events {
            event_del(entry.event)
            event_free(entry.event)
            Unmanaged<SignalBox>.fromOpaque(entry.retained).release()
        }
        events.removeAll()
    }

    deinit {
        tearDown()
    }
}
