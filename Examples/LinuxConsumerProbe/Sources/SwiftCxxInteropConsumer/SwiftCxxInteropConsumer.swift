// Swift target with C++ interop enabled, consuming a C++ shim that
// internally `#include`s <event2/event.h>. Mirrors swift-bitcoin's
// actual Swift→libevent path: Swift C++ interop forces `-fmodules` for
// the C++ side, so CxxLibeventShim.cpp compiles under modules + C++ —
// the configuration that broke in swift-event 0.2.0 with
// `umbrella "."`.
//
// The shim's *public* header deliberately stays libevent-free; only the
// `.cpp` pulls in event2/*. That matches how swift-bitcoin's bitcoind
// target is structured and ensures we test the libevent modulemap's
// behavior at exactly the regression boundary.
import CxxLibeventShim

public enum SwiftCxxInteropConsumer {

    /// Returns true if the C++ shim can round-trip an `event_base`.
    public static func smokeTest() -> Bool {
        return cxx_libevent_round_trip() == 1
    }
}
