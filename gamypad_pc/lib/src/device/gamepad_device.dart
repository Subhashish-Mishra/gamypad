import 'package:protocol/protocol.dart';

abstract interface class GamepadDevice {
  void setButton(GamepadButton button, bool pressed);
  void setTrigger(GamepadTrigger trigger, int value);
  void setStick(GamepadStick stick, int x, int y);
  /// Releases every button, centres both sticks, zeroes both triggers.
  void reset();
  void dispose();
}
