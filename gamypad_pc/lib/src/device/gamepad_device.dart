import 'package:gamypad_pc/src/device/pad_type.dart';
import 'package:protocol/protocol.dart';

abstract interface class GamepadDevice {
  void setButton(GamepadButton button, bool pressed);
  void setTrigger(GamepadTrigger trigger, int value);
  void setStick(GamepadStick stick, int x, int y);

  /// Releases every button, centres both sticks, zeroes both triggers.
  void reset();
  void setMotion(MotionMessage motion);
  void dispose();
}

/// The virtual pad could not be created. [message] is fit to show the user.
class DeviceUnavailable implements Exception {
  const DeviceUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Builds the device for [type]. Throws [DeviceUnavailable] if it cannot.
typedef DeviceFactory = GamepadDevice Function(PadType type);
