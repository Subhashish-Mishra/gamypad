import 'package:flutter_test/flutter_test.dart';
import 'package:gamypad_pc/src/device/pad_type.dart';
import 'package:gamypad_pc/src/settings/server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('port validation', () {
    expect(isValidPort(0), isTrue);
    expect(isValidPort(1024), isTrue);
    expect(isValidPort(65535), isTrue);
    expect(isValidPort(80), isFalse);
    expect(isValidPort(65536), isFalse);
    expect(isValidPort(-1), isFalse);
  });

  test(
    'defaults to random port, persists and rejects bad stored values',
    () async {
      SharedPreferences.setMockInitialValues({});
      const repo = SharedPreferencesServerSettingsRepository();
      expect((await repo.load()).isRandomPort, isTrue);

      await repo.save(const ServerSettings(port: 5000));
      expect((await repo.load()).port, 5000);

      SharedPreferences.setMockInitialValues({'server_port': 80});
      expect((await repo.load()).isRandomPort, isTrue);
    },
  );

  test('the pad type defaults to Xbox 360 and persists', () async {
    SharedPreferences.setMockInitialValues({});
    const repo = SharedPreferencesServerSettingsRepository();
    expect((await repo.load()).padType, PadType.xbox360);

    await repo.save(const ServerSettings(padType: PadType.playstation));
    final loaded = await repo.load();
    expect(loaded.padType, PadType.playstation);
    expect(loaded.isRandomPort, isTrue); // saving the type kept the port
  });

  test('an unknown stored pad type falls back to Xbox 360', () async {
    SharedPreferences.setMockInitialValues({'pad_type': 'gamecube'});
    const repo = SharedPreferencesServerSettingsRepository();
    expect((await repo.load()).padType, PadType.xbox360);
  });

  test('changing one setting keeps the other', () {
    const s = ServerSettings(port: 5000, padType: PadType.playstation);
    expect(s.copyWith(port: 6000).padType, PadType.playstation);
    expect(s.copyWith(padType: PadType.xbox360).port, 5000);
  });
}
