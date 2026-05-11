# Embedding a C Library in Swift Package Manager

@Metadata {
    @TitleHeading("Article")
}

How to make a C library consumable from Swift Package Manager — using libevent and ``Event`` as the worked example, with the module-map and product-re-export patterns extracted for your own ports.

## Overview

If you've tried to bring a non-trivial C library — libevent, libssh, libuv, OpenSSL, libtor — into a Swift Package Manager target, you've hit the same questions every time:

1. Where do the headers go?
2. How do you write a `module.modulemap` so Swift sees the C symbols?
3. How do you let *other* SwiftPM packages link against the C library through yours, without duplicating the build?
4. What about C++ consumers that can't parse the headers as a Clang module?

This article documents the pattern this package uses for libevent, generalised for your own ports. The pattern is also the proof for [`swift-tor`](https://github.com/21-DOT-DEV/swift-tor), which depends on `libevent` (from this package) alongside `libcrypto` / `libssl` (from [`swift-openssl`](https://github.com/21-DOT-DEV/swift-openssl)) to build a Swift-native Tor daemon — without bundling its own libevent build.

### The shape of the problem

A C library you want to wrap typically has this layout in its upstream source tree:

```
libfoo/
├── include/
│   ├── foo.h
│   └── foo/
│       ├── core.h
│       ├── ext.h
│       └── ...
├── src/
│   ├── core.c
│   ├── ext.c
│   └── ...
└── configure.ac          // or CMakeLists.txt — autotools / cmake build
```

SwiftPM doesn't run `configure` or `cmake`. To consume the library from Swift, you need to:

- Place the headers somewhere SwiftPM expects (`Sources/<target>/include/`).
- Place the source files somewhere SwiftPM compiles (`Sources/<target>/`).
- Write a `Package.swift` `target` declaration that tells SwiftPM how to compile the sources and what flags / defines to pass.
- (For non-trivial libraries) write a manual `module.modulemap` that tells Clang which headers form the public module surface.

### Step 1 — Vendoring the upstream sources

The cleanest pattern is to copy or `git subtree` the upstream `include/` and `src/` directories into your SwiftPM target:

```
swift-libfoo/
├── Package.swift
└── Sources/
    └── libfoo/                  // SwiftPM target name
        ├── include/
        │   ├── foo.h
        │   ├── foo/
        │   │   ├── core.h
        │   │   └── ext.h
        │   └── module.modulemap   // ← we'll write this
        └── src/
            ├── core.c
            └── ext.c
```

This package uses a `git subtree` extraction (driven by `subtree.yaml`) so that running the extraction script pulls fresh upstream sources from the libevent repo into `Sources/libevent/`. See `subtree.yaml` and the `Vendor/AGENTS.md` notes for the exact configuration.

For a one-off vendor, plain `cp -R` works.

> Important: **Do not edit the vendored files in place.** Any patches you need go in a separate "manually maintained" file list (this package keeps the list in `Vendor/AGENTS.md`) so re-extraction doesn't silently overwrite your changes. Forgetting this rule is the single most common way to lose patches across upstream-sync cycles.

### Step 2 — `Package.swift` for the C target

```swift
.target(
    name: "libfoo",
    exclude: [
        // Sources you don't want compiled (e.g., platform-specific
        // implementations that conflict with the host's libc):
        "src/arc4random.c",
    ],
    cSettings: [
        // Pass any defines the upstream build system would have set:
        .define("_GNU_SOURCE", .when(platforms: [.linux])),
        .define("HAVE_CONFIG_H"),
    ]
)
```

Two non-obvious points:

- **`exclude:` lets you skip files** that conflict with the host platform — for example, libevent ships its own `arc4random.c` that collides with glibc 2.36+'s `arc4random_buf` definition. This package excludes that file and lets the bundled getrandom() fallback handle randomness on Linux.
- **`cSettings` `.define` declarations** stand in for what `./configure` would have written into `config.h`. For libevent, this means `event-config.h` is shipped as a hand-maintained file (see `Sources/libevent/include/event2/event-config.h`) rather than being generated at build time. The trade-off: you lose autoconf's per-host detection, and you have to update `event-config.h` when the host environment changes (e.g., the recent glibc 2.36 arc4random handling).

### Step 3 — The module map

**Use `umbrella "."` (directory-wide) for non-trivial C libraries — it is the safer default than `umbrella header "foo.h"`.** When SwiftPM sees a `module.modulemap` inside `Sources/<target>/include/`, it uses *your* map and skips its automatic generation. The minimal working map for a non-trivial C library is:

```
module libfoo {
    requires !cplusplus
    umbrella "."
    export *
}
```

What each line does:

- **`requires !cplusplus`** — Clang skips module compilation when the consumer is C++. C++ consumers fall back to textual `#include` via the `-I` paths SwiftPM puts on the search path. This matters because many C library headers don't parse cleanly as an isolated Clang module under C++ rules; the textual-include fallback bypasses that.
- **`umbrella "."`** — declares the directory containing the modulemap as the umbrella. All `.h` files in that directory and its subdirectories become part of the module. This is much less brittle than listing each header by hand or using `umbrella header "foo.h"` — the latter requires every transitive header to be reachable through `#include` chains from the umbrella header, which fails for header families like libevent's `event2/*_struct.h` that aren't pulled in by the public `event2/event.h`.
- **`export *`** — re-exports every imported symbol so Swift consumers don't need to qualify with the submodule prefix.

If your library's headers happen to live in subdirectories AND the public API is reachable through one umbrella header AND you don't need the `*_struct.h`-family workaround, you can use the simpler form:

```
module libfoo {
    requires !cplusplus
    umbrella header "foo.h"
    export *
}
```

But the directory-umbrella form (`umbrella "."`) is the safer default for non-trivial libraries.

### Step 4 — Exposing the C target as a SwiftPM product

To let other Swift packages depend on your C library directly (not through your Swift wrapper), declare it as a product in `Package.swift`:

```swift
let package = Package(
    name: "swift-libfoo",
    products: [
        .library(name: "libfoo", targets: ["libfoo"]),   // ← raw C bindings
        .library(name: "Foo",    targets: ["Foo"]),       // ← idiomatic Swift API
    ],
    targets: [
        .target(name: "libfoo", /* ... as above ... */),
        .target(name: "Foo", dependencies: ["libfoo"]),
    ]
)
```

A downstream package can then depend on either:

```swift
// Downstream Package.swift
dependencies: [
    .package(url: "https://github.com/you/swift-libfoo.git", branch: "main"),
],
targets: [
    .target(
        name: "MyCLibThatNeedsLibfoo",
        dependencies: [
            .product(name: "libfoo", package: "swift-libfoo"),
        ]
    )
]
```

This is the pattern `swift-tor` uses to depend on this package's `libevent` product:

```swift
// From swift-tor's Package.swift
.target(
    name: "libtor",
    dependencies: [
        .product(name: "libcrypto", package: "swift-openssl"),
        .product(name: "libssl",    package: "swift-openssl"),
        .product(name: "libevent",  package: "swift-event"),
    ]
)
```

The downstream target gets the `libevent` headers on its `-I` path and links the libevent object files transitively. No duplicate libevent build, no source vendoring on the consumer side.

### Step 5 — Test that downstream consumers actually work

The single most useful test you can write for a C-bindings package is "another SwiftPM target can import this and call into it." This package's `libeventTests` target does exactly that — the higher-level Swift API (``EventLoop``, ``Socket``, ``ServerSocket``, ``SocketAddress``, ``SocketError``) lives in a *separate* target (`Event`) that depends on `libevent`, proving the pattern from the consumer side too:

```swift
import XCTest
@testable import libevent

final class libeventTests: XCTestCase {
    func testExample() throws {
        _ = event()    // Constructs a libevent `event` struct — proves the C
                       // headers are visible and the linker resolved.
    }
}
```

If this test passes, your downstream consumers will be able to import your C product. If it fails (typically with "cannot find 'X' in scope" errors), your module map is wrong — usually the umbrella isn't covering all the headers downstream code needs.

### Embedded Swift compatibility (forward-looking)

Apple's [Embedded Swift](https://github.com/apple/swift/blob/main/docs/EmbeddedSwift/UserManual.md) push (WWDC 2024-25) opens a new audience for C-bindings packages: microcontroller and bare-metal Swift code that needs minimal-runtime C interop. Today, the ``Event`` Swift API uses `Foundation`, `CheckedContinuation`, and other features that aren't yet available in Embedded Swift mode — so ``Socket``, ``ServerSocket``, and ``EventLoop`` won't compile under Embedded Swift today. But the `libevent` C product itself has no such dependency and should be consumable from Embedded Swift targets that can build libevent's own dependency footprint.

This is forward-looking — we have not yet certified swift-event's `libevent` product against the Embedded Swift toolchain. If you're trying this, file an issue with the specific build error and we can iterate.

### Common pitfalls

**"Header X not found" inside the C library's own .c files.** Your `cSettings` is missing a header search path. Add `.headerSearchPath("include/foo")` for any subdirectory the C sources `#include "foo/bar.h"` from.

**`module map missing umbrella header`-style warnings under Swift compilation.** Some headers in your `include/` aren't reachable from your declared umbrella. Switch to `umbrella "."` (directory-wide).

**`ambiguous use of 'X'` errors in Swift consumers.** Your library exports a symbol that collides with one from `Darwin` / `Glibc` (e.g., libevent's `EV_TIMEOUT` collides with kqueue's `EV_TIMEOUT` constant on Apple platforms). Disambiguate at the call site with module qualification: `libevent.EV_TIMEOUT`. The ``Event`` package's own ``EventLoop/schedule(after:_:)`` implementation does exactly this.

> Warning: Without module qualification, the Swift compiler picks one of the colliding `EV_TIMEOUT` definitions arbitrarily — usually the wrong one. The compile error is loud (`ambiguous use of 'EV_TIMEOUT'`), but a *successful* build with the wrong constant value can produce silent runtime misbehavior (events that never fire, or fire constantly). Always qualify when both modules are imported in the same file.

**`undefined symbol` at link time but compile succeeds.** A `.c` file is excluded from the build (via `exclude:`) or its source isn't in `Sources/<target>/`. Check `Package.swift`'s `exclude:` list and your file layout.

**Tests pass on macOS but fail on Linux.** Almost always a `_GNU_SOURCE` / `__GLIBC__` issue. Add platform-conditional defines in `cSettings` and check `event-config.h`-style hand-maintained config files for stale assumptions.

## See Also

- <doc:ChoosingLibeventVsEvent>
- <doc:GettingStarted>
- <doc:BackendAndPlatforms>
- ``Event``
- ``EventLoop``
- ``Socket``
- ``ServerSocket``
- ``EventLoop/schedule(after:_:)``
- [`swift-tor`](https://github.com/21-DOT-DEV/swift-tor)
- [Apple SwiftPM documentation: C language targets](https://developer.apple.com/documentation/packagedescription/target)
- [Clang Modules specification](https://clang.llvm.org/docs/Modules.html)
