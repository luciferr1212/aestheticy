import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/diagnostics/diagnostic_report.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';

void main() {
  const testCaps = EngineCapabilities(
    exclusiveMode: false,
    gapless: true,
    equalizer: true,
    replayGain: true,
  );

  group('Diagnostic Report Tests (S6)', () {
    test('buildDiagnosticReport includes all expected fields', () {
      final report = buildDiagnosticReport(
        appName: 'Aestheticy',
        appVersion: '1.2.3',
        osVersion: 'Windows 10 Pro 22H2',
        dartVersion: '3.5.0',
        engineName: 'MpvAudioEngine',
        capabilities: testCaps,
        outputDeviceName: 'Speakers (Realtek)',
        exclusiveMode: false,
        eqEnabled: true,
        replayGainMode: ReplayGainMode.track,
        glassQuality: GlassQuality.full,
        language: 'en',
        textScale: 'normal',
        trackCount: 1500,
        albumCount: 120,
        artistCount: 85,
        folderCount: 2,
        schemaVersion: 3,
        resumeSession: true,
        sessionRestoreSummary: 'restored 10 items, dropped 0',
        playEventsCount: 42,
        logLines: [
          '2026-11-06T00:00:00.000Z [INFO] [App] Engine started',
          '2026-11-06T00:01:00.000Z [INFO] [Playback] Playing track',
        ],
      );

      expect(report, contains('=== Aestheticy Diagnostic Report ==='));
      expect(report, contains('App Version: 1.2.3'));
      expect(report, contains('OS Version: Windows 10 Pro 22H2'));
      expect(report, contains('Dart Runtime: 3.5.0'));
      expect(report, contains('Audio Engine: MpvAudioEngine'));
      expect(report, contains('Output Device: Speakers (Realtek)'));
      expect(report, contains('ReplayGain Mode: track'));
      expect(report, contains('Resume Session: true'));
      expect(report, contains('Glass Quality: full'));
      expect(report, contains('Language: en'));
      expect(report, contains('Text Scale: normal'));
      expect(report, contains('1500 tracks, 120 albums, 85 artists, 2 folders'));
      expect(report, contains('Schema Version: 3'));
      expect(report, contains('Play Events Count: 42'));
      expect(report, contains('Media Session: active'));
      expect(report, contains('Tray: off'));
      expect(report, contains('Sleep Prevention: on'));
      expect(report, contains('Close Behavior: quit'));
      expect(report, contains('Lyrics Source: localThenOnline'));
      expect(report, contains('Session Restore: restored 10 items, dropped 0'));
      expect(report, contains('=== Recent Logs (Last 100 lines) ==='));
      expect(report, contains('Engine started'));
      expect(report, contains('Playing track'));
    });

    test('buildDiagnosticReport strictly enforces privacy rules (no user name, no full paths, redacts tokens)', () {
      const rawUser = 'mido_super_user';
      final logLines = [
        'User logged in: mido_super_user',
        'Loading file: C:\\Users\\mido_super_user\\Music\\SecretSong.flac',
        'Auth header with token=top_secret_token_12345',
        'Api key: secret_api_key_abcde',
      ];

      final report = buildDiagnosticReport(
        osVersion: 'Windows 10',
        dartVersion: '3.5.0',
        engineName: 'FakeAudioEngine',
        capabilities: testCaps,
        outputDeviceName: 'Default',
        exclusiveMode: false,
        eqEnabled: false,
        replayGainMode: ReplayGainMode.off,
        glassQuality: GlassQuality.off,
        language: 'en',
        textScale: 'normal',
        trackCount: 10,
        albumCount: 1,
        artistCount: 1,
        folderCount: 1,
        schemaVersion: 3,
        playEventsCount: 5,
        logLines: logLines,
        userNameToScrub: rawUser,
      );

      // Verify user name is never present
      expect(report.contains(rawUser), isFalse);
      expect(report, contains('[REDACTED_USER]'));

      // Verify full paths are stripped to filename only
      expect(report.contains(r'C:\Users\'), isFalse);
      expect(report, contains('SecretSong.flac'));

      // Verify tokens and keys are redacted
      expect(report.contains('top_secret_token_12345'), isFalse);
      expect(report.contains('secret_api_key_abcde'), isFalse);
      expect(report, contains('[REDACTED]'));
    });

    test('buildDiagnosticReport caps log lines to at most 100', () {
      final lines = List.generate(150, (i) => 'Log line #$i');

      final report = buildDiagnosticReport(
        osVersion: 'Windows 10',
        dartVersion: '3.5.0',
        engineName: 'FakeAudioEngine',
        capabilities: testCaps,
        outputDeviceName: 'Default',
        exclusiveMode: false,
        eqEnabled: false,
        replayGainMode: ReplayGainMode.off,
        glassQuality: GlassQuality.off,
        language: 'en',
        textScale: 'normal',
        trackCount: 10,
        albumCount: 1,
        artistCount: 1,
        folderCount: 1,
        schemaVersion: 3,
        playEventsCount: 5,
        logLines: lines,
      );

      // Earlier lines 0-49 should be pruned; only last 100 (50-149) should remain
      expect(report.contains('Log line #0'), isFalse);
      expect(report.contains('Log line #49'), isFalse);
      expect(report.contains('Log line #50'), isTrue);
      expect(report.contains('Log line #149'), isTrue);
    });

    test('buildDiagnosticReport includes custom integration status lines without paths or names', () {
      final report = buildDiagnosticReport(
        osVersion: 'Windows 11',
        dartVersion: '3.5.0',
        engineName: 'MpvAudioEngine',
        capabilities: testCaps,
        outputDeviceName: 'Default',
        exclusiveMode: false,
        eqEnabled: false,
        replayGainMode: ReplayGainMode.off,
        glassQuality: GlassQuality.off,
        language: 'en',
        textScale: 'normal',
        trackCount: 0,
        albumCount: 0,
        artistCount: 0,
        folderCount: 0,
        schemaVersion: 4,
        playEventsCount: 0,
        mediaSessionStatus: 'unavailable',
        trayEnabled: true,
        sleepPreventionEnabled: false,
        closeBehavior: 'tray',
        logLines: [],
      );

      expect(report, contains('Media Session: unavailable'));
      expect(report, contains('Tray: on'));
      expect(report, contains('Sleep Prevention: off'));
      expect(report, contains('Close Behavior: tray'));
      expect(report.contains(r'C:\'), isFalse);
    });
  });
}
