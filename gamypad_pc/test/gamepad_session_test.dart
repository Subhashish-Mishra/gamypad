import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gamypad_pc/src/device/gamepad_device.dart';
import 'package:gamypad_pc/src/device/pad_type.dart';
import 'package:gamypad_pc/src/session/gamepad_session.dart';
import 'package:gamypad_pc/src/transport/message_socket.dart';
import 'package:protocol/protocol.dart';

class _FakeSocket implements MessageSocket {
  final messagesController = StreamController<Message>.broadcast(sync: true);
  final stateController = StreamController<ConnectionState>.broadcast(
    sync: true,
  );
  final sent = <Message>[];
  bool started = false;
  bool failStart = false;
  int? startedOnPort;

  @override
  Stream<Message> get messages => messagesController.stream;
  @override
  Stream<ConnectionState> get state => stateController.stream;
  @override
  int get port => 4242;
  @override
  void send(Message message) => sent.add(message);

  @override
  Future<void> start({int port = 0}) async {
    if (failStart) throw StateError('port in use');
    started = true;
    startedOnPort = port;
  }

  @override
  Future<void> stop() async => started = false;
}

class _FakeDevice implements GamepadDevice {
  _FakeDevice(this.type);
  final PadType type;
  final calls = <String>[];
  bool disposed = false;

  @override
  void setButton(GamepadButton button, bool pressed) =>
      calls.add('button ${button.name} $pressed');
  @override
  void setTrigger(GamepadTrigger trigger, int value) =>
      calls.add('trigger ${trigger.name} $value');
  @override
  void setStick(GamepadStick stick, int x, int y) =>
      calls.add('stick ${stick.name} $x $y');
  @override
  void setMotion(MotionMessage motion) => calls.add('motion ${motion.gx}');
  @override
  void reset() => calls.add('reset');
  @override
  void dispose() => disposed = true;
}

void main() {
  late _FakeSocket socket;
  late List<_FakeDevice> made;
  Object? factoryError;

  GamepadSession build() => GamepadSession(
    socket: socket,
    deviceFactory: (type) {
      if (factoryError != null) throw factoryError!;
      final d = _FakeDevice(type);
      made.add(d);
      return d;
    },
  );

  setUp(() {
    socket = _FakeSocket();
    made = [];
    factoryError = null;
  });

  test('no pad exists until the server starts', () {
    build();
    expect(made, isEmpty);
  });

  test(
    'the pad is built for the chosen type and the port is passed on',
    () async {
      final session = build();
      await session.start(port: 5000, padType: PadType.playstation);

      expect(made.single.type, PadType.playstation);
      expect(socket.startedOnPort, 5000);
    },
  );

  test('defaults to the Xbox 360 pad', () async {
    await build().start();
    expect(made.single.type, PadType.xbox360);
  });

  test('stopping releases the pad', () async {
    final session = build();
    await session.start();
    await session.stop();

    expect(made.single.disposed, isTrue);
    expect(made.single.calls, contains('reset'));
  });

  test(
    'a new start after a stop builds a fresh pad, of the new type',
    () async {
      final session = build();
      await session.start(padType: PadType.xbox360);
      await session.stop();
      await session.start(padType: PadType.playstation);

      expect(made.map((d) => d.type), [PadType.xbox360, PadType.playstation]);
      expect(made.first.disposed, isTrue);
      expect(made.last.disposed, isFalse);
    },
  );

  test(
    'if the pad cannot be made, start fails and the socket stays off',
    () async {
      factoryError = const DeviceUnavailable('no /dev/uhid');
      final session = build();

      await expectLater(
        session.start(padType: PadType.playstation),
        throwsA(isA<DeviceUnavailable>()),
      );
      expect(socket.started, isFalse);
      expect(socket.messagesController.hasListener, isFalse);
    },
  );

  test('if the socket cannot start, the pad is released again', () async {
    socket.failStart = true;
    final session = build();

    await expectLater(session.start(), throwsStateError);
    expect(made.single.disposed, isTrue);
    expect(socket.messagesController.hasListener, isFalse);
  });

  test('messages drive the pad', () async {
    await build().start();
    socket.messagesController
      ..add(const ButtonMessage(button: GamepadButton.A, pressed: true))
      ..add(const TriggerMessage(trigger: GamepadTrigger.RT, value: 200))
      ..add(const StickMessage(stick: GamepadStick.leftStick, x: 5, y: -5))
      ..add(const MotionMessage(gx: 77));

    expect(made.single.calls, [
      'button A true',
      'trigger RT 200',
      'stick leftStick 5 -5',
      'motion 77',
    ]);
  });

  test('a ping is answered with a pong', () async {
    await build().start();
    socket.messagesController.add(const Ping());
    expect(socket.sent.single, isA<Pong>());
  });

  test('inputs are released when the client goes away', () async {
    await build().start();
    socket.stateController.add(ConnectionState.connected);
    expect(made.single.calls, isNot(contains('reset')));

    socket.stateController.add(ConnectionState.listening);
    expect(made.single.calls, contains('reset'));
  });

  test('messages after stop are ignored', () async {
    final session = build();
    await session.start();
    await session.stop();
    socket.messagesController.add(
      const ButtonMessage(button: GamepadButton.A, pressed: true),
    );

    expect(made.single.calls.where((c) => c.startsWith('button')), isEmpty);
  });
}
