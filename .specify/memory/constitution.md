<!--
Sync Impact Report:
- Version: 1.0.0 → 1.0.1 (PATCH: polish + external-standard citations)
- Change Type: Amendment (non-semantic refinements)
- Scope: swift-event repository (/Users/csjones/Developer/swift-event)
- Structure: Two-tier (7 core principles + implementation practices in nested format)
- Core Principles (unchanged):
  I. Scope & Upstream Alignment
  II. Resource Safety & Correctness
  III. Swift Concurrency & Sendability
  IV. API Design & Layering
  V. Spec-First & Test-Driven Development
  VI. Cross-Platform CI & Quality Gates
  VII. Open Source Excellence
- Amendments in 1.0.1:
  • Principle III: `@unchecked Sendable` usages now require an inline doc-comment rationale
  • Principle IV: cites Swift API Design Guidelines (https://www.swift.org/documentation/api-design-guidelines/)
  • Governance: cites Semantic Versioning 2.0.0 (https://semver.org/spec/v2.0.0.html)
  • Implementation Guidance › Security Disclosure: collapsed to org-level pointer
  • Principle VII + Preamble: reference org-level CONTRIBUTING.md / SECURITY.md at https://github.com/21-DOT-DEV/.github
- Templates Status:
  ⚠ spec-template.md - Requires alignment review on first feature spec
  ⚠ plan-template.md - Requires alignment review on first feature plan
  ⚠ tasks-template.md - Requires alignment review on first feature tasks
  ⚠ checklist-template.md - Requires alignment review on first feature checklist
- Resolved from 1.0.0:
  ✅ AGENTS.md (root + scoped) created
  ✅ CONTRIBUTING.md / SECURITY.md deferred to org-level (21-DOT-DEV/.github)
-->

# Constitution for swift-event

## Preamble

This constitution governs the **swift-event** package, a Swift wrapper around
[libevent](https://github.com/libevent/libevent) providing event-driven async
I/O and non-blocking TCP sockets across Apple platforms and Linux.

**Scope**: This repository only. Covers both the raw C bindings product
(`libevent`) and the idiomatic Swift API product (`Event`), along with the
vendored upstream sources under `Vendor/libevent/` synchronized via the
`subtree` tool.

**Philosophy**: Principles are technology-agnostic where possible. This is a
thin, zero-runtime-dependency wrapper over a battle-tested C library—
**resource safety, correctness, concurrency discipline, and simplicity** take
precedence over feature breadth. Where libevent already solves a problem, the
Swift layer MUST defer to it rather than re-implement.

**Ecosystem Documents**: Repository-level guidance in this file is complemented
by the authoritative org-level documents at
<https://github.com/21-DOT-DEV/.github>, including `CONTRIBUTING.md`
(branching and commit guidelines) and `SECURITY.md` (vulnerability disclosure).
This constitution does not duplicate that guidance.

---

## Core Principles

### I. Scope & Upstream Alignment

**Statement**: The package MUST focus exclusively on wrapping libevent for
event-driven async I/O on Apple platforms and Linux. libevent MUST remain the
sole source of I/O multiplexing primitives.

**Rationale**: Keeping scope tight reduces complexity and maintenance burden.
Delegating to libevent leverages decades of battle-tested, production I/O
code. Divergence from upstream risks subtle bugs in event loop semantics.

**Practices**:
- **MUST** limit scope to libevent-backed event loops, non-blocking sockets,
  and related I/O primitives (timers, signals, bufferevents where exposed)
- **MUST** use libevent as the sole source of I/O multiplexing primitives
  (`kqueue` on Apple platforms, `epoll` on Linux, `poll`/`select` as fallbacks)
- **MUST** maintain zero runtime dependencies beyond libevent
- **MUST** track a specific, pinned libevent commit/tag in `subtree.yaml`
- **MUST NOT** add dependencies without constitutional review and explicit
  justification
- **MUST NOT** edit files under `Vendor/libevent/` or extracted
  `Sources/libevent/` directly; changes are overwritten on next extraction
- **MUST NOT** port or bundle unsupported upstream backends
  (Windows IOCP, Solaris `devpoll`/`evport`, OpenSSL bufferevents)
- **SHOULD** prefer upgrading the pinned libevent version over patching
  extracted sources
- **MAY** expose selected libevent features progressively as Swift APIs are
  designed; absence of a wrapper is not a defect

**Compliance**: PRs adding new runtime dependencies, upstream backends, or
local patches to vendored sources MUST include justification and constitutional
review. CI blocks unapproved additions.

---

### II. Resource Safety & Correctness

**Statement**: All file descriptors, event loop resources, and C-allocated
memory MUST have deterministic ownership and lifetime. Leaks, use-after-free,
and double-free conditions MUST be prevented by construction.

**Rationale**: I/O libraries manage scarce OS resources (file descriptors,
kernel event structures). Leaks degrade production systems silently; dangling
pointers and double-frees in C interop cause hard-to-diagnose crashes. These
errors are cheap to prevent at design time and expensive to debug in
production.

**Practices**:
- **MUST** define clear ownership for every file descriptor and libevent
  resource (`event_base`, `event`, `bufferevent`) exposed to Swift
- **MUST** release libevent resources in `deinit` or via explicit `close()`
  when ownership is transferred to Swift wrappers
- **MUST** close owned file descriptors on error paths (no partial-init leaks)
- **MUST** set non-blocking mode on any socket used with libevent
- **MUST** validate return codes from C functions and surface errors as typed
  Swift errors (e.g., `SocketError`)
- **MUST NOT** share raw C pointers across concurrent tasks without
  documented synchronization
- **MUST NOT** rely on ARC alone for C resources—pair with explicit release
- **SHOULD** prefer structured concurrency lifetimes for sockets and servers
  (ownership tied to task/scope)
- **SHOULD** test resource cleanup paths (error branches, cancellation,
  abnormal termination)
- **MAY** offer unsafe escape hatches for advanced users, clearly documented
  as such

**Compliance**: Code review MUST verify ownership and cleanup paths. Tests
MUST cover both success and error branches for resource-acquiring APIs.

---

### III. Swift Concurrency & Sendability

**Statement**: The `Event` product MUST conform to Swift 6 strict concurrency
and present a Sendable-correct, structured-concurrency-friendly API.
Continuations bridging libevent callbacks into async Swift MUST be resumed
exactly once on all paths.

**Rationale**: Swift 6 strict concurrency is the language's long-term safety
model; conforming now prevents costly future migrations and protects users
from data races. Continuation misuse (double-resume, leaked resume) causes
crashes or hangs that are nearly impossible to diagnose in shipped code.

**Practices**:
- **MUST** compile cleanly under `swiftLanguageModes: [.v6]` with strict
  concurrency checking
- **MUST** mark public types `Sendable` where semantically correct; use
  `@unchecked Sendable` only with an inline doc-comment rationale naming the
  synchronization mechanism (lock, actor isolation, immutability, etc.)
- **MUST** resume every `CheckedContinuation` exactly once on every code path
  (success, failure, cancellation)
- **MUST** bridge libevent C callbacks to Swift via explicit, memory-safe
  handoffs (`Unmanaged.passRetained` / `takeRetainedValue` with paired counts)
- **MUST** support task cancellation in long-running async APIs where it is
  meaningful (accept loops, reads, writes)
- **MUST NOT** introduce data races or use `nonisolated(unsafe)` without
  documented invariants
- **MUST NOT** block the Swift concurrency cooperative thread pool with
  synchronous libevent calls
- **SHOULD** prefer `AsyncSequence` for streams of events (e.g., incoming
  connections)
- **SHOULD** document threading assumptions for each public type
- **MAY** provide lower-level synchronous escape hatches when async wrapping
  is inappropriate

**Compliance**: CI MUST build with strict concurrency enabled. Code review
MUST trace continuation resume paths for every new async API.

---

### IV. API Design & Layering

**Statement**: The package MUST maintain a two-layer design: a raw C module
(`libevent`) exposing unmodified bindings, and an idiomatic Swift API
(`Event`) providing safe defaults. The layers MUST remain separable so
advanced users can drop to raw bindings.

**Rationale**: A thin Swift layer prevents ecosystem lock-in and allows
experts to bypass abstractions when needed. Safe defaults protect typical
users while preserving access to libevent's full power.

**Practices**:
- **MUST** expose `libevent` as a standalone product (raw C bindings, no
  Swift abstractions leaked in)
- **MUST** provide `Event` as the idiomatic Swift API with safe defaults
  (non-blocking sockets, owned descriptors, typed errors)
- **MUST** use strongly-typed errors for all failure modes (e.g.,
  `SocketError` cases for connect/bind/listen/read/write)
- **MUST** follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
  (naming, argument labels, initializer vs. factory method conventions)
- **MUST** document platform-conditional behavior (backend selection,
  availability) in public API doc comments
- **MUST NOT** leak raw C pointers, `UnsafePointer`, or `OpaquePointer`
  through `Event`'s public API without a clearly named `unsafe*` affordance
- **SHOULD** prefer value types and structured concurrency over reference
  types with manual lifetime management where feasible
- **SHOULD** keep the `Event` surface small and grow it feature-by-feature
  with a spec (Principle V)
- **MAY** provide convenience methods for common patterns (echo server,
  request/response clients)

**Compliance**: Code review enforces API naming and the layering boundary.
New `Event` APIs MUST justify any surfacing of raw C types.

---

### V. Spec-First & Test-Driven Development

**Statement**: Every feature MUST start with a specification. All code MUST
follow test-driven development: tests written first, verified to fail, then
implementation proceeds.

**Rationale**: Specifications ensure alignment with user needs and provide
measurable success criteria. TDD prevents regressions, enables confident
refactoring, and documents expected behavior—especially important for I/O
code where race conditions and edge cases proliferate.

**Practices - Specification Requirements**:
- **MUST** create `spec.md` for every feature before development
- **MUST** represent a single feature or small subfeature (not multiple
  unrelated features)
- **MUST** be independently testable (no dependencies on incomplete specs)
- **MUST** define user scenarios, acceptance criteria, and success metrics
- **MUST NOT** combine multiple unrelated features in one spec
- **MUST NOT** describe implementation details instead of user-facing behavior

**Practices - Test-Driven Development**:
- **MUST** write tests before implementation (red → green → refactor)
- **MUST** verify tests fail initially
- **MUST** cover both happy-path and error-path behavior for every public API
- **MUST** cover resource cleanup (fd close, event release) explicitly
- **MUST** run tests against all supported platforms in CI (see Principle VI)
- **SHOULD** include integration tests exercising real sockets on loopback
- **SHOULD** include a backend-verification test confirming the expected I/O
  backend is in use per platform (e.g., `epoll` on Linux, `kqueue` on macOS)
- **MAY** add property-based or fuzz tests for protocol parsing helpers

**Compliance**: PRs MUST include tests written first. CI blocks merges if
tests are missing or immediately pass without a red phase documented. Specs
combining multiple features MUST be rejected in review.

---

### VI. Cross-Platform CI & Quality Gates

**Statement**: The package MUST maintain support for all advertised
platforms with CI coverage ensuring the package builds and tests pass on each.
Behavior MUST be deterministic within the guarantees libevent provides.

**Rationale**: Cross-platform reliability is a core value proposition.
Differences between `kqueue`, `epoll`, and `poll` backends are a common source
of platform-specific bugs; continuous CI on each platform catches regressions
before release.

**Practices**:
- **MUST** run build and tests on macOS on every PR
- **MUST** run build and tests on Linux on every PR (Docker-based acceptable)
- **MUST** run build (at minimum) on iOS, tvOS, watchOS, and visionOS on every
  PR; run tests where the platform permits
- **MUST** fail CI on any compiler warning in `Event` or `libeventTests`
  under strict concurrency
- **MUST** verify the expected I/O backend is active per platform
  (`kqueue` / `epoll`) via a runtime test
- **MUST NOT** merge code that breaks any supported platform
- **SHOULD** gate merges on a green required-check status matching the
  branch protection policy
- **SHOULD** keep CI workflows minimal and fast; prefer `swift test` over
  `xcodebuild` where feasible
- **MAY** add scheduled workflows for longer-running checks (soak tests,
  upgraded toolchains)

**Compliance**: CI pipeline enforces all MUST-level gates. Platform failures
block merge. Workflow changes affecting required checks require review.

---

### VII. Open Source Excellence

**Statement**: All development MUST follow open source best practices:
comprehensive documentation, welcoming contributions, clear licensing, and
simplicity over cleverness.

**Rationale**: Good documentation reduces friction. Clear decisions preserve
knowledge. Simplicity encourages contributions and reduces maintenance
burden—especially important for small, focused libraries.

**Practices**:
- **MUST** maintain a clear README with setup, installation, and usage
  examples (client, server, event loop)
- **MUST** defer contribution guidelines to the org-level
  [CONTRIBUTING.md](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md)
  (branching and commit guidelines apply)
- **MUST** include a LICENSE file (MIT)
- **MUST** write clear, human-readable code (readability over cleverness)
- **MUST** apply KISS and DRY principles
- **MUST** document all public APIs with Swift doc comments (`///`)
- **MUST** preserve an `AGENTS.md` (root) capturing non-obvious patterns for
  AI and human agents, including the vendored-sources rule
- **SHOULD** defer security disclosure to the org-level [SECURITY.md](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md)
- **SHOULD** provide minimal, runnable usage examples for each major API
  surface
- **SHOULD** respond to community contributions promptly and respectfully
- **MAY** provide issue and PR templates

**Compliance**: PRs MUST include documentation updates for new features or
API changes. Code reviews enforce readability and alignment with the
documented layering.

---

## Implementation Guidance

### Vendored Upstream Sync

**Purpose**: libevent sources live under `Vendor/libevent/` and are extracted
into `Sources/libevent/` via the `subtree` CLI, configured in `subtree.yaml`.

**Requirements**:
- **MUST** pin a specific upstream commit and branch/tag in `subtree.yaml`
- **MUST** treat files under `Vendor/**` and extracted `Sources/libevent/` as
  read-only with respect to local edits
- **MUST** document any manually maintained files alongside the extraction
  config (e.g., platform shims, `event-config.h`)
- **MUST** run the package's full test matrix after every subtree
  re-extraction or upstream bump
- **SHOULD** prefer upstream patches (upstreaming) over local divergence
- **SHOULD** capture the rationale for each extraction pattern/exclusion in
  comments inside `subtree.yaml`

**Security-Relevant Changes**:
- Maintainer MUST document security implications (upstream CVEs addressed,
  behavior changes) in the PR description when bumping libevent
- Upstream bumps SHOULD be landed as isolated PRs (no mixed feature work)

---

### Platform Backend Selection

**Purpose**: Document which I/O backend is expected per platform so tests and
reviewers can validate correctness.

**Expected Backends**:

| Platform | Primary Backend | Fallback |
|----------|-----------------|----------|
| macOS, iOS, tvOS, watchOS, visionOS | `kqueue` | `poll` / `select` |
| Linux | `epoll` | `poll` / `select` |

**Out of Scope**:
- Windows IOCP
- Solaris `devpoll`, `evport`
- OpenSSL-backed bufferevents

**Rationale**: Scope is bounded to the platforms advertised in the README.
Adding a backend requires constitutional review (Principle I).

---

### Security Disclosure Process

**Authoritative source**: <https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md>

This repository defers to the org-level `SECURITY.md` for vulnerability
reporting, contact methods, response timelines, and coordinated disclosure.
This constitution MUST NOT duplicate that guidance; amendments to disclosure
process are made in the org-level document.

---

## Technology Stack (Current Implementation)

**Note**: The constitution defines technology-agnostic principles. This
section documents current choices, which may change without constitutional
amendments.

### Supported Platforms

- **macOS** (arm64, x86_64)
- **iOS** (arm64)
- **tvOS** (arm64)
- **watchOS** (arm64)
- **visionOS** (arm64)
- **Linux** (x86_64, arm64)

### Current Stack (2026-04-18)

- **Language**: Swift 6.1 (strict concurrency, `swiftLanguageModes: [.v6]`)
- **C Standard**: GNU89 (`cLanguageStandard: .gnu89`)
- **Build**: Swift Package Manager (SPM)
- **Testing**: XCTest / swift-testing
- **CI**: GitHub Actions (Apple platforms + Docker/Linux)

### Products

| Product | Type | Description |
|---------|------|-------------|
| `libevent` | C library | Raw bindings to libevent (vendored, extracted from `Vendor/libevent/`) |
| `Event` | Swift library | Idiomatic Swift API: `EventLoop`, `Socket`, `ServerSocket`, `SocketAddress`, `SocketError` |

### Dependencies

- **Runtime**: Zero dependencies beyond the vendored libevent sources
- **Development only**: `swift-plugin-subtree` (subtree sync tooling)

### Upstream

- **libevent**: https://github.com/libevent/libevent (pinned in `subtree.yaml`)

---

## Governance

### Authority

This constitution supersedes all other development practices. Deviations
MUST be explicitly justified and approved.

**Model**: Project owner (BDFL) can amend the constitution directly.
Community proposes changes via GitHub issues.

### Vendored-Upstream Changes

Changes affecting vendored libevent sources require additional scrutiny:

| Requirement | Purpose |
|-------------|---------|
| Document upstream version delta in PR description | Creates audit trail |
| Isolate upstream bumps from feature work | Simplifies bisection |
| Run full cross-platform CI before merge | Prevents backend regressions |
| Explicit "vendored-review" label before merge | Signals intentional consideration |

**Vendored-relevant changes include**:
- Bumping the pinned libevent commit/tag
- Modifying extraction patterns or exclusions in `subtree.yaml`
- Adding or removing platform shims and manually maintained files

### Amendment Process

1. Project owner proposes amendment with rationale and impact analysis
2. Version updated per [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):
   - **MAJOR**: Backward-incompatible changes or principle removals
   - **MINOR**: New principle or materially expanded guidance
   - **PATCH**: Clarifications, wording fixes
3. Update dependent templates in `.specify/templates/`
4. Document changes in Sync Impact Report
5. Commit with descriptive message

### Compliance Review Triggers

| Trigger | Action |
|---------|--------|
| Adding a runtime dependency | Full constitutional alignment check |
| Bumping libevent upstream | Vendored-upstream review protocol |
| Adding a new platform or I/O backend | Scope review (Principle I) |
| Breaking API changes (semver major) | Stability signaling review |
| Changes to public `Event` concurrency semantics | Concurrency review (Principle III) |

### Versioning & Stability

**Pre-1.0** (current):
- No stability guarantees
- Immediate breaking changes acceptable
- Users advised to pin exact versions or use `branch: "main"`

**Post-1.0** (future):
- Semantic versioning strictly enforced
- Deprecation period (one minor version) before removal
- Breaking changes require major version bump

### Enforcement

- PR reviewers verify constitutional alignment
- CI pipeline enforces MUST-level (blocking) and SHOULD-level (warning) gates
- Three-tier enforcement:
  - **MUST**: Blocks merge
  - **SHOULD**: Warning; requires override justification
  - **MAY**: Informational only

---

## Version History

**Version**: 1.0.1
**Ratified**: 2026-04-18
**Last Amended**: 2026-04-18

**Changelog**:
- **1.0.1** (2026-04-18): Polish amendment. Tightened Principle III
  (`@unchecked Sendable` requires inline rationale). Cited Swift API Design
  Guidelines (Principle IV) and Semantic Versioning 2.0.0 (Governance).
  Collapsed Security Disclosure Process to an org-level pointer. Removed
  deferred TODOs for CONTRIBUTING.md / SECURITY.md (superseded by
  21-DOT-DEV/.github). No principle semantics changed.
- **1.0.0** (2026-04-18): Initial constitution with 7 core principles,
  three-tier enforcement, BDFL governance, and vendored-upstream sync
  protocols tailored to the libevent wrapper scope.

---

## Appendix: Principle Mapping

This constitution adapts the swift-secp256k1 constitution's structure to a
non-cryptographic, I/O-focused Swift wrapper library.

**From General Core Principles**:
- Spec-First & Outside-In → Principle V
- Test-Driven Development → Principle V
- Small, Independent Specs → Principle V
- CI & Quality Gates → Principle VI
- Simplicity & Readability → Principle VII
- Open Source Excellence → Principle VII
- Governance & Amendments → Governance

**From I/O Library Concerns (this package)**:
- Bounded Scope & Upstream Delegation → Principle I
- Vendored-Sources Integrity → Principle I, Implementation Guidance
- File Descriptor / Event Lifetime → Principle II
- Error Typing & Propagation → Principles II, IV
- Swift 6 Strict Concurrency → Principle III
- Continuation Safety → Principle III
- Two-Layer Design (raw C + idiomatic Swift) → Principle IV
- Cross-Platform Determinism → Principle VI
- Platform Backend Expectations → Implementation Guidance

**Version**: 1.0.1 | **Ratified**: 2026-04-18 | **Last Amended**: 2026-04-18
