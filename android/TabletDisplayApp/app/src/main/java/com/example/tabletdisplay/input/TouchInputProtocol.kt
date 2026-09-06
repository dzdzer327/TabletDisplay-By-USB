package com.example.tabletdisplay.input

object TouchInputProtocol {
  const val PORT = 27184
  const val MAGIC = 0x54444950
  const val VERSION = 1
  const val HEADER_SIZE = 16
  const val CONTACT_SIZE = 20
  const val MAX_CONTACTS = 10

  const val ACTION_DOWN = 1
  const val ACTION_MOVE = 2
  const val ACTION_UP = 3
  const val ACTION_CANCEL = 4
}
