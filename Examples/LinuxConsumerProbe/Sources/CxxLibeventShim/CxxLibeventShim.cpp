#include "CxxLibeventShim.h"

// libevent headers stay HERE, in the .cpp, not in the public header.
// This is the regression boundary: this translation unit is compiled
// as C++ with `-fmodules` forced on (transitively, via swift-bitcoin-
// shaped Swift C++ interop downstream). If swift-event's libevent
// modulemap ever re-claims event2/*.h, this `#include` fails with
// "module 'libevent' is incompatible with feature 'cplusplus'".
#include <event2/event.h>

int cxx_libevent_round_trip(void) {
    event_base *b = event_base_new();
    if (b == nullptr) { return 0; }
    event_base_free(b);
    return 1;
}
