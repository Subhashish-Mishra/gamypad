import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:gamypad_pc/src/device/gamepad_device.dart';
import 'package:protocol/protocol.dart';

import 'gamepad_ffi.dart';

/// A Sony DualSense, created through /dev/uhid.
///
/// The native side keeps the controller state and sends a full input report at
/// ~125 Hz, so these calls only update that state.
class DualSenseDevice implements GamepadDevice {
  DualSenseDevice() : _handle = _create();

  static Pointer<Void> _create() {
    final handle = dualSenseNew();
    if (handle == nullptr) {
      throw DeviceUnavailable(
        'Could not create the PlayStation pad: '
        '${nativeLastError().toDartString()}. '
        'It needs access to /dev/uhid — re-run the installer, then log out '
        'and back in.',
      );
    }
    return handle;
  }

  final Pointer<Void> _handle;
  bool _disposed = false;

  final Set<GamepadButton> _pressed = {};
  bool _up = false;
  bool _down = false;
  bool _left = false;
  bool _right = false;

  void _pushDpad() => dualSenseSetDpad(
    _handle,
    (_right ? 1 : 0) - (_left ? 1 : 0),
    (_down ? 1 : 0) - (_up ? 1 : 0),
  );

  @override
  void setButton(GamepadButton button, bool pressed) {
    switch (button) {
      case GamepadButton.UP:
        _up = pressed;
        _pushDpad();
      case GamepadButton.DOWN:
        _down = pressed;
        _pushDpad();
      case GamepadButton.LEFT:
        _left = pressed;
        _pushDpad();
      case GamepadButton.RIGHT:
        _right = pressed;
        _pushDpad();
      default:
        pressed ? _pressed.add(button) : _pressed.remove(button);
        final name = button.name.toNativeUtf8();
        try {
          dualSenseSetButton(_handle, name, pressed ? 1 : 0);
        } finally {
          malloc.free(name);
        }
    }
  }

  @override
  void setStick(GamepadStick stick, int x, int y) =>
      dualSenseSetStick(_handle, stick.index, x, y);

  @override
  void setTrigger(GamepadTrigger trigger, int value) =>
      dualSenseSetTrigger(_handle, trigger.index, value);

  @override
  void setMotion(MotionMessage m) =>
      dualSenseSetMotion(_handle, m.gx, m.gy, m.gz, m.ax, m.ay, m.az);

  @override
  void reset() {
    if (_disposed) return;
    for (final button in _pressed.toList()) {
      setButton(button, false);
    }
    _up = _down = _left = _right = false;
    _pushDpad();
    for (final stick in GamepadStick.values) {
      setStick(stick, stickCenter, stickCenter);
    }
    for (final trigger in GamepadTrigger.values) {
      setTrigger(trigger, triggerMin);
    }
    dualSenseSetMotion(_handle, 0, 0, 0, 0, 0, 0);
  }

  @override
  void dispose() {
    if (_disposed) return;
    reset();
    _disposed = true;
    dualSenseDelete(_handle);
  }
}
