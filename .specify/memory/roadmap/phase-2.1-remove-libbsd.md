# Phase 2.1: Remove libbsd Dependency

**Status**: ✅ Complete  
**Priority**: Medium  
**Estimated Effort**: Small (<1 hour)

---

## Overview

Remove the libbsd system dependency on Linux by using libevent's bundled implementations for BSD functions. This eliminates the need for `apt-get install libbsd-dev` and simplifies downstream package usage.

**Benefits**:
- Zero external dependencies on Linux
- Simpler Dockerfile (no `libbsd-dev`)
- Downstream packages don't need system library installed
- Uses modern Linux syscalls (`getrandom()`) instead of compatibility layer

---

## Prerequisites

- ✅ Phase 2: Linux Epoll Backend (complete)

---

## Technical Approach

### Problem
libbsd provides BSD functions (`arc4random`, `strlcpy`) on Linux. However:
- Requires system package installation
- Adds external dependency
- libevent already bundles these implementations

### Solution
Use libevent's bundled implementations with preprocessor guards:

1. **arc4random**: Bundled `arc4random.c` is `#include`d into `evutil_rand.c` when `EVENT__HAVE_ARC4RANDOM` is NOT defined. Uses `getrandom()` syscall on Linux.

2. **strlcpy**: Bundled `strlcpy.c` compiles its implementation when `EVENT__HAVE_STRLCPY` is NOT defined.

### Key Insight
`arc4random.c` must be **excluded from direct compilation** (via Package.swift `exclude:`) because it's designed to be textually included, not compiled as a separate unit.

---

## Changes Made

### event-config.h (Linux-conditional macros)

| Macro | macOS/iOS | Linux |
|-------|-----------|-------|
| `EVENT__HAVE_ARC4RANDOM` | defined | undef |
| `EVENT__HAVE_ARC4RANDOM_BUF` | defined | undef |
| `EVENT__HAVE_STRLCPY` | defined | undef |
| `EVENT__HAVE_SYSCTL` | defined | undef |
| `EVENT__HAVE_SYS_SYSCTL_H` | defined | undef |
| `EVENT__HAVE_GETRANDOM` | undef | defined |

### Package.swift

```swift
.target(
    name: "libevent",
    exclude: ["src/arc4random.c"]  // Included textually, not compiled directly
)
// Removed: .linkedLibrary("bsd", .when(platforms: [.linux]))
```

### Dockerfile

```dockerfile
# Removed: libbsd-dev from apt-get install
```

### subtree.yaml

```yaml
# Removed 'arc4random*' from exclude list
```

---

## Acceptance Criteria

- [x] macOS build passes (uses system arc4random)
- [x] macOS tests pass
- [x] Docker Linux build passes (uses bundled arc4random.c)
- [x] Linux tests pass
- [x] No libbsd-dev in Dockerfile
- [x] No .linkedLibrary("bsd") in Package.swift

---

## Files Modified

| File | Change |
|------|--------|
| `Sources/libevent/src/arc4random.c` | Added (extracted from Vendor) |
| `Sources/libevent/include/event2/event-config.h` | Conditional macros for Linux |
| `Package.swift` | Added exclude, removed linkedLibrary |
| `Dockerfile` | Removed libbsd-dev |
| `subtree.yaml` | Removed arc4random* from exclude |

---

## Notes

- `getrandom()` syscall available since Linux 3.17 (2014) — safe for all modern systems
- Bundled implementations are battle-tested (from OpenBSD/libevent)
- `arc4random.c` is included via `#include "./arc4random.c"` in `evutil_rand.c`, not compiled separately
- This pattern avoids the need for two separate SwiftPM targets
