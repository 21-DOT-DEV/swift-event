/*
 * swift-shim.h — Swift-visible umbrella for the libevent public API.
 *
 * Why this file exists
 * ====================
 *
 * swift-event ships `libevent` as a Clang module so that Swift consumers
 * (most importantly this package's own `Event` target) can
 * `import libevent` and see the full libevent C API.
 *
 * However, swift-event is ALSO consumed by projects that pull libevent
 * into C or C++ translation units via `#include <event2/…>`. When a
 * downstream package (e.g. swift-bitcoin) compiles its C++ under Swift
 * C++ interop, Clang is invoked with `-fmodules` forced on. If our
 * modulemap claimed ownership of the event2 headers — for example via
 * an umbrella-directory declaration — Clang would try to load the module
 * during the C++ compile, find the `requires !cplusplus` clause, and
 * emit:
 *
 *     error: module 'libevent' is incompatible with feature 'cplusplus'
 *
 * instead of falling through to a plain textual `#include`. That is the
 * opposite of what a C++ consumer wants.
 *
 * The fix: the modulemap lists ONLY this shim header. No event2 header
 * is claimed by any module, so when a C/C++ consumer resolves
 * `#include <event2/event.h>` via the `-I` search path, Clang finds a
 * file not owned by any module and textually includes it — the same
 * semantics as if no modulemap existed at all.
 *
 * For a Swift consumer, `import libevent` causes Clang to parse this
 * shim. The shim transitively pulls in every public libevent header, so
 * Swift still sees the full C API (events, buffer events, DNS, HTTP,
 * RPC, listeners, thread helpers, and the top-level legacy aliases).
 *
 * This file is maintained by hand — it is NOT produced by the libevent
 * subtree extraction. Update it when new public headers are added
 * upstream.
 */
#ifndef LIBEVENT_SWIFT_SHIM_H
#define LIBEVENT_SWIFT_SHIM_H

/* event2/ — current public API (preferred for new code). */
#include "event2/visibility.h"
#include "event2/event-config.h"
#include "event2/util.h"
#include "event2/event.h"
#include "event2/event_struct.h"
#include "event2/event_compat.h"
#include "event2/buffer.h"
#include "event2/buffer_compat.h"
#include "event2/bufferevent.h"
#include "event2/bufferevent_struct.h"
#include "event2/bufferevent_compat.h"
#include "event2/bufferevent_ssl.h"
#include "event2/listener.h"
#include "event2/dns.h"
#include "event2/dns_struct.h"
#include "event2/dns_compat.h"
#include "event2/http.h"
#include "event2/http_struct.h"
#include "event2/http_compat.h"
#include "event2/rpc.h"
#include "event2/rpc_struct.h"
#include "event2/rpc_compat.h"
#include "event2/tag.h"
#include "event2/tag_compat.h"
#include "event2/keyvalq_struct.h"
#include "event2/thread.h"

/* Top-level legacy headers — thin re-exports of the event2/ API. */
#include "event.h"
#include "evdns.h"
#include "evhttp.h"
#include "evrpc.h"
#include "evutil.h"

#endif /* LIBEVENT_SWIFT_SHIM_H */
