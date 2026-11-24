import 'package:flutter/material.dart';

import 'package:aestheticy/audio/audio_models.dart';

/// Stream metadata diagnostics table card for [AudioLabScreen].
class AudioLabStreamInfoSection extends StatelessWidget {
  /// Latest reported stream info, if any.
  final AudioStreamInfo? streamInfo;

  /// Creates an [AudioLabStreamInfoSection].
  const AudioLabStreamInfoSection({
    super.key,
    required this.streamInfo,
  });

  TableRow _buildInfoRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            value,
            style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = streamInfo;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Stream Info',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(2.0),
              },
              children: [
                _buildInfoRow('Codec', info?.codec ?? 'Unknown'),
                _buildInfoRow('Container', info?.container ?? 'Unknown'),
                _buildInfoRow(
                  'Sample Rate',
                  info?.sampleRate != null ? '${info!.sampleRate} Hz' : 'Unknown',
                ),
                _buildInfoRow(
                  'Bit Depth',
                  info?.bitDepth != null ? '${info!.bitDepth}-bit' : 'Unknown',
                ),
                _buildInfoRow(
                  'Channels',
                  info?.channels != null ? '${info!.channels}' : 'Unknown',
                ),
                _buildInfoRow(
                  'Bitrate',
                  info?.bitrateKbps != null
                      ? '${info!.bitrateKbps!.toStringAsFixed(1)} kbps'
                      : 'Unknown',
                ),
                _buildInfoRow(
                  'Lossless',
                  info?.isLossless == true
                      ? 'Yes'
                      : (info?.isLossless == false ? 'No' : 'Unknown'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrollable Audio Lab diagnostic event log card.
class AudioLabEventLogSection extends StatelessWidget {
  /// Recorded log entries (newest first).
  final List<String> logs;

  /// Callback copying the full log to clipboard.
  final VoidCallback onCopyLog;

  /// Creates an [AudioLabEventLogSection].
  const AudioLabEventLogSection({
    super.key,
    required this.logs,
    required this.onCopyLog,
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
                const Icon(Icons.terminal, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Event Log',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${logs.length} events',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onCopyLog,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Log'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No events logged yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: logs.length,
                      padding: const EdgeInsets.all(8.0),
                      itemBuilder: (context, i) {
                        final logText = logs[i];
                        final isErr = logText.contains('AudioError');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            logText,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: isErr
                                  ? Colors.redAccent
                                  : Colors.grey.shade300,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
