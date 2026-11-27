import 'dart:io';

import 'file_association_service.dart';
import 'media_session_service.dart';
import 'noop_platform_services.dart';
import 'sleep_inhibitor.dart';
import 'tray_service.dart';
import 'window_service.dart';
import 'windows/folder_opener.dart';
import 'windows/smtc_media_session.dart';
import 'windows/win32_sleep_inhibitor.dart';
import 'windows/windows_file_association_service.dart';
import 'windows/windows_tray_service.dart';
import 'windows/windows_window_service.dart';

/// Platform-specific service bundle selected by host OS (`Platform.isWindows`),
/// with safe no-op fallbacks for non-Windows hosts (e.g. macOS/Linux CI).
class PlatformServices {
  final MediaSessionService mediaSession;
  final SleepInhibitor sleepInhibitor;
  final TrayService tray;
  final WindowService window;
  final FileAssociationService fileAssociation;
  final Future<void> Function(String path) openFolder;

  const PlatformServices({
    required this.mediaSession,
    required this.sleepInhibitor,
    required this.tray,
    required this.window,
    required this.fileAssociation,
    required this.openFolder,
  });

  /// Creates the platform service implementations for the current OS, or
  /// for the explicit [isWindowsOverride] in tests.
  factory PlatformServices.create({bool? isWindowsOverride}) {
    final useWindows = isWindowsOverride ?? Platform.isWindows;
    if (useWindows) {
      return PlatformServices(
        mediaSession: SmtcMediaSession(),
        sleepInhibitor: Win32SleepInhibitor(),
        tray: WindowsTrayService(),
        window: WindowsWindowService(),
        fileAssociation: WindowsFileAssociationService(),
        openFolder: openFolderInExplorer,
      );
    }
    return PlatformServices(
      mediaSession: NoopMediaSessionService(),
      sleepInhibitor: NoopSleepInhibitor(),
      tray: NoopTrayService(),
      window: NoopWindowService(),
      fileAssociation: NoopFileAssociationService(),
      openFolder: (_) async {},
    );
  }

  /// Creates a standalone [WindowService] for the current OS (or no-op fallback).
  static WindowService createWindowService({bool? isWindowsOverride}) {
    final useWindows = isWindowsOverride ?? Platform.isWindows;
    return useWindows ? WindowsWindowService() : NoopWindowService();
  }
}
