// Swift external-consumer probe. `import libevent` against the swift-event
// package boundary verifies that the shim-header modulemap exposes the
// full C API to consumers that don't go through swift-event's own
// `Event` target. If a future modulemap regression empties out the
// libevent module (e.g. dropping the shim header), `event_base_new()`
// stops resolving and this target fails to compile.
import libevent

public enum SwiftConsumer {

    /// Smoke-test that libevent C symbols are visible after `import libevent`.
    public static func eventBaseRoundTrip() -> Bool {
        guard let base = event_base_new() else { return false }
        event_base_free(base)
        return true
    }
}
