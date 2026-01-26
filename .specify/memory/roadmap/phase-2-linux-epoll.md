# Phase 2: Linux Epoll Backend

**Status**: 🔜 Planned  
**Priority**: High  
**Estimated Effort**: Small (<1 hour)

---

## Overview

Add the epoll backend for optimized I/O on Linux. Currently swift-event falls back to poll/select on Linux, which works but is less efficient for high-connection-count scenarios. The epoll files already exist in `Vendor/libevent/` and just need to be added to the package.

**Performance Impact**: Epoll is O(1) for event notification vs O(n) for poll/select, making it significantly better for servers with many concurrent connections.

---

## Analysis: Vendor/libevent Files

### Linux-specific (needed)

| File | Purpose | Include? |
|------|---------|----------|
| `epoll.c` | Linux epoll backend | ✅ Yes |
| `epoll_sub.c` | Fallback for kernels without `epoll_create1` | ❌ No (modern kernels only) |
| `epolltable-internal.h` | Header for epoll | ✅ Already in Sources |

### Other platforms (not needed)

| File | Purpose | Platform |
|------|---------|----------|
| `devpoll.c` | /dev/poll backend | Solaris |
| `evport.c` | Event ports backend | Solaris |
| `evthread_win32.c` | Windows threading | Windows |
| `win32select.c` | Windows select | Windows |
| `buffer_iocp.c` | Windows IOCP | Windows |
| `bufferevent_async.c` | Windows async | Windows |
| `event_iocp.c` | Windows IOCP | Windows |

### Optional features (deferred)

| File | Purpose | Notes |
|------|---------|-------|
| `bufferevent_openssl.c` | OpenSSL integration | Would need OpenSSL dependency |
| `arc4random.c` | Fallback random | Using libbsd instead |

---

## Prerequisites

- ✅ Phase 1: Linux Basic Support (complete)

---

## Tasks

### 1. Add epoll.c to Sources/libevent/src/

Copy from `Vendor/libevent/`:
- [ ] `epoll.c` → `Sources/libevent/src/epoll.c`
- ✅ `epolltable-internal.h` already exists in `Sources/libevent/src/`

### 2. Update event-config.h for Linux epoll

Enable epoll conditionally on Linux in `Sources/libevent/include/event2/event-config.h`:

```c
/* Define if your system supports the epoll system calls */
#if defined(__linux__)
#define EVENT__HAVE_EPOLL 1
#else
/* #undef EVENT__HAVE_EPOLL */
#endif

/* Define to 1 if you have the `epoll_create1' function. */
#if defined(__linux__)
#define EVENT__HAVE_EPOLL_CREATE1 1
#else
/* #undef EVENT__HAVE_EPOLL_CREATE1 */
#endif

/* Define to 1 if you have the `epoll_ctl' function. */
#if defined(__linux__)
#define EVENT__HAVE_EPOLL_CTL 1
#else
/* #undef EVENT__HAVE_EPOLL_CTL */
#endif

/* Define to 1 if you have the <sys/epoll.h> header file. */
#if defined(__linux__)
#define EVENT__HAVE_SYS_EPOLL_H 1
#else
/* #undef EVENT__HAVE_SYS_EPOLL_H */
#endif
```

### 3. Test Docker build

```bash
cd /Users/csjones/Developer/swift-event
docker build --no-cache -t swift-event-linux .
```

### 4. Verify epoll is being used

Check build output for `Compiling epoll.c` to confirm the backend is included.

---

## Acceptance Criteria

- [ ] `epoll.c` compiles on Linux without errors
- [ ] Docker build passes with epoll enabled
- [ ] Build output shows `Compiling epoll.c`
- [ ] macOS build still works (epoll disabled, kqueue used)
- [ ] libevent uses epoll backend (verify in runtime if possible)

---

## Files to Modify

| File | Change |
|------|--------|
| `Sources/libevent/src/epoll.c` | Add (copy from Vendor) |
| `Sources/libevent/include/event2/event-config.h` | Enable epoll macros for Linux |

---

## Notes

- **Epoll is Linux-specific**; macOS uses kqueue (already working)
- The `epolltable-internal.h` header already exists in `Sources/libevent/src/`
- No Package.swift changes needed (SwiftPM auto-discovers .c files)
- `epoll_sub.c` is NOT needed - it's only for ancient kernels without `epoll_create1`
- Solaris/Windows backends are NOT needed for this project's scope
