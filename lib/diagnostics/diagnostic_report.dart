import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';

/// Pure function building a privacy-scrubbed diagnostic text report.
String buildDiagnosticReport({
  String appName = 'Aestheticy',
  String appVersion = '1.0.0',
  required String osVersion,
  required String dartVersion,
  required String engineName,
  required EngineCapabilities capabilities,
  required String outputDeviceName,
  required bool exclusiveMode,
  required bool eqEnabled,
  required ReplayGainMode replayGainMode,
  required GlassQuality glassQuality,
  required String language,
  required String textScale,
  required int trackCount,
  required int albumCount,
  required int artistCount,
  required int folderCount,
  required int schemaVersion,
  bool resumeSession = true,
  String? sessionRestoreSummary,
  required int playEventsCount,
  String mediaSessionStatus = 'active',
  bool trayEnabled = false,
  bool sleepPreventionEnabled = true,
  String closeBehavior = 'quit',
  required List<String> logLines,
  String? userNameToScrub,
}) {
  final sb = StringBuffer();

  sb.writeln('=== $appName Diagnostic Report ===');
  sb.writeln('App Version: $appVersion');
  sb.writeln('OS Version: $osVersion');
  sb.writeln('Dart Runtime: $dartVersion');
  sb.writeln('Audio Engine: $engineName');
  sb.writeln('Capabilities: $capabilities');
  sb.writeln('Output Device: $outputDeviceName');
  sb.writeln('Exclusive Mode: $exclusiveMode');
  sb.writeln('EQ Enabled: $eqEnabled');
  sb.writeln('ReplayGain Mode: ${replayGainMode.name}');
  sb.writeln('Resume Session: $resumeSession');
  sb.writeln('Glass Quality: ${glassQuality.name}');
  sb.writeln('Language: $language');
  sb.writeln('Text Scale: $textScale');
  sb.writeln('Library Counts: $trackCount tracks, $albumCount albums, $artistCount artists, $folderCount folders');
  sb.writeln('Schema Version: $schemaVersion');
  sb.writeln('Play Events Count: $playEventsCount');
  sb.writeln('Media Session: $mediaSessionStatus');
  sb.writeln('Tray: ${trayEnabled ? 'on' : 'off'}');
  sb.writeln('Sleep Prevention: ${sleepPreventionEnabled ? 'on' : 'off'}');
  sb.writeln('Close Behavior: $closeBehavior');
  if (sessionRestoreSummary != null) {
    sb.writeln('Session Restore: $sessionRestoreSummary');
  }
  sb.writeln();
  sb.writeln('=== Recent Logs (Last 100 lines) ===');

  final recentLogs = logLines.length > 100
      ? logLines.sublist(logLines.length - 100)
      : logLines;

  for (final line in recentLogs) {
    final sanitized = AppLogger.sanitizeMessage(line, userName: userNameToScrub);
    sb.writeln(sanitized);
  }

  var fullReport = sb.toString();

  // Final privacy enforcement sweep: scrub user name and any stray paths
  if (userNameToScrub != null && userNameToScrub.trim().isNotEmpty) {
    fullReport = fullReport.replaceAll(userNameToScrub.trim(), '[REDACTED_USER]');
  }

  // Scrub any full paths that might have been interpolated
  fullReport = fullReport.replaceAllMapped(
    RegExp(r'(?:[a-zA-Z]:[\\/]|file:\/\/\/?|\/)[^\s"<>]+[\\/]([^\s\\/]+)'),
    (m) => m.group(1) ?? '',
  );

  return fullReport;
}
