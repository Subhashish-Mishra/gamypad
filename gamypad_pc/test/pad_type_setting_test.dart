import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamypad_pc/src/device/pad_type.dart';
import 'package:gamypad_pc/src/settings/server_settings.dart';
import 'package:gamypad_pc/src/ui/state/server_settings_controller.dart';
import 'package:gamypad_pc/src/ui/view/settings_view.dart';

class _MemoryRepo implements ServerSettingsRepository {
  ServerSettings saved = const ServerSettings();

  @override
  Future<ServerSettings> load() async => saved;
  @override
  Future<void> save(ServerSettings settings) async => saved = settings;
}

void main() {
  late _MemoryRepo repo;

  Future<void> open(WidgetTester tester) async {
    repo = _MemoryRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [serverSettingsRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: SettingsView()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers both controller types, Xbox 360 selected by default', (
    tester,
  ) async {
    await open(tester);

    final selector = tester.widget<SegmentedButton<PadType>>(
      find.byKey(const ValueKey('pad-type')),
    );
    expect(selector.segments.map((s) => s.value), PadType.values);
    expect(selector.selected, {PadType.xbox360});
    expect(selector.multiSelectionEnabled, isFalse);
    expect(find.text(padTypeDescriptions[PadType.xbox360]!), findsOneWidget);
  });

  testWidgets('picking PlayStation saves it and swaps the description', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('PLAYSTATION'));
    await tester.pumpAndSettle();

    expect(repo.saved.padType, PadType.playstation);
    expect(
      find.text(padTypeDescriptions[PadType.playstation]!),
      findsOneWidget,
    );
    expect(find.text(padTypeDescriptions[PadType.xbox360]!), findsNothing);
  });

  testWidgets('choosing a pad type does not disturb the saved port', (
    tester,
  ) async {
    await open(tester);
    repo.saved = const ServerSettings(port: 5000);
    // Reload so the controller sees the stored port.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsView)),
    );
    container.invalidate(serverSettingsControllerProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.text('PLAYSTATION'));
    await tester.pumpAndSettle();

    expect(repo.saved.port, 5000);
    expect(repo.saved.padType, PadType.playstation);
  });
}
