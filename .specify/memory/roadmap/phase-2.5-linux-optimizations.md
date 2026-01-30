# Phase 2.5: Linux Optimizations

**Status**: ✅ Complete  
**Priority**: Low  
**Estimated Effort**: Small (<1 hour)

---

## Overview

Enable additional Linux-specific features in libevent for improved performance and correctness. These are optional enhancements that complement the epoll backend (Phase 2).

**Note**: These features are not required for basic functionality. Epoll is the high-impact change; these are optimizations on top of optimizations.

---

## Features to Enable

| Feature | Macro | Purpose |
|---------|-------|---------|
| `pipe2` | `EVENT__HAVE_PIPE2` | Atomic pipe creation (avoids race conditions) |
| `eventfd` | `EVENT__HAVE_EVENTFD` | Lightweight event signaling |
| `sys/eventfd.h` | `EVENT__HAVE_SYS_EVENTFD_H` | Header for eventfd |
| `accept4` | `EVENT__HAVE_ACCEPT4` | Atomic accept with flags |
| `splice` | `EVENT__HAVE_SPLICE` | Zero-copy data transfer |
| `timerfd_create` | `EVENT__HAVE_TIMERFD_CREATE` | Timer file descriptors |
| `sys/timerfd.h` | `EVENT__HAVE_SYS_TIMERFD_H` | Header for timerfd |
| `sys/sendfile.h` | `EVENT__HAVE_SYS_SENDFILE_H` | Zero-copy file transfer header |
| `gethostbyname_r` | `EVENT__HAVE_GETHOSTBYNAME_R_6_ARG` | Thread-safe DNS (6-arg) |

---

## Prerequisites

- ✅ Phase 2: Linux Epoll Backend (complete)

---

## Tasks

### 1. Update event-config.h

Enable each feature conditionally on Linux:

```c
/* Define to 1 if you have the `pipe2' function. */
#if defined(__linux__)
#define EVENT__HAVE_PIPE2 1
#else
/* #undef EVENT__HAVE_PIPE2 */
#endif
```

Repeat pattern for: `EVENTFD`, `SYS_EVENTFD_H`, `ACCEPT4`, `SPLICE`, `TIMERFD_CREATE`, `SYS_TIMERFD_H`, `SYS_SENDFILE_H`, `GETHOSTBYNAME_R`, `GETHOSTBYNAME_R_6_ARG`.

### 2. Test Docker build

```bash
docker build --no-cache -t swift-event-linux .
```

### 3. Verify macOS still builds

```bash
swift build && swift test
```

---

## Acceptance Criteria

- [x] All features compile on Linux without errors
- [x] Docker build passes
- [x] macOS build still works (features disabled)
- [x] No regressions in test suite

---

## Notes

- All features require Linux 2.6.27+ (2008) — safe for modern systems
- Each feature is independent; can be enabled incrementally if needed
- libevent falls back gracefully if features are unavailable at runtime
