// snippet.hide
import Event
// snippet.end

// Inspect the I/O multiplexer libevent selected at initialization time.
// "kqueue" on Apple platforms, "epoll" on Linux.
let loop = EventLoop()
print(loop.backendMethod)
