package com.example.tabletdisplay.input

import java.net.Socket

// The input protocol is one-way. Read only to detect the Windows peer closing
// its socket during a settings change, even when the user is not touching.
internal fun watchTouchPeer(socket: Socket): Thread =
  Thread({
    try {
      val input = socket.getInputStream()
      while (!socket.isClosed && input.read() >= 0) { /* no server payload expected */ }
    } catch (_: Exception) {
      // Closing locally and losing the remote peer both invalidate this session.
    } finally {
      try { socket.close() } catch (_: Exception) { }
    }
  }, "TabletDisplayTouchPeer").apply { isDaemon = true; start() }
