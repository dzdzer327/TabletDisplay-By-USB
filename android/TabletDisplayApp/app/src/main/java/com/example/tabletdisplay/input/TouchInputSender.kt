package com.example.tabletdisplay.input

import android.util.Log
import android.view.MotionEvent
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

private data class TouchContact(
  val pointerId: Int,
  val action: Int,
  val normalizedX: Int,
  val normalizedY: Int,
  val pressure: Int,
)

private data class TouchFrame(val contacts: List<TouchContact>)

class TouchInputSender {
  private companion object {
    const val TAG = "TabletDisplayInput"
    const val NORMALIZED_MAX = 1_000_000
  }

  private val running = AtomicBoolean(false)
  private val frames = LinkedBlockingQueue<TouchFrame>(256)

  @Volatile private var worker: Thread? = null
  @Volatile private var socket: Socket? = null

  fun start() {
    if (!running.compareAndSet(false, true)) return
    worker = Thread(::runSender, "TabletDisplayTouchSender").also { it.start() }
  }

  fun stop() {
    if (!running.compareAndSet(true, false)) return
    socket?.closeQuietly()
    worker?.interrupt()
    worker = null
    socket = null
    frames.clear()
  }

  fun send(event: MotionEvent, viewWidth: Int, viewHeight: Int) {
    if (!running.get() || viewWidth <= 0 || viewHeight <= 0) return

    val maskedAction = event.actionMasked
    val actionIndex = event.actionIndex
    val contacts =
      List(event.pointerCount.coerceAtMost(TouchInputProtocol.MAX_CONTACTS)) { index ->
        val action =
          when {
            maskedAction == MotionEvent.ACTION_CANCEL -> TouchInputProtocol.ACTION_CANCEL
            index == actionIndex &&
              (maskedAction == MotionEvent.ACTION_DOWN ||
                maskedAction == MotionEvent.ACTION_POINTER_DOWN) -> TouchInputProtocol.ACTION_DOWN
            index == actionIndex &&
              (maskedAction == MotionEvent.ACTION_UP ||
                maskedAction == MotionEvent.ACTION_POINTER_UP) -> TouchInputProtocol.ACTION_UP
            else -> TouchInputProtocol.ACTION_MOVE
          }
        TouchContact(
          pointerId = event.getPointerId(index) + 1,
          action = action,
          normalizedX =
            ((event.getX(index) / viewWidth) * NORMALIZED_MAX)
              .roundToInt()
              .coerceIn(0, NORMALIZED_MAX),
          normalizedY =
            ((event.getY(index) / viewHeight) * NORMALIZED_MAX)
              .roundToInt()
              .coerceIn(0, NORMALIZED_MAX),
          pressure = (event.getPressure(index) * 1024).roundToInt().coerceIn(1, 1024),
        )
      }

    if (!frames.offer(TouchFrame(contacts))) {
      frames.poll()
      frames.offer(TouchFrame(contacts))
    }
  }

  private fun runSender() {
    while (running.get()) {
      try {
        Socket().use { connectedSocket ->
          connectedSocket.tcpNoDelay = true
          connectedSocket.connect(
            InetSocketAddress(InetAddress.getLoopbackAddress(), TouchInputProtocol.PORT),
            750,
          )
          socket = connectedSocket
          Log.i(TAG, "Windows touch receiver connected through ADB reverse")

          DataOutputStream(BufferedOutputStream(connectedSocket.getOutputStream(), 16 * 1024)).use { output ->
            while (running.get() && !connectedSocket.isClosed) {
              val frame = frames.poll(250, TimeUnit.MILLISECONDS) ?: continue
              writeFrame(output, frame)
            }
          }
        }
      } catch (_: InterruptedException) {
        break
      } catch (error: Exception) {
        if (running.get()) {
          Log.d(TAG, "Touch receiver is not ready: ${error.message}")
          try {
            Thread.sleep(500)
          } catch (_: InterruptedException) {
            break
          }
        }
      } finally {
        socket = null
      }
    }
  }

  private fun writeFrame(output: DataOutputStream, frame: TouchFrame) {
    output.writeInt(TouchInputProtocol.MAGIC)
    output.writeInt(TouchInputProtocol.VERSION)
    output.writeInt(frame.contacts.size)
    output.writeInt(0)
    frame.contacts.forEach { contact ->
      output.writeInt(contact.pointerId)
      output.writeInt(contact.action)
      output.writeInt(contact.normalizedX)
      output.writeInt(contact.normalizedY)
      output.writeInt(contact.pressure)
    }
    output.flush()
  }

  private fun AutoCloseable.closeQuietly() {
    try {
      close()
    } catch (_: Exception) {
      // Disconnect is best-effort during lifecycle teardown.
    }
  }
}
