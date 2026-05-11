# Production Considerations

@Metadata {
    @TitleHeading("Article")
}

Pre-1.0 status, the concurrency model, resource-ownership rules, and the list of capabilities not yet shipping in `Event`.

## Overview

`Event` is a pre-1.0 MVP. It covers enough surface to drive non-blocking TCP clients and servers with async/await and to link `libevent` into other Swift packages, but several capabilities a full networking library would be expected to provide are explicitly not shipping today. This article collects the caveats you need to know before depending on the package in production.

### Pre-1.0 SemVer

swift-event follows [SemVer major version zero](https://semver.org/#spec-item-4): the `0.y.z` range reserves the right to break API in any release. Pin with `exact:` so a minor-version bump in this package never silently breaks your build:

```swift
.package(url: "https://github.com/21-DOT-DEV/swift-event.git", exact: "0.2.1"),
```

If you want patch-level updates without manually re-pinning, use `from:` against the current minor — but be aware that `from: "0.2.1"` will accept any 0.y release ≥ 0.2.1, including breaking changes per `0.y.z` semantics.

### Concurrency Model

`Event` is **not** a thread-safe library. This is the single largest caveat, and it is deliberate — the honest description is more useful than a papered-over invariant.

- ``EventLoop``, ``Socket``, and ``ServerSocket`` are marked `@unchecked Sendable` (rather than strictly `Sendable`) so you can hand them off across task boundaries while preserving the single-owner discipline below. The underlying libevent `event_base` is not configured for thread-safe use: swift-event does **not** call [`evthread_use_pthreads()`][evthread] at startup, so concurrent calls into a single loop (or into a single socket wired to that loop) from multiple tasks are undefined behavior at the libevent level. libevent itself surfaces this with the warning `event_base_loop: reentrant invocation. Only one event_base_loop can run on each event_base at once.` if you violate the invariant.
- **Single-owner-per-scope is the invariant.** Create a socket in one task, hand it to exactly one other task for I/O, close it when the task's work completes. Do not `Task.detached { socket.read() }` alongside `Task.detached { socket.write() }` on the same socket.
- For client/server pairs that need to coexist in the same process (tests, in-memory IPC, proxies), allocate **separate ``EventLoop`` instances** for the server side and the client side. Each loop has its own `event_base`; concurrent operations across loops are safe, concurrent operations within a single loop are not.
- `deinit` on `Socket` / `ServerSocket` closes the file descriptor unconditionally (for sockets with `ownsDescriptor == true`, which is the default). If another task is mid-I/O when `deinit` runs, that I/O will fail with `EBADF`.
- ``EventLoop/shared`` is fine for simple single-loop applications. Tests that need isolation should allocate a fresh `EventLoop()` so that test shutdown tears the loop down cleanly.

[evthread]: https://libevent.org/doc/evthread_8h.html

An open question is whether a future release should introduce explicit actor isolation — wrapping `EventLoop` as an actor and routing `Socket` / `ServerSocket` I/O through its mailbox. That would make strict-`Sendable` conformance honest instead of unchecked and would remove the single-owner responsibility from callers (the actor would serialize access to the loop). Such a refactor is deliberately out of scope for the current release; file an issue if you need it.

### Resource Ownership (constitution Principle II)

`Event` tracks file-descriptor ownership explicitly:

- ``Socket`` takes an `ownsDescriptor` flag at init time (`true` by default). When `true`, `deinit` closes the fd via `close(2)`. When `false`, the socket assumes another party retains responsibility — a mode reserved for internal fd-adoption today.
- ``ServerSocket`` always owns its descriptor; there is no escape hatch.
- On error paths in ``Socket/listen(on:backlog:loop:)``, the allocated fd is closed before the error is thrown, so partially-constructed sockets never leak descriptors.

The current shape assumes RAII: the socket object's lifetime bounds the fd's lifetime. Explicit ``Socket/close()`` and ``ServerSocket/close()`` methods exist but are idempotent — calling them after `deinit` has already run is safe, just no-op-at-`EBADF`.

### Signal Handling

swift-event does **not** install a `SIGPIPE` handler. On Apple platforms, sockets created by `Event` inherit the default disposition (process-wide `SIGPIPE` terminates on write-after-peer-closed). On Linux, a dedicated `SIGPIPE` handler can intercept; otherwise the default action is process termination.

Two workarounds for production code:

1. Install a `SIG_IGN` disposition for `SIGPIPE` at application startup (POSIX-portable).
2. On Linux, use `MSG_NOSIGNAL` on every `send(2)` — which ``Socket/write(_:timeout:)`` does not currently do.

A future release may set `SO_NOSIGPIPE` (macOS) or thread through `MSG_NOSIGNAL` (Linux) automatically; the current behavior inherits the platform defaults.

### Backpressure and Partial Writes

``Socket/write(_:timeout:)`` issues a single `write(2)` syscall covering the full buffer. It does **not** loop on partial writes — if the kernel accepts fewer bytes than requested, the remainder is silently dropped (the callback reports success). In practice, writes of a few KB on a connected TCP socket complete in one syscall on all supported platforms, but applications sending large buffers should chunk explicitly until proper backpressure handling lands.

The fix is straightforward — loop on `write(2)` inside the ready callback, re-register the `EV_WRITE` event if the kernel returns `EAGAIN` — and is planned for a post-0.1.0 release.

### Capabilities Not Shipping Today

The following capabilities are out of scope for this release. Each has been considered and deferred rather than overlooked:

- **TLS**: Plain TCP only. No wrapping with `bufferevent_openssl` or equivalent. If you need TLS today, front the socket with a TLS library or use SwiftNIO with `swift-nio-ssl`.
- **UDP**: TCP-only `socket(AF_INET, SOCK_STREAM, 0)`. UDP is a natural next step but is not wired up.
- **One signal per event-loop**: libevent permits at most one `event_base` to claim a given signal at a time. ``EventLoop/signalStream(_:)`` is *now* shipped, but registering the same signum (e.g. `SIGTERM`) on two ``EventLoop`` instances in the same process is undefined. Standard pattern: register process-global signals on ``EventLoop/shared``. Timer scheduling — ``EventLoop/schedule(after:_:)`` and ``EventLoop/sleep(for:)`` — has no such constraint.
- **Cancellation of the `connections` stream**: Cancelling the task that iterates ``ServerSocket/connections`` terminates the `for try await` loop in your code but does not unregister the outstanding libevent accept callback. Call ``ServerSocket/close()`` to fully tear the listener down.
- **IPv6 server binding**: ``Socket/listen(on:backlog:loop:)`` allocates an `AF_INET` kernel socket today; IPv6 server support requires a small refactor to detect the `ss_family` of the supplied address. IPv6 client connections work; IPv6 parsing works.
- **Read buffer sizing**: ``Socket/read(maxBytes:timeout:)`` takes a `maxBytes` parameter but currently ignores it — the internal buffer is a fixed 4096 bytes. Preserved in the API for future honor.

### Vulnerability Reporting

Security vulnerabilities in the Swift API or in the vendored libevent extraction should be reported via the private channel described in [the 21-DOT-DEV SECURITY.md](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md). Do not open public issues for vulnerabilities.

## See Also

- <doc:GettingStarted>
- <doc:BackendAndPlatforms>
- <doc:ChoosingLibeventVsEvent>
