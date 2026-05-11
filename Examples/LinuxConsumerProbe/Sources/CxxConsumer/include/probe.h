#pragma once

// Public surface of the pure-C++ probe target. As with CxxLibeventShim,
// `<event2/...>` includes stay in probe.cpp, not in the public header —
// any consumer of CxxConsumer that imports it as a Clang module would
// otherwise hit "module 'Darwin.POSIX.sys.socket' inside extern \"C\"".
// The libevent modulemap regression boundary is exercised in probe.cpp.

#ifdef __cplusplus
extern "C" {
#endif

int probe_cxx_smoke(void);

#ifdef __cplusplus
}
#endif
