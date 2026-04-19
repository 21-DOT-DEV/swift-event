# AGENTS.md (Tests)

This directory contains SwiftPM test targets using **Swift Testing** (`import Testing`, `@Test`, `@Suite`, `#expect`).

## Test targets

- `EventTests` — tests for the `Event` Swift API.
- `libeventTests` — tests for the raw `libevent` C bindings.

## Required invariants

- **Backend verification** (`EventTests › EventLoop uses optimal backend`): `EventLoop().backendMethod` MUST return `"kqueue"` on Apple platforms and `"epoll"` on Linux. This is an invariant enforced by the constitution (Principle V) — do not weaken or remove this test without constitutional review.

## Conventions

- Bug fixes MUST include a regression test (constitution Principle V).
- Cover both happy-path and error-path behavior for every public API (constitution Principle V).
- Cover resource cleanup (fd close, event release) explicitly (constitution Principle II).
- Prefer structured concurrency patterns (`async`/`await`, task cancellation) in tests that exercise `Event`.
