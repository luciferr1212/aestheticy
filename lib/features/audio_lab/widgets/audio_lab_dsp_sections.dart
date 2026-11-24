import 'package:flutter/material.dart';

import 'package:aestheticy/audio/audio_models.dart';

/// Audio output device and WASAPI Exclusive Mode card for [AudioLabScreen].
class AudioLabOutputSection extends StatelessWidget {
  /// Available output devices.
  final List<AudioDevice> devices;

  /// Currently selected device ID.
  final String selectedDeviceId;

  /// Whether WASAPI Exclusive Mode is enabled.
  final bool isExclusive;

  /// Called when an output device is selected.
  final ValueChanged<String?> onSelectDevice;

  /// Called when refresh devices is pressed.
  final VoidCallback onRefreshDevices;

  /// Called when exclusive mode is toggled.
  final ValueChanged<bool> onToggleExclusive;

  /// Creates an [AudioLabOutputSection].
  const AudioLabOutputSection({
    super.key,
    required this.devices,
    required this.selectedDeviceId,
    required this.isExclusive,
    required this.onSelectDevice,
    required this.onRefreshDevices,
    required this.onToggleExclusive,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Audio Output',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.speaker, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedDeviceId,
                    items: devices.map((d) {
                      final displayName = d.name.trim().isNotEmpty ? d.name : d.id;
                      return DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: onSelectDevice,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh devices',
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefreshDevices,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('WASAPI Exclusive Mode'),
              subtitle: const Text(
                'Direct hardware output. Warning: Exclusive mode gives direct DAC control and will silence audio from other Windows apps.',
                style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
              ),
              value: isExclusive,
              onChanged: onToggleExclusive,
            ),
          ],
        ),
      ),
    );
  }
}

/// 10-band equalizer and preamp control card for [AudioLabScreen].
class AudioLabEqualizerSection extends StatelessWidget {
  static const List<String> _eqLabels = [
    '31',
    '62',
    '125',
    '250',
    '500',
    '1k',
    '2k',
    '4k',
    '8k',
    '16k',
  ];

  /// Whether the equalizer is enabled.
  final bool isEqEnabled;

  /// Gain values (in dB) for each of the 10 bands.
  final List<double> eqGains;

  /// Preamp gain in dB.
  final double preamp;

  /// Called when EQ enabled switch changes.
  final ValueChanged<bool> onToggleEq;

  /// Called when Reset button is pressed.
  final VoidCallback onResetEq;

  /// Called when preamp slider changes.
  final ValueChanged<double> onPreampChanged;

  /// Called when a band slider changes.
  final void Function(int index, double value) onBandChanged;

  /// Creates an [AudioLabEqualizerSection].
  const AudioLabEqualizerSection({
    super.key,
    required this.isEqEnabled,
    required this.eqGains,
    required this.preamp,
    required this.onToggleEq,
    required this.onResetEq,
    required this.onPreampChanged,
    required this.onBandChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.equalizer, size: 20),
                const SizedBox(width: 8),
                Text(
                  '10-Band Equalizer',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Switch(
                  value: isEqEnabled,
                  onChanged: onToggleEq,
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('eq_reset_button'),
                  onPressed: onResetEq,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Preamp slider
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    'Preamp: ${preamp.toStringAsFixed(1)} dB',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: preamp.clamp(-12.0, 12.0),
                    min: -12.0,
                    max: 12.0,
                    divisions: 48,
                    onChanged: isEqEnabled ? onPreampChanged : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 10 band sliders
            for (var i = 0; i < 10; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 55,
                      child: Text(
                        '${_eqLabels[i]} Hz',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: eqGains[i].clamp(-12.0, 12.0),
                        min: -12.0,
                        max: 12.0,
                        divisions: 48,
                        onChanged: isEqEnabled
                            ? (val) => onBandChanged(i, val)
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 55,
                      child: Text(
                        '${eqGains[i] >= 0 ? "+" : ""}${eqGains[i].toStringAsFixed(1)} dB',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ReplayGain mode selector card for [AudioLabScreen].
class AudioLabReplayGainSection extends StatelessWidget {
  /// Currently selected ReplayGain mode.
  final ReplayGainMode replayGainMode;

  /// Called when ReplayGain mode changes.
  final ValueChanged<ReplayGainMode?> onChanged;

  /// Creates an [AudioLabReplayGainSection].
  const AudioLabReplayGainSection({
    super.key,
    required this.replayGainMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            const Icon(Icons.graphic_eq, size: 20),
            const SizedBox(width: 8),
            Text(
              'ReplayGain Mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            DropdownButton<ReplayGainMode>(
              value: replayGainMode,
              items: const [
                DropdownMenuItem(
                  value: ReplayGainMode.off,
                  child: Text('Off'),
                ),
                DropdownMenuItem(
                  value: ReplayGainMode.track,
                  child: Text('Track'),
                ),
                DropdownMenuItem(
                  value: ReplayGainMode.album,
                  child: Text('Album'),
                ),
              ],
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
