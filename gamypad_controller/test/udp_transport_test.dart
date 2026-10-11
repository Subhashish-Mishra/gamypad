import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gamypad_controller/src/connection/connection_status.dart';
import 'package:gamypad_controller/src/connection/connection_target.dart';
import 'package:gamypad_controller/src/connection/udp_transport.dart';
import 'package:protocol/protocol.dart';

void main() {
  late RawDatagramSocket server;
  late UdpTransport transport;
  late List<ConnectionStatus> statuses;
  var answering = true;

  setUp(() async {
    answering = true;
    server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = server.receive();
      if (dg == null || !answering) return;
      server.send(utf8.encode(const Pong().encode()), dg.address, dg.port);
    });
    transport = UdpTransport(
      pingInterval: const Duration(milliseconds: 50),
      checkInterval: const Duration(milliseconds: 20),
      timeout: const Duration(milliseconds: 300),
    );
    statuses = [];
    transport.status.listen(statuses.add);
  });

  tearDown(() async {
    await transport.disconnect();
    server.close();
  });

  Future<void> settle(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  test('goes lost on silence and recovers by itself when the PC returns',
      () async {
    await transport.connect(UdpTarget(host: '127.0.0.1', port: server.port));
    await settle(150);
    expect(statuses.last, ConnectionStatus.connected);

    answering = false;
    await settle(500);
    expect(statuses.last, ConnectionStatus.lost);

    answering = true;
    await settle(200);
    expect(statuses.last, ConnectionStatus.connected);
  });

  test('stays connected while pongs keep arriving', () async {
    await transport.connect(UdpTarget(host: '127.0.0.1', port: server.port));
    await settle(700);
    expect(statuses, isNot(contains(ConnectionStatus.lost)));
  });
}
