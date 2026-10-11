import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gamypad_controller/src/connection/connection_status.dart';
import 'package:gamypad_controller/src/connection/connection_target.dart';
import 'package:gamypad_controller/src/connection/gamepad_transport.dart';
import 'package:protocol/protocol.dart';

class UdpTransport implements GamepadTransport {
  UdpTransport({
    this.pingInterval = const Duration(seconds: 2),
    this.checkInterval = const Duration(seconds: 1),
    this.timeout = const Duration(seconds: 8),
  });

  /// How often a [Ping] goes out. UDP drops packets, so [timeout] must span
  /// several of these — one lost ping or pong must never end the link.
  final Duration pingInterval;

  /// How often the watchdog looks at the clock.
  final Duration checkInterval;

  /// Silence longer than this marks the link [ConnectionStatus.lost]. The
  /// socket stays open and pings continue, so a later pong restores
  /// [ConnectionStatus.connected] without the user reconnecting.
  final Duration timeout;

  RawDatagramSocket? _socket;

  List<InternetAddress> _resolved = const [];
  InternetAddress? _target;
  int? _targetPort;

  Timer? _pingTimer;
  Timer? _watchdog;

  DateTime? _lastPong;
  bool _tearingDown = false;
  bool _lost = false;

  final _status = StreamController<ConnectionStatus>.broadcast();
  final _incoming = StreamController<Message>.broadcast();

  @override
  Stream<ConnectionStatus> get status => _status.stream;

  @override
  Stream<Message> get incoming => _incoming.stream;

  @override
  Future<void> connect(ConnectionTarget target) async {
    if (_socket != null) _teardown();
    _tearingDown = false;
    _lost = false;
    _status.add(ConnectionStatus.connecting);

    try {
      final addresses = await InternetAddress.lookup(target.host);
      if (addresses.isEmpty) {
        throw SocketException('Could not resolve ${target.host}');
      }

      // Port 0 asks the OS for a free port.
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      _socket = socket;
      _resolved = addresses;
      _target = addresses.first;
      _targetPort = target.port;

      socket.listen(
        _onEvent,
        onError: (Object error, StackTrace _) => _onSocketGone(),
        onDone: _onSocketGone,
      );

      _lastPong = DateTime.now();
      _startPing();
      _startWatchdog();

      _status.add(ConnectionStatus.connected);
    } catch (_) {
      _teardown();
      _status.add(ConnectionStatus.disconnected);
      rethrow; // The casller needs the reason; connect_view shows it to the user.
    }
  }

  @override
  Future<void> disconnect() async {
    _teardown();
    _status.add(ConnectionStatus.disconnected);
  }

  void _teardown() {
    _tearingDown = true;

    _pingTimer?.cancel();
    _pingTimer = null;
    _watchdog?.cancel();
    _watchdog = null;

    _lastPong = null;
    _lost = false;
    _target = null;
    _targetPort = null;
    _resolved = const [];

    final socket = _socket;
    _socket = null;
    socket?.close();
  }

  void _onSocketGone() {
    if (_tearingDown || _socket == null) return;
    _teardown();
    _status.add(ConnectionStatus.lost);
  }

  @override
  Future<void> send(Message message) async {
    final socket = _socket;
    final address = _target;
    final port = _targetPort;

    if (socket == null || address == null || port == null) return;

    try {
      socket.send(utf8.encode(message.encode()), address, port);
    } on SocketException {
      // Closed between the guard above and here. A send is not the place to
      // tear the link down — the watchdog's job is to notice, and it will.
    }
  }

  @override
  Future<void> probe() async {
    if (_socket == null) return;
    // Timers may have been frozen while the app was in the background; the
    // silence that built up then says nothing about the link.
    if (!_lost) _lastPong = DateTime.now();
    await send(const Ping());
  }

  void _startPing() {
    _pingTimer = Timer.periodic(
      pingInterval,
      (_) => unawaited(send(const Ping())),
    );
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    while (true) {
      final datagram = _socket?.receive();
      if (datagram == null) break;
      _handle(datagram);
    }
  }

  void _handle(Datagram datagram) {
    if (!_resolved.contains(datagram.address)) return;
    if (datagram.port != _targetPort) return;

    final Message message;
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json is! Map<String, dynamic>) return;
      message = Message.fromJson(json);
    } on FormatException {
      return;
    }

    // The PC answers pings and says nothing else.
    if (message is! Pong) return;

    _lastPong = DateTime.now();
    if (_lost) {
      _lost = false;
      _status.add(ConnectionStatus.connected);
    }
    _incoming.add(message);
  }

  void _startWatchdog() {
    _watchdog = Timer.periodic(checkInterval, (_) {
      final last = _lastPong;
      if (last == null || _lost) return;

      if (DateTime.now().difference(last) > timeout) {
        // Keep the socket and the ping timer: the PC re-accepts any packet,
        // so the first pong that comes back restores the link by itself.
        _lost = true;
        _status.add(ConnectionStatus.lost);
      }
    });
  }
}
