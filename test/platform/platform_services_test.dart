import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/platform/noop_platform_services.dart';
import 'package:aestheticy/platform/platform_services.dart';
import 'package:aestheticy/platform/windows/smtc_media_session.dart';
import 'package:aestheticy/platform/windows/win32_sleep_inhibitor.dart';
import 'package:aestheticy/platform/windows/windows_file_association_service.dart';
import 'package:aestheticy/platform/windows/windows_tray_service.dart';
import 'package:aestheticy/platform/windows/windows_window_service.dart';

void main() {
  group('PlatformServices selector (S3)', () {
    test('selects Windows implementations when isWindowsOverride is true', () async {
      final services = PlatformServices.create(isWindowsOverride: true);
      expect(services.mediaSession, isA<SmtcMediaSession>());
      expect(services.sleepInhibitor, isA<Win32SleepInhibitor>());
      expect(services.tray, isA<WindowsTrayService>());
      expect(services.window, isA<WindowsWindowService>());
      expect(services.fileAssociation, isA<WindowsFileAssociationService>());
      expect(services.fileAssociation.isSupported, isFalse);
      expect(await services.fileAssociation.isRegistered('.mp3'), isFalse);
      expect(await services.fileAssociation.registerExtensions(['.mp3']), isFalse);
      expect(
        PlatformServices.createWindowService(isWindowsOverride: true),
        isA<WindowsWindowService>(),
      );
    });

    test('selects no-op fallbacks when isWindowsOverride is false', () async {
      final services = PlatformServices.create(isWindowsOverride: false);
      expect(services.mediaSession, isA<NoopMediaSessionService>());
      expect(services.sleepInhibitor, isA<NoopSleepInhibitor>());
      expect(services.tray, isA<NoopTrayService>());
      expect(services.window, isA<NoopWindowService>());
      expect(services.fileAssociation, isA<NoopFileAssociationService>());
      await services.openFolder('/tmp/nowhere');
      expect(
        PlatformServices.createWindowService(isWindowsOverride: false),
        isA<NoopWindowService>(),
      );

      // No-op methods complete safely without throwing
      await services.mediaSession.initialize();
      await services.mediaSession.disable();
      services.sleepInhibitor.acquire();
      services.sleepInhibitor.release();
      await services.tray.hide();
      await services.window.setPreventClose(true);
      await services.mediaSession.dispose();
      await services.tray.dispose();
      await services.window.dispose();
    });
  });
}
