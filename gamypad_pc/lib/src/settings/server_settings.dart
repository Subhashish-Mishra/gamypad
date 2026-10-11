import 'package:gamypad_pc/src/device/pad_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0 asks the OS for a free port; otherwise stay out of the privileged range.
const int randomPort = 0;
const int minPort = 1024;
const int maxPort = 65535;

bool isValidPort(int port) =>
    port == randomPort || (port >= minPort && port <= maxPort);

class ServerSettings {
  const ServerSettings({
    this.port = randomPort,
    this.padType = PadType.xbox360,
  });

  final int port;
  final PadType padType;

  ServerSettings copyWith({int? port, PadType? padType}) =>
      ServerSettings(port: port ?? this.port, padType: padType ?? this.padType);

  bool get isRandomPort => port == randomPort;
}

abstract interface class ServerSettingsRepository {
  Future<ServerSettings> load();
  Future<void> save(ServerSettings settings);
}

class SharedPreferencesServerSettingsRepository
    implements ServerSettingsRepository {
  const SharedPreferencesServerSettingsRepository();

  static const _portKey = 'server_port';
  static const _padTypeKey = 'pad_type';

  @override
  Future<ServerSettings> load() async {
    final pref = await SharedPreferences.getInstance();
    final port = pref.getInt(_portKey);
    final padType =
        PadType.values.asNameMap()[pref.getString(_padTypeKey)] ??
        PadType.xbox360;
    return ServerSettings(
      port: port != null && isValidPort(port) ? port : randomPort,
      padType: padType,
    );
  }

  @override
  Future<void> save(ServerSettings settings) async {
    final pref = await SharedPreferences.getInstance();
    await pref.setInt(_portKey, settings.port);
    await pref.setString(_padTypeKey, settings.padType.name);
  }
}
