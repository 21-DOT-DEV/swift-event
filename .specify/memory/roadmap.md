# swift-event Product Roadmap

**Version**: v1.0.0  
**Last Updated**: 2025-01-26  

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
| **Linux Basic Support** | Build and test on Linux using poll/select backend. Disable macOS-specific features (kqueue, Mach headers). Add libbsd dependency for BSD functions. | ✅ Complete |
| **Linux Epoll Backend** | Add `epoll.c` from `Vendor/libevent/` for optimized Linux I/O (O(1) vs O(n) for poll/select). Only `epoll.c` needed - Solaris/Windows backends out of scope. | 🔜 Planned |

---

## Phases Overview

| Phase | Name | Status | File |
|-------|------|--------|------|
| **0** | Foundation | ✅ Complete | — |
| **1** | Linux Basic Support | ✅ Complete | [phase-1-linux-basic.md](roadmap/phase-1-linux-basic.md) |
| **2** | Linux Epoll Backend | 🔜 Planned | [phase-2-linux-epoll.md](roadmap/phase-2-linux-epoll.md) |
| **3** | CI & Quality Gates | 🔜 Planned | — |

---

## Product-Level Metrics & Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| macOS build & test | Pass | ✅ |
| Linux build & test (poll/select) | Pass | ✅ |
| Linux build & test (epoll) | Pass | 🔜 |
| Platform CI pass rate | 100% across macOS + Linux | 🔜 |

---

## Change Log

| Version | Date | Change Type | Description |
|---------|------|-------------|-------------|
| v1.0.0 | 2025-01-26 | Initial | Initial roadmap with Linux support phases |
