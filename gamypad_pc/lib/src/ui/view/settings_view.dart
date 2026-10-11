import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gamypad_pc/src/device/pad_type.dart';
import 'package:gamypad_pc/src/settings/server_settings.dart';
import 'package:gamypad_pc/src/ui/state/notifier.dart';
import 'package:gamypad_pc/src/ui/state/server_settings_controller.dart';
import 'package:gamypad_pc/src/ui/widgets/setting/section_label.dart';
import 'package:gamypad_pc/src/ui/widgets/setting/settings_card.dart';
import 'package:gamypad_pc/src/utils/app_theme.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _formKey = GlobalKey<FormState>();
  final _port = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  String? _validate(String? text) {
    final port = int.tryParse((text ?? '').trim());
    if (port == null) return 'Enter a number';
    if (!isValidPort(port)) return '0 for random, or $minPort-$maxPort';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final port = int.parse(_port.text.trim());
    await ref.read(serverSettingsControllerProvider.notifier).setPort(port);
    if (!mounted) return;
    final running = ref.read(serverControllerProvider).isRunning;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          running ? 'Saved. Restart the server to apply.' : 'Saved.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(serverSettingsControllerProvider);
    final running = ref.watch(serverControllerProvider).isRunning;

    if (!_loaded && settings.hasValue) {
      _loaded = true;
      _port.text = '${settings.requireValue.port}';
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              children: [
                _PadTypeSection(
                  selected: settings.value?.padType ?? PadType.xbox360,
                  enabled: settings.hasValue,
                  onChanged: (type) => ref
                      .read(serverSettingsControllerProvider.notifier)
                      .setPadType(type),
                ),
                const SizedBox(height: 24),
                const SectionLabel('SERVER'),
                const SizedBox(height: 12),
                SettingsCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Server port',
                          style: TextStyle(
                            color: ColorPalette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Port the PC listens on. 0 picks a random free port '
                          'each time the server starts.',
                          style: TextStyle(
                            color: ColorPalette.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _port,
                          enabled: settings.hasValue,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: _validate,
                          onFieldSubmitted: (_) => _save(),
                          style: const TextStyle(
                            color: ColorPalette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                          decoration: const InputDecoration(
                            hintText: '0',
                            hintStyle: TextStyle(
                              color: ColorPalette.muted,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (running) ...[
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      'The server is running — changes (including the controller type) apply on next start.',
                      style: TextStyle(color: ColorPalette.muted, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: settings.hasValue ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ColorPalette.accent,
                      disabledBackgroundColor: ColorPalette.surface,
                      foregroundColor: Colors.black,
                      disabledForegroundColor: ColorPalette.muted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'SAVE',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What each controller type is, shown under the selector.
const padTypeDescriptions = <PadType, String>{
  PadType.xbox360:
      'Presents an Xbox 360 controller. Works in every game and needs no '
      'extra setup. Has no gyro, so the phone\'s Motion mode only reaches '
      'tools that read a separate motion device.',
  PadType.playstation:
      'Presents a Sony DualSense as a real HID device, so browsers (WebHID), '
      'Steam and SDL games see a genuine PlayStation controller with gyro and '
      'accelerometer. Needs access to /dev/uhid — re-run the installer once, '
      'then log out and back in.',
};

const _padTypeLabels = <PadType, String>{
  PadType.xbox360: 'XBOX 360',
  PadType.playstation: 'PLAYSTATION',
};

class _PadTypeSection extends StatelessWidget {
  const _PadTypeSection({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final PadType selected;
  final bool enabled;
  final ValueChanged<PadType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'CONTROLLER TYPE',
          style: TextStyle(
            color: ColorPalette.muted,
            fontSize: 10,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<PadType>(
          key: const ValueKey('pad-type'),
          showSelectedIcon: false,
          segments: [
            for (final type in PadType.values)
              ButtonSegment(
                value: type,
                label: Text(
                  _padTypeLabels[type]!,
                  style: const TextStyle(letterSpacing: 2, fontSize: 12),
                ),
              ),
          ],
          selected: {selected},
          onSelectionChanged: enabled
              ? (selection) => onChanged(selection.single)
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          padTypeDescriptions[selected]!,
          key: const ValueKey('pad-type-description'),
          style: const TextStyle(
            color: ColorPalette.muted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
