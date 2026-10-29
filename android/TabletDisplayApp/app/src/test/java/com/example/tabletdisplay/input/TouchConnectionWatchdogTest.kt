package com.example.tabletdisplay.input

import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TouchConnectionWatchdogTest {
  @Test fun remoteCloseIsDetectedWithoutSendingTouch() {
    ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { server ->
      Socket(InetAddress.getLoopbackAddress(), server.localPort).use { client ->
        val peer = server.accept()
        val watcher = watchTouchPeer(client)
        peer.close()
        watcher.join(2000)
        assertFalse("EOF watcher must finish without a user gesture", watcher.isAlive)
        assertTrue(client.isClosed)
      }
    }
  }
  @Test fun localStopReleasesTheWatcher() {
    ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { server ->
      Socket(InetAddress.getLoopbackAddress(), server.localPort).use { client ->
        server.accept().use {
          val watcher = watchTouchPeer(client)
          client.close()
          watcher.join(2000)
          assertFalse(watcher.isAlive)
        }
      }
    }
  }
}
