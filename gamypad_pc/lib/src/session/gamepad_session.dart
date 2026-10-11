import 'dart:async';
import 'dart:io';

import 'package:gamypad_pc/src/device/gamepad_device.dart';
import 'package:gamypad_pc/src/device/pad_type.dart';
import 'package:gamypad_pc/src/transport/message_socket.dart';
import 'package:protocol/protocol.dart';

void _trace(String message) {
  stderr.writeln('[session] $message');
}

class GamepadSession {
  final MessageSocket socket;
  final DeviceFactory deviceFactory;

  GamepadSession({required this.socket, required this.deviceFactory});

  /// The virtual pad. It exists only while the server runs, so games do not
  /// see a controller that nothing is driving.
  GamepadDevice? _device;

  StreamSubscription<Message>? _subscription;
  StreamSubscription<ConnectionState>? _stateSubscription;

  Stream<ConnectionState> get state => socket.state;
  int get port => socket.port;

  Future<void> start({int port = 0, PadType padType = PadType.xbox360}) async {
    _trace('start() called, pad: ${padType.name}');
    // Before the socket: if the pad cannot be made there is nothing to serve.
    final device = deviceFactory(padType);
    _device = device;
    _subscription = socket.messages.listen(
      apply,
      onError: (Object error, StackTrace stack) {
        _trace('stream error: $error');
        Error.throwWithStackTrace(error, stack);
      },
    );
    // A client that goes quiet may be holding buttons; nobody is left to
    // release them.
    _stateSubscription = socket.state.listen((next) {
      if (next != ConnectionState.connected) _device?.reset();
    });
    _trace('subscribed to ${socket.runtimeType}.messages');
    try {
      await socket.start(port: port);
      _trace('socket.start() returned, port=${socket.port}');
    } catch (e, st) {
      _trace('socket.start() THREW ${e.runtimeType}: $e');
      _trace('stack: $st');
      // Leave nothing subscribed, or a retry would apply every message twice.
      await _subscription?.cancel();
      _subscription = null;
      await _stateSubscription?.cancel();
      _stateSubscription = null;
      _releaseDevice();
      rethrow;
    }
  }

  Future<void> stop() async {
    _trace('stop() called');
    await _subscription?.cancel();
    _subscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    _releaseDevice();
    _trace('subscription cancelled');
    await socket.stop();
    _trace('socket stopped');
  }

  void dispose() {
    _trace('dispose() -> device.dispose()');
    _releaseDevice();
  }

  void _releaseDevice() {
    _device?.reset();
    _device?.dispose();
    _device = null;
  }

  void apply(Message message) {
    switch (message) {
      case ButtonMessage(:final button, :final pressed):
        _device?.setButton(button, pressed);
      case TriggerMessage(:final trigger, :final value):
        _device?.setTrigger(trigger, value);
      case StickMessage(:final stick, :final x, :final y):
        _device?.setStick(stick, x, y);
      case MotionMessage():
        _device?.setMotion(message);
      case Ping():
        socket.send(const Pong());
      case Pong():
        break;
    }
  }
}
