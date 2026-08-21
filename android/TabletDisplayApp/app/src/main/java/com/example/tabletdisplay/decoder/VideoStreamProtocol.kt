package com.example.tabletdisplay.decoder

object VideoStreamProtocol {
  const val PORT = 27183
  const val MAGIC = 0x54445350
  const val VERSION = 1
  const val HEADER_SIZE = 32
  const val MAX_ACCESS_UNIT_SIZE = 8 * 1024 * 1024

  const val FLAG_CODEC_CONFIG = 1
  const val FLAG_KEY_FRAME = 1 shl 1
  const val FLAG_END_OF_STREAM = 1 shl 2
}

data class VideoPacket(
  val width: Int,
  val height: Int,
  val flags: Int,
  val presentationTimeUs: Long,
  val payload: ByteArray,
)
