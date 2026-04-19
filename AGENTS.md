# AGENTS.md (swift-event)

A Swift 6.1 wrapper around [libevent](https://github.com/libevent/libevent) providing event-driven async I/O and non-blocking TCP sockets. Supports macOS 13+, iOS 13+, tvOS 13+, watchOS 6+, visionOS 1+, and Linux (Ubuntu 22.04+). Uses Swift 6 strict concurrency (`swiftLanguageModes: [.v6]`). Two products: `libevent` (raw C bindings) and `Event` (idiomatic Swift API).

## Commands

- Build: `swift build`
- Test: `swift test`
- Linux build: `docker build .`

## Non-obvious patterns

- **Conditional dev deps**: `Package.swift` uses `Context.gitInformation?.currentTag` to exclude `swift-plugin-subtree` at tagged releases. Consumers resolving a tagged version get zero transitive dependencies; the package has no runtime dependencies.
- **Two-product split**: `libevent` is the raw C bindings product (consumable standalone); `Event` is the idiomatic Swift API (`EventLoop`, `Socket`, `ServerSocket`, `SocketAddress`, `SocketError`). Never leak raw C pointers through `Event`'s public API without an `unsafe*`-prefixed affordance.
- **Extraction flow**: libevent upstream is extracted via `subtree.yaml` (remote `libevent/libevent`, branch `release-2.1.12-stable`). `Vendor/libevent` → `Sources/libevent/`. Do NOT edit `Sources/libevent/**` directly; changes are overwritten on the next extraction. Manually maintained files are listed in `Vendor/AGENTS.md`.
- **Excluded sources**: `Sources/libevent/src/arc4random.c` is excluded from build via `Package.swift` (bundled BSD implementation using `getrandom()` on Linux replaces it).
- **Linux-only C define**: `_GNU_SOURCE` is defined on Linux only, to enable glibc features like `gethostbyname_r`.
- **Backend runtime verification**: `EventLoop().backendMethod` MUST report `kqueue` on Apple platforms and `epoll` on Linux. This is an invariant enforced by a test (`EventTests › EventLoop uses optimal backend`).
- **Forbidden backends** (per constitution Principle I): Windows IOCP, Solaris `devpoll`/`evport`, OpenSSL-backed bufferevents. Do not port or bundle these.

## Boundaries

- **Never**: edit files under `Vendor/**` or `Sources/libevent/**` directly; broaden GitHub Actions `permissions` without justification; add runtime dependencies; re-introduce excluded backends.
- **Ask first**: add new third-party dependencies (dev or runtime); modify `subtree.yaml` extraction patterns; add a new platform or I/O backend.
- See the [21-DOT-DEV contributing guidelines](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) for branching and commit guidelines. See the [21-DOT-DEV SECURITY.md](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md) for vulnerability reporting.

## Scoped guidance

Directory-specific `AGENTS.md` files provide additional context:

- `.github/AGENTS.md` — CI workflows and Actions security policy
- `Sources/AGENTS.md` — Swift targets, C bindings, extraction paths
- `Tests/AGENTS.md` — Swift Testing framework, backend-verification invariant
- `Vendor/AGENTS.md` — vendored libevent sources and subtree sync rules

## Maintenance

- Keep scoped `AGENTS.md` files limited to deltas; avoid duplicating root guidance.
- Update when build/test workflows, toolchain versions, platform support, or extraction patterns change.
