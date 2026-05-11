#pragma once

// Public surface of the C++ libevent shim. This header MUST NOT
// `#include <event2/...>` — the headers are confined to the .cpp file,
// which mirrors the swift-bitcoin pattern (bitcoind's public headers
// only expose its own C bridge declarations; <event2/...> is consumed
// internally in .cpp translation units).
//
// Why the discipline matters: a Swift target that does
// `import CxxLibeventShim` triggers Clang to compile this public header
// as the CxxLibeventShim Clang module under C++ + `-fmodules`. If we
// transitively pulled in <event2/util.h> here, Clang would try to load
// <sys/socket.h> as a module from inside libevent's `extern "C" {}`
// block on macOS — which is illegal — and the build fails. Keeping
// libevent includes out of the public header replicates the production
// boundary swift-bitcoin maintains.
//
// The libevent regression we DO want to catch is exercised one level
// down: CxxLibeventShim.cpp does `#include <event2/event.h>` directly,
// and that .cpp is compiled under C++ mode with -fmodules forced on by
// Swift C++ interop's transitive settings. If the libevent modulemap
// ever re-claims event2/*.h, *that* compile fails first.

#ifdef __cplusplus
extern "C" {
#endif

/// Round-trip an `event_base` from C++ via libevent. Returns 1 on success,
/// 0 on failure. Exposed as a plain C entry point so it crosses the Swift
/// C++ interop boundary cleanly without forcing event2 types into the
/// public surface.
int cxx_libevent_round_trip(void);

#ifdef __cplusplus
}
#endif
