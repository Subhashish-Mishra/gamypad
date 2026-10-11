import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:gamypad_pc/src/device/gamepad_device.dart';
import 'package:protocol/protocol.dart';

import 'gamepad_ffi.dart';

class UinputDevice implements GamepadDevice {
  UinputDevice() : _handle = _create();

  static Pointer<Void> _create() {
    final handle = gamepadNew();
    if (handle == nullptr) {
      throw DeviceUnavailable(
        'Could not create the Xbox 360 pad: '
        '${nativeLastError().toDartString()}',
      );
    }
    return handle;
  }

  final Pointer<Void> _handle;
  bool _disposed = false;

  final Set<GamepadButton> _pressed = {};
  // Created on the first motion message: most sessions never send one, and the
  // device is visible system-wide while it exists.
  Pointer<Void>? _motion;
  bool _motionFailed = false;

  bool _up = false;
  bool _down = false;
  bool _left = false;
  bool _right = false;

  static const _dpad = {
    GamepadButton.UP,
    GamepadButton.DOWN,
    GamepadButton.LEFT,
    GamepadButton.RIGHT,
  };

  @override
  void setButton(GamepadButton button, bool pressed) {
    if (_dpad.contains(button)) {
      switch (button) {
        case GamepadButton.UP:
          _up = pressed;
        case GamepadButton.DOWN:
          _down = pressed;
        case GamepadButton.LEFT:
          _left = pressed;
        case GamepadButton.RIGHT:
          _right = pressed;
        default:
          break;
      }
      gamepadSetDpad(
        _handle,
        (_right ? 1 : 0) - (_left ? 1 : 0),
        (_down ? 1 : 0) - (_up ? 1 : 0),
      );
      return;
    }

    pressed ? _pressed.add(button) : _pressed.remove(button);
    final key = button.name.toNativeUtf8();
    try {
      pressed ? gamepadPressKey(_handle, key) : gamepadReleaseKey(_handle, key);
    } finally {
      malloc.free(key);
    }
  }

  @override
  void setStick(GamepadStick stick, int x, int y) {
    gamepadSetAxis(_handle, stick.index, x, y);
  }

  @override
  void setTrigger(GamepadTrigger trigger, int value) {
    gamepadSetTrigger(_handle, trigger.index, value);
  }

  @override
  void reset() {
    if (_disposed) return;
    for (final button in _pressed.toList()) {
      setButton(button, false);
    }
    if (_up || _down || _left || _right) {
      _up = _down = _left = _right = false;
      gamepadSetDpad(_handle, 0, 0);
    }
    for (final stick in GamepadStick.values) {
      setStick(stick, stickCenter, stickCenter);
    }
    for (final trigger in GamepadTrigger.values) {
      setTrigger(trigger, triggerMin);
    }
  }

  @override
  void setMotion(MotionMessage m) {
    if (_motionFailed) return;
    var handle = _motion;
    if (handle == null) {
      handle = motionNew();
      if (handle == nullptr) {
        _motionFailed = true;
        return;
      }
      _motion = handle;
    }
    motionSet(handle, m.gx, m.gy, m.gz, m.ax, m.ay, m.az);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final motion = _motion;
    if (motion != null) motionDelete(motion);
    _motion = null;
    if (_up || _down || _left || _right) {
      _up = _down = _left = _right = false;
      gamepadSetDpad(_handle, 0, 0);
    }
    gamepadDelete(_handle);
  }
}
