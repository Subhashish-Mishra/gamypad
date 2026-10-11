/// Which controller the PC presents to games.
enum PadType {
  /// Xbox 360 pad through uinput. The default; works everywhere.
  xbox360,

  /// Sony DualSense through uhid: a real HID device with gyro, so browsers,
  /// SDL and Steam see a genuine PlayStation controller.
  playstation,
}
