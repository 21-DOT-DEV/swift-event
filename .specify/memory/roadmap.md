# swift-event Product Roadmap

**Version**: v1.0.4  
**Last Updated**: 2026-04-21  

---

## Vision & Goals

Provide a Swift wrapper for libevent, enabling high-performance asynchronous I/O with Swift concurrency on all Apple platforms and Linux.

**Target Audience**:
- Swift developers building network applications
- Projects requiring cross-platform async I/O (macOS + Linux)
- Tor integration via swift-tor

**Core Value Proposition**:
- Swift concurrency integration (async/await)
- Cross-platform support (all Apple platforms + Linux)
- Minimal dependencies

---

## 🔴 High Priority Items

| Item | Description | Status |
|------|-------------|--------|
| **Linux Basic Support** | Build and test on Linux using poll/select backend. Disable macOS-specific features (kqueue, Mach headers). Uses bundled BSD functions (no external deps). | ✅ Complete |
| **Linux Epoll Backend** | Add `epoll.c` from `Vendor/libevent/` for optimized Linux I/O (O(1) vs O(n) for poll/select). Only `epoll.c` needed - Solaris/Windows backends out of scope. | ✅ Complete |

---

## Phases Overview

| Phase | Name | Status | File |
|-------|------|--------|------|
| **0** | Foundation | ✅ Complete | — |
| **1** | Linux Basic Support | ✅ Complete | [phase-1-linux-basic.md](roadmap/phase-1-linux-basic.md) |
| **2** | Linux Epoll Backend | ✅ Complete | [phase-2-linux-epoll.md](roadmap/phase-2-linux-epoll.md) |
| **2.1** | Remove libbsd Dependency | ✅ Complete | [phase-2.1-remove-libbsd.md](roadmap/phase-2.1-remove-libbsd.md) |
| **2.5** | Linux Optimizations | ✅ Complete | [phase-2.5-linux-optimizations.md](roadmap/phase-2.5-linux-optimizations.md) |
| **3** | CI & Quality Gates | ✅ Complete | — |
| **3.5** | DocC & Documentation Parity | ✅ Complete | — |
| **4** | Benchmark Suite | 🔜 Planned | — |

---

## Product-Level Metrics & Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| macOS build & test | Pass | ✅ |
| Linux build & test (poll/select) | Pass | ✅ |
| Linux build & test (epoll) | Pass | ✅ |
| Platform CI pass rate | 100% across macOS + Linux | ✅ |

---

## Change Log

| Version | Date | Change Type | Description |
|---------|------|-------------|-------------|
| v1.0.0 | 2025-01-26 | Initial | Initial roadmap with Linux support phases |
| v1.0.1 | 2026-01-30 | Enhancement | Phase 2.1: Remove libbsd dependency, use bundled implementations |
| v1.0.2 | 2026-01-30 | Enhancement | Phase 2.5: Linux optimizations (pipe2, eventfd, accept4, splice) |
| v1.0.3 | 2026-01-30 | Enhancement | Runtime backend verification test (epoll/kqueue) |
| v1.0.4 | 2026-04-21 | Enhancement | Phase 3.5: DocC catalog + articles + inline rationales, platform normalization, constitutional compliance (III.1, VII) |
