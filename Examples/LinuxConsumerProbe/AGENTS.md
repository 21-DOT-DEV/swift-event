# AGENTS.md (Examples/LinuxConsumerProbe)

This is a separate SPM package, NOT a target inside swift-event. It depends on the parent package via `.package(path: "../..")` and exists to verify external-consumer behavior of the `libevent` modulemap on platforms where regressions would otherwise only surface in downstream packages (notably swift-bitcoin under Swift C++ interop on Linux).

## Targets

- **`CxxConsumer`** — pure C++ target. Public header `include/probe.h` exposes only an `extern "C"` smoke-test entry point; the `<event2/...>` includes live in `probe.cpp`. Catches any regression that re-claims event2/*.h for the `libevent` module (e.g. reverting to `umbrella "."`).
- **`SwiftConsumer`** — plain Swift target with `import libevent`. Catches regressions that leave the libevent module empty (e.g. dropping the shim header from the modulemap), which would silently break access to libevent C symbols from Swift.
- **`CxxLibeventShim`** + **`SwiftCxxInteropConsumer`** — Swift target with `interoperabilityMode(.Cxx)` consuming a C++ shim. The shim's public header (`CxxLibeventShim/include/CxxLibeventShim.h`) is C-API-only; `<event2/...>` is `#include`d in `CxxLibeventShim.cpp`. Mirrors swift-bitcoin's actual path: Swift C++ interop forces `-fmodules` in C++ mode for the .cpp compile, so this is the path that broke swift-bitcoin in swift-event 0.2.0. This target is the regression's canary.

## Non-obvious patterns

- **SPM package identity matches the parent directory name.** `dependencies: [.package(path: "../..")]` resolves the parent's identity from the directory name (`swift-event`). If the parent is checked out under a different directory name, `Package.swift`'s `.product(name: "libevent", package: "swift-event")` references will fail to resolve. Keep the parent dir named `swift-event` when running the probe.
- **Public headers are C-API-only; libevent includes live in `.cpp` files.** This is the discipline swift-bitcoin's `bitcoind` target follows in production (libevent is `#include`d from `httpserver.cpp` / `torcontrol.cpp`, never from a public header), and the probe replicates it deliberately. Putting `#include <event2/...>` into a public header that gets compiled as a Clang module under Swift C++ interop triggers `module 'Darwin.POSIX.sys.socket' inside extern "C"` on macOS — a *different* bug from the libevent modulemap issue, which would mask the regression we actually want to catch. **When adding a target or moving includes around, keep `<event2/...>` strictly in `.cpp` files.** The libevent modulemap regression boundary is exercised inside each `.cpp` (compiled under C++ + `-fmodules` via swift-bitcoin-shaped Swift C++ interop downstream), which is exactly where the failure mode reproduces.
- **`SwiftCxxInteropConsumer` mirrors swift-bitcoin's bitcoind target.** swift-bitcoin's bitcoind is a C++ target compiled under Swift C++ interop that does `#include <event2/event.h>` from `httpserver.cpp` / `torcontrol.cpp`. The probe's `CxxLibeventShim` is the minimum reproducer of that path inside a package boundary; keep its `.cpp` doing the libevent include directly.

## Workflow integration

- `Examples/LinuxConsumerProbe/` is built by the `Dockerfile` at the repo root (after the swift-event tests run).
- Apple-platform CI (`.github/workflows/apple-builds.yml`) should build the probe on macOS too — Swift C++ interop differs between macOS and Linux Clang and both must stay green.
- Run locally with: `cd Examples/LinuxConsumerProbe && swift build`.
