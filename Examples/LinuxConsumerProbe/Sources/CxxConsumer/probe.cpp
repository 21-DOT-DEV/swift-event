#include "probe.h"

// libevent includes are in the .cpp, never the public header — see
// CxxLibeventShim.h for the rationale (module-import-inside-extern-C).
//
// This .cpp is the "pure C++ consumer" regression check: a plain SPM
// C++ target built with `-fmodules` (via Swift C++ interop downstream)
// must be able to textually include event2/*.h. If swift-event's
// libevent modulemap ever re-claims those headers, this compile fails
// with "module 'libevent' is incompatible with feature 'cplusplus'".
#include <event2/event.h>
#include <event2/buffer.h>
#include <event2/bufferevent.h>
#include <event2/listener.h>

int probe_cxx_smoke(void) {
    event_base *b = event_base_new();
    if (b == nullptr) { return 0; }
    event_base_free(b);
    return 1;
}
