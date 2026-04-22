# Choosing Between Event and libevent

@Metadata {
    @TitleHeading("Explanation")
}

This package ships two library products — which one should you link? This article covers the decision boundary, the canonical consumer example (`swift-tor`), and the stability guarantees that differ between the idiomatic Swift API and the raw C bindings.

## Overview

This article walks the decision boundary product-by-product, covers the `swift-tor` consumption pattern, explains the differing stability guarantees, and closes with how the two products compose inside a single binary.

### The Two Products

`Package.swift` defines two public library products:

- **`Event`** — the idiomatic Swift API (``EventLoop``, ``Socket``, ``ServerSocket``, ``SocketAddress``, ``SocketError``). Async/await surface, `@unchecked Sendable` handoff invariant (see <doc:ProductionConsiderations>), no raw C pointers in the public signatures.
- **`libevent`** — raw C bindings to libevent 2.1.12 (event-dispatch machinery, bufferevents, rate-limited groups, DNS resolution at the C level, timer and signal events at the C level).

Both products share a single statically linked copy of upstream libevent. A binary that imports `Event` and `libevent` in different targets pulls in one runtime, not two.

### When to Import `Event`

Default choice for Swift callers. Import `Event` when:

- You want an `async`/`await` API for TCP clients and servers without reaching for raw callbacks.
- You want to compile against Swift 6.1 strict concurrency and rely on the documented single-owner handoff invariant rather than writing your own.
- You're writing application code rather than a dependency that re-exports a C runtime.
- Your protocol is plain TCP (TLS and UDP are not yet shipping — see <doc:ProductionConsiderations>).

The `Event` surface is deliberately narrow. It does not wrap libevent's timer events, signal events, bufferevents, or DNS resolver today. Reach for `libevent` directly when you need those; the next section covers when and why.

### When to Import `libevent` Directly

Reach for the raw C bindings when:

- You need a libevent primitive the `Event` Swift API hasn't wrapped yet: `evtimer_*` (timer events), `evsignal_*` (signal events), `bufferevent_*` (buffered I/O with watermarks and rate limits), `evdns_*` (async DNS resolution), `evhttp_*` (the embedded HTTP server).
- You're bridging existing C or C++ code that already uses libevent's API — exposing the same symbols to Swift via `libevent` avoids duplicating the runtime.
- You're building another Swift package that needs libevent to back its own C sources.

**Canonical example**: [`swift-tor`](https://github.com/21-DOT-DEV/swift-tor) links `libevent` from this package alongside `libcrypto` and `libssl` from [`swift-openssl`](https://github.com/21-DOT-DEV/swift-openssl). Its `libtor` target vendors the Tor source tree — C code that calls `event_base_*`, `evbuffer_*`, `evdns_*`, `SSL_*`, and `EVP_*` routines — and resolves those symbols through these products rather than system libraries, ensuring Tor uses the same statically-linked, vendor-controlled libevent and OpenSSL that the rest of the dependency graph sees. Per [`swift-tor`'s AGENTS.md](https://github.com/21-DOT-DEV/swift-tor/blob/main/AGENTS.md), the `libtor` target declares all three products as direct dependencies:

```swift
// From swift-tor's Package.swift
dependencies: [
    .package(url: "https://github.com/21-DOT-DEV/swift-openssl.git", branch: "main"),
    .package(url: "https://github.com/21-DOT-DEV/swift-event.git", branch: "main"),
],
targets: [
    .target(
        name: "libtor",
        dependencies: [
            .product(name: "libcrypto", package: "swift-openssl"),
            .product(name: "libssl", package: "swift-openssl"),
            .product(name: "libevent", package: "swift-event"),
        ],
        // ...
    ),
],
```

This is the intended consumption pattern for packages that need libevent as a runtime substrate rather than as a Swift API.

### Stability Guarantees

The package-level "pre-1.0" status applies differently to each product:

- **`Event` (Swift API)**: Pre-1.0 ([SemVer `0.y.z`](https://semver.org/#spec-item-4)). The public surface — type names, function signatures, the set of ``SocketError`` cases, the concurrency posture — may change across `0.y.z` releases. No version tag has been cut yet; consumers pin to `branch: "main"`. Pinning `exact:` will replace branch pins as soon as 0.1.0 ships.
- **`libevent` (C bindings)**: Stable *relative to upstream libevent 2.1.12's own C ABI*. If upstream libevent 2.2 renames or removes a function, this package will pass that change through. If upstream keeps a function stable, so does this package. The version pin is in `subtree.yaml` (currently tracking the `release-2.1.12-stable` branch); updating it follows the extraction recipe in [`Vendor/AGENTS.md`](https://github.com/21-DOT-DEV/swift-event/blob/main/Vendor/AGENTS.md).

Consumers of `libevent` (like `swift-tor`) inherit the libevent 2.1.12 stability contract directly. Consumers of `Event` (like an application using the Swift API) inherit this package's own pre-1.0 policy on top.

This dichotomy mirrors the one in [`swift-openssl`'s](https://github.com/21-DOT-DEV/swift-openssl) product model — `OpenSSL` is pre-1.0 Swift-surface-versioned, while `libcrypto` / `libssl` track upstream OpenSSL's C ABI.

### Mixing Products

A single target can import both `Event` and `libevent` without runtime duplication. Because both resolve to the same statically-linked libevent build, there is exactly one copy of libevent's global state in the final binary.

Transitive consumers behave the same way. An application that depends on `swift-tor` (which pulls in `libevent` from this package) and separately imports `Event` to open a TCP client connection will see one libevent runtime, not two. This keeps log output, DNS caches, and any future shared-state behavior coherent across the dependency graph.

### Next Steps

- <doc:GettingStarted> — client and server walkthroughs using the `Event` Swift API.
- <doc:BackendAndPlatforms> — the kqueue / epoll story, platform matrix, and excluded backends.
- <doc:ProductionConsiderations> — concurrency model, resource-ownership rules, pre-1.0 caveats.
