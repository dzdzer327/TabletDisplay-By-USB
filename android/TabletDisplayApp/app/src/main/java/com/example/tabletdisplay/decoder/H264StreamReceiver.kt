package com.example.tabletdisplay.decoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.view.Surface
import java.io.BufferedInputStream
import java.io.DataInputStream
import java.io.EOFException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

sealed interface ReceiverStatus {
  data object Starting : ReceiverStatus
  data class Waiting(val port: Int) : ReceiverStatus
  data class Connected(val peer: String) : ReceiverStatus
  data class Decoding(val width: Int, val height: Int, val frameCount: Long) : ReceiverStatus
  data class Error(val message: String) : ReceiverStatus
  data object Stopped : ReceiverStatus
}

class H264StreamReceiver(
  private val surface: Surface,
  private val onStatus: (ReceiverStatus) -> Unit,
) {
  private val running = AtomicBoolean(false)
  private var scope: CoroutineScope? = null
  private var receiveJob: Job? = null

  @Volatile private var serverSocket: ServerSocket? = null
  @Volatile private var clientSocket: Socket? = null

  fun start() {
    if (!running.compareAndSet(false, true)) return

    onStatus(ReceiverStatus.Starting)
    val receiverScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    scope = receiverScope
    receiveJob = receiverScope.launch { runServer() }
  }

  fun stop() {
    if (!running.compareAndSet(true, false)) return

    clientSocket?.closeQuietly()
    serverSocket?.closeQuietly()
    receiveJob?.cancel()
    scope?.cancel()
    receiveJob = null
    scope = null
    clientSocket = null
    serverSocket = null
    onStatus(ReceiverStatus.Stopped)
  }

  private suspend fun runServer() {
    try {
      ServerSocket().use { server ->
        server.reuseAddress = true
        server.bind(
          InetSocketAddress(InetAddress.getLoopbackAddress(), VideoStreamProtocol.PORT),
          1,
        )
        serverSocket = server

        while (running.get() && scope?.isActive == true) {
          onStatus(ReceiverStatus.Waiting(VideoStreamProtocol.PORT))
          val client = try {
            server.accept()
          } catch (_: SocketException) {
            break
          }

          clientSocket = client
          client.tcpNoDelay = true
          onStatus(ReceiverStatus.Connected(client.inetAddress.hostAddress ?: "ADB"))

          try {
            receiveVideo(client)
          } catch (_: EOFException) {
            // A clean disconnect returns the receiver to the accept loop.
          } catch (error: Exception) {
            if (running.get()) {
              onStatus(ReceiverStatus.Error(error.message ?: error.javaClass.simpleName))
            }
          } finally {
            client.closeQuietly()
            clientSocket = null
          }
        }
      }
    } catch (error: Exception) {
      if (running.get()) {
        onStatus(ReceiverStatus.Error(error.message ?: error.javaClass.simpleName))
      }
    } finally {
      serverSocket = null
    }
  }

  private fun receiveVideo(client: Socket) {
    DataInputStream(BufferedInputStream(client.getInputStream(), 256 * 1024)).use { input ->
      var decoder: MediaCodec? = null
      var decoderWidth = 0
      var decoderHeight = 0
      var renderedFrames = 0L

      try {
        while (running.get()) {
          val packet = readPacket(input)

          if (decoder == null || packet.width != decoderWidth || packet.height != decoderHeight) {
            decoder?.stopAndRelease()
            decoder = createDecoder(packet.width, packet.height)
            decoderWidth = packet.width
            decoderHeight = packet.height
            renderedFrames = 0
          }

          queuePacket(decoder, packet)
          renderedFrames += drainDecoder(decoder)
          onStatus(ReceiverStatus.Decoding(decoderWidth, decoderHeight, renderedFrames))

          if (packet.flags and VideoStreamProtocol.FLAG_END_OF_STREAM != 0) {
            break
          }
        }
      } finally {
        decoder?.stopAndRelease()
      }
    }
  }

  private fun readPacket(input: DataInputStream): VideoPacket {
    val magic = input.readInt()
    require(magic == VideoStreamProtocol.MAGIC) { "Invalid video packet magic: 0x${magic.toString(16)}" }

    val version = input.readInt()
    require(version == VideoStreamProtocol.VERSION) { "Unsupported protocol version: $version" }

    val width = input.readInt()
    val height = input.readInt()
    val flags = input.readInt()
    val payloadSize = input.readInt()
    val presentationTimeUs = input.readLong()

    require(width in 1..8192 && height in 1..8192) { "Invalid frame size: ${width}x$height" }
    require(payloadSize in 0..VideoStreamProtocol.MAX_ACCESS_UNIT_SIZE) {
      "Invalid H.264 access-unit size: $payloadSize"
    }

    val payload = ByteArray(payloadSize)
    input.readFully(payload)
    return VideoPacket(width, height, flags, presentationTimeUs, payload)
  }

  private fun createDecoder(width: Int, height: Int): MediaCodec {
    val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
      setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
      setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, VideoStreamProtocol.MAX_ACCESS_UNIT_SIZE)
    }

    return MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).also { codec ->
      codec.configure(format, surface, null, 0)
      codec.start()
    }
  }

  private fun queuePacket(decoder: MediaCodec, packet: VideoPacket) {
    while (running.get()) {
      val inputIndex = decoder.dequeueInputBuffer(10_000)
      if (inputIndex >= 0) {
        val inputBuffer = checkNotNull(decoder.getInputBuffer(inputIndex))
        inputBuffer.clear()
        inputBuffer.put(packet.payload)

        var codecFlags = 0
        if (packet.flags and VideoStreamProtocol.FLAG_CODEC_CONFIG != 0) {
          codecFlags = codecFlags or MediaCodec.BUFFER_FLAG_CODEC_CONFIG
        }
        if (packet.flags and VideoStreamProtocol.FLAG_KEY_FRAME != 0) {
          codecFlags = codecFlags or MediaCodec.BUFFER_FLAG_KEY_FRAME
        }
        if (packet.flags and VideoStreamProtocol.FLAG_END_OF_STREAM != 0) {
          codecFlags = codecFlags or MediaCodec.BUFFER_FLAG_END_OF_STREAM
        }

        decoder.queueInputBuffer(
          inputIndex,
          0,
          packet.payload.size,
          packet.presentationTimeUs,
          codecFlags,
        )
        return
      }

      drainDecoder(decoder)
    }
  }

  private fun drainDecoder(decoder: MediaCodec): Long {
    val bufferInfo = MediaCodec.BufferInfo()
    var renderedFrames = 0L

    while (true) {
      when (val outputIndex = decoder.dequeueOutputBuffer(bufferInfo, 0)) {
        MediaCodec.INFO_TRY_AGAIN_LATER -> return renderedFrames
        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
        else -> if (outputIndex >= 0) {
          val render = bufferInfo.size > 0
          decoder.releaseOutputBuffer(outputIndex, render)
          if (render) renderedFrames++
        }
      }
    }
  }

  private fun MediaCodec.stopAndRelease() {
    try {
      stop()
    } finally {
      release()
    }
  }

  private fun AutoCloseable.closeQuietly() {
    try {
      close()
    } catch (_: Exception) {
      // Closing is best-effort during disconnect and lifecycle teardown.
    }
  }
}
