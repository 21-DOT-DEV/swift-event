# AGENTS.md (Sources)

This directory contains the library implementation (Swift target and C bindings).

## What lives here

- **Swift target**: `Event` — idiomatic Swift API (`EventLoop`, `Socket`, `ServerSocket`, `SocketAddress`, `SocketError`).
- **C binding target**: `libevent` — raw bindings extracted from vendored upstream.

## Extractions

`Sources/libevent/` is generated via extraction from `Vendor/libevent/`. Before making changes here, check `subtree.yaml` to confirm the extraction mapping and avoid unintended divergence that will be overwritten on the next extraction.

- `Sources/libevent/include/`
- `Sources/libevent/src/`

See `Vendor/AGENTS.md` for the list of manually maintained files under `Sources/libevent/` that are NOT produced by extraction.

## Non-obvious patterns

- `Sources/libevent/src/arc4random.c` is excluded from the build via `exclude: ["src/arc4random.c"]` in `Package.swift`. A bundled BSD implementation using `getrandom()` on Linux replaces it.
- `_GNU_SOURCE` is defined on Linux only, to enable glibc features like `gethostbyname_r`.
- The `Event` target depends on `libevent`; never re-export raw C types through `Event`'s public API without an `unsafe*`-prefixed affordance (constitution Principle IV).
