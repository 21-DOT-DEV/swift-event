# Phase 1: Linux Basic Support

**Status**: ✅ Complete  
**Completed**: 2025-01-26

---

## Overview

Enable swift-event to build and test on Linux using poll/select backends. Disable macOS-specific features and add necessary dependencies.

---

## Completed Tasks

### 1. Disable macOS-specific features in event-config.h

- [x] `EVENT__HAVE_KQUEUE` - disabled on Linux
- [x] `EVENT__HAVE_WORKING_KQUEUE` - disabled on Linux
- [x] `EVENT__HAVE_SYS_EVENT_H` - disabled on Linux
- [x] `EVENT__HAVE_MACH_ABSOLUTE_TIME` - disabled on Linux
- [x] `EVENT__HAVE_MACH_MACH_TIME_H` - disabled on Linux
- [x] `EVENT__HAVE_MACH_MACH_H` - disabled on Linux
- [x] `EVENT__HAVE_STRUCT_SOCKADDR_IN6_SIN6_LEN` - disabled on Linux
- [x] `EVENT__HAVE_ISSETUGID` - disabled on Linux (not in libbsd)

### 2. Add Darwin/Glibc conditional compilation in Swift code

- [x] `Sources/Event/Socket.swift` - conditional imports and function calls
- [x] `Sources/Event/ServerSocket.swift` - conditional imports and function calls
- [x] Fix `SOCK_STREAM` type difference on Linux

### 3. Add Dockerfile for Linux testing

- [x] Create `Dockerfile` using `swift:6.1-jammy`
- [x] Create `.dockerignore`
- [x] Install `libbsd-dev` for BSD functions (arc4random, strlcpy)

### 4. Add linker settings in Package.swift

- [x] Link `libbsd` on Linux platform

---

## Files Modified

| File | Change |
|------|--------|
| `Sources/libevent/include/event2/event-config.h` | Conditional macros for Linux |
| `Sources/Event/Socket.swift` | Darwin/Glibc conditional compilation |
| `Sources/Event/ServerSocket.swift` | Darwin/Glibc conditional compilation |
| `Package.swift` | Add libbsd linker setting for Linux |
| `Dockerfile` | New file for Linux testing |
| `.dockerignore` | New file |

---

## Verification

```bash
docker build -t swift-event-linux .
# Build and tests pass
```
