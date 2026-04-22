# Backend and Platforms

@Metadata {
    @TitleHeading("Article")
}

The I/O multiplexer `Event` uses at runtime, the platform matrix it supports, and the backends deliberately excluded from the build.

## Overview

`Event` delegates event-readiness detection to libevent, which picks the most efficient I/O multiplexer available on the host at initialization time. The selection is exposed through ``EventLoop/backendMethod`` as a short string name. On supported platforms this selection is deterministic, and swift-event's test suite enforces the invariant.

### Runtime Backend Invariant

The `EventTests › EventLoop uses optimal backend` test in `Tests/EventTests/EventTests.swift` asserts:

- `backendMethod == "kqueue"` on macOS, iOS, tvOS, watchOS, and visionOS.
- `backendMethod == "epoll"` on Linux.

The invariant is a constitution Principle V guarantee: the swift-event build must not silently fall back to `poll(2)` / `select(2)` on a supported platform. If the test begins failing it means the vendored libevent extraction has regressed a backend file or the build is mis-detecting platform capabilities.

@Snippet(path: "swift-event/Snippets/EventLoopBackend")

### kqueue on Apple Platforms

Apple platforms expose the BSD [`kqueue(2)` / `kevent(2)`][kqueue] interface, which libevent's `kqueue.c` wraps. kqueue returns O(1) readiness notifications per ready fd (vs the O(n) scan of `poll(2)` / `select(2)`) and correctly handles edge cases like EOF and POLLHUP that the POSIX APIs conflate or lose.

[kqueue]: https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kqueue.2.html

### epoll on Linux

On Linux, libevent's `epoll.c` wraps the [`epoll_wait(2)`][epoll] family — the kernel's high-scalability readiness interface since 2.6. Like kqueue it delivers O(1) notifications per ready fd and supports edge-triggered mode. swift-event's epoll support is complete; the Docker CI build validates this on every push.

[epoll]: https://man7.org/linux/man-pages/man7/epoll.7.html

### Fallback: poll and select

If for some reason neither kqueue nor epoll is available, libevent will fall back to `poll(2)` and finally `select(2)`. swift-event does not deliberately disable these fallbacks — they stay compiled in so the library remains robust on exotic configurations — but the backend invariant test will fail and indicate a build regression rather than a legitimate fallback.

### Deliberately Excluded Backends

Several libevent backends are **not** part of swift-event's build or CI matrix. These exclusions are enforced by constitution Principle I:

- **Windows IOCP** (`win32select.c`, `buffer_iocp.c`): swift-event does not target Windows. The Windows-specific event and buffer implementations are not extracted from the vendored source and not compiled.
- **Solaris `devpoll` / `evport`** (`devpoll.c`, `evport.c`): Solaris and illumos are not supported platforms.
- **OpenSSL-backed bufferevents** (`bufferevent_openssl.c`): TLS wrapping is out of scope for the current release; see <doc:ProductionConsiderations> for the "not shipping today" list. When TLS support lands it will be via a dedicated Swift surface rather than a raw libevent-OpenSSL bufferevent.

The `AGENTS.md` files at the repository root and under `Vendor/` list the exclusions alongside the subtree-extraction patterns that enforce them.

### Platform Support Matrix

| Platform | Minimum | Backend |
| --- | --- | --- |
| macOS | 13 (Ventura) | kqueue |
| iOS / iPadOS | 16 | kqueue |
| tvOS | 16 | kqueue |
| watchOS | 9 | kqueue |
| visionOS | 1 | kqueue |
| Linux | Ubuntu 22.04+ (glibc) | epoll |

The Apple platform floor matches Swift 6.1's minimum deployment targets. The Linux floor reflects the swift-event CI matrix: anything older than Ubuntu 22.04 is not tested and not supported, though libevent itself is portable to much older glibc revisions.

### Next Steps

- <doc:ProductionConsiderations> — concurrency model, resource ownership, and the list of capabilities not yet shipping.
- <doc:ChoosingLibeventVsEvent> — when to reach past the Swift API into the raw `libevent` product.
- ``EventLoop`` — the public interface to the `event_base` wrapped here.
