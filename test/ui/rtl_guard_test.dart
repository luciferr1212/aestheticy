import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/audio/audio_models.dart';
import 'package:aestheticy/audio/fake_audio_engine.dart';
import 'package:aestheticy/audio/playback_controller.dart';
import 'package:aestheticy/audio/playback_queue.dart';
import 'package:aestheticy/features/collections/user_collections.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/ui/glass/glass_blur_budget.dart';
import 'package:aestheticy/ui/glass/glass_quality.dart';
import 'package:aestheticy/ui/glass/glass_scope.dart';
import 'package:aestheticy/ui/library/album_detail_view.dart';
import 'package:aestheticy/ui/library/albums_view.dart';
import 'package:aestheticy/ui/library/artist_detail_view.dart';
import 'package:aestheticy/ui/library/artists_view.dart';
import 'package:aestheticy/ui/library/favorites_view.dart';
import 'package:aestheticy/ui/library/playlist_detail_view.dart';
import 'package:aestheticy/ui/library/playlists_view.dart';
import 'package:aestheticy/ui/library/recently_played_view.dart';
import 'package:aestheticy/ui/library/tracks_view.dart';
import 'package:aestheticy/ui/queue/queue_view.dart';
import 'package:aestheticy/ui/settings/settings_store.dart';
import 'package:aestheticy/ui/shell/app_navigator.dart';
import 'package:aestheticy/ui/theme/app_theme.dart';
import '../library/fake_library_repository.dart';

/// Allowlist of intentional physical layout tokens in lib/ui/.
///
/// Each entry defines the file path, the token, and the architectural rationale
/// why physical coordinates are required instead of directional ones.
class AllowedPhysicalToken {
  final String relativePath;
  final String token;
  final String rationale;

  const AllowedPhysicalToken({
    required this.relativePath,
    required this.token,
    required this.rationale,
  });
}

const List<AllowedPhysicalToken> kAllowedPhysicalTokens = [
  // 1. Gallery decorative background blobs
  AllowedPhysicalToken(
    relativePath: 'lib/ui/gallery/design_gallery_screen.dart',
    token: 'Positioned',
    rationale:
        'Visual design preview screen decorative background color blobs placed at fixed physical canvas coordinates.',
  ),
  // 2. Full screen view decorative glass shapes and full-width edge-to-edge bars
  AllowedPhysicalToken(
    relativePath: 'lib/ui/now_playing/full_screen_view.dart',
    token: 'Positioned',
    rationale:
        'Decorative floating glass shapes at fixed coordinates; edge-to-edge full width seek bar track; top bar; debug probe.',
  ),
  AllowedPhysicalToken(
    relativePath: 'lib/ui/now_playing/full_screen_view.dart',
    token: 'Alignment.centerRight',
    rationale:
        'Physical seek bar fraction fill alignment explicitly handled per text direction.',
  ),
  AllowedPhysicalToken(
    relativePath: 'lib/ui/now_playing/full_screen_view.dart',
    token: 'Alignment.centerLeft',
    rationale:
        'Physical seek bar fraction fill alignment explicitly handled per text direction.',
  ),
  // 3. Lyrics view
  AllowedPhysicalToken(
    relativePath: 'lib/ui/lyrics/lyrics_view.dart',
    token: 'Positioned',
    rationale:
        'Full-width top notice bar spanning left: 0, right: 0 across viewport.',
  ),
  AllowedPhysicalToken(
    relativePath: 'lib/ui/lyrics/lyrics_view.dart',
    token: 'Alignment.centerRight',
    rationale:
        'Physical shader gradient sweep coordinates and per-line Arabic/Latin text direction alignment.',
  ),
  AllowedPhysicalToken(
    relativePath: 'lib/ui/lyrics/lyrics_view.dart',
    token: 'Alignment.centerLeft',
    rationale:
        'Physical shader gradient sweep coordinates and per-line Arabic/Latin text direction alignment.',
  ),
  // 4. Volume HUD overlay
  AllowedPhysicalToken(
    relativePath: 'lib/ui/shell/volume_hud.dart',
    token: 'Positioned',
    rationale:
        'Full-width top volume HUD overlay spanning left: 12, right: 12 symmetrically.',
  ),
];

void main() {
  group('RTL Guards: Codebase Token and Icon Scanners', () {
    test('No unmirrored directional icons in lib/ui/', () {
      final uiDir = Directory('lib/ui');
      expect(uiDir.existsSync(), isTrue, reason: 'lib/ui directory must exist');

      final dartFiles = uiDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final directionalIconPattern = RegExp(
        r'Icons\.(arrow_back|arrow_forward|chevron_left|chevron_right|navigate_before|navigate_next|arrow_left|arrow_right)\b',
      );

      final violations = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final match = directionalIconPattern.firstMatch(line);
          if (match != null) {
            // Check if line or adjacent line has matchTextDirection: true
            final contextWindow = [
              if (i > 0) lines[i - 1],
              line,
              if (i + 1 < lines.length) lines[i + 1],
              if (i + 2 < lines.length) lines[i + 2],
            ].join(' ');

            if (!contextWindow.contains('matchTextDirection: true') &&
                !contextWindow.contains('Icons.auto_mirrored')) {
              violations.add(
                '${file.path}:${i + 1} uses unmirrored directional icon "${match.group(0)}" without matchTextDirection or auto_mirrored',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'All directional icons in lib/ui/ must use Icons.auto_mirrored or matchTextDirection: true:\n${violations.join('\n')}',
      );
    });

    test('No accidental physical padding or alignment in lib/ui/', () {
      final uiDir = Directory('lib/ui');
      final dartFiles = uiDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final physicalTokenPatterns = [
        RegExp(r'EdgeInsets\.only\([^)]*\b(left|right)\s*:'),
        RegExp(r'EdgeInsets\.fromLTRB\b'),
        RegExp(r'Alignment\.center(Left|Right)\b'),
        RegExp(r'Positioned\([^)]*\b(left|right)\s*:'),
      ];

      final violations = <String>[];

      for (final file in dartFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        final lines = file.readAsLinesSync();

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];

          for (final pattern in physicalTokenPatterns) {
            final match = pattern.firstMatch(line);
            if (match != null) {
              final matchedToken = match.group(0)!;

              // Check against allowlist
              final isAllowed = kAllowedPhysicalTokens.any((allowed) {
                return normalizedPath.endsWith(allowed.relativePath) &&
                    matchedToken.contains(allowed.token);
              });

              if (!isAllowed) {
                violations.add(
                  '$normalizedPath:${i + 1} contains unapproved physical layout token "$matchedToken"',
                );
              }
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Accidental physical tokens found in lib/ui/. Use EdgeInsetsDirectional / AlignmentDirectional or document intentional physical tokens in kAllowedPhysicalTokens:\n${violations.join('\n')}',
      );
    });
  });

  group('RTL Guards: List Views Render Cleanly in RTL at 1280x800', () {
    late Directory tempDir;
    late FakeLibraryRepository repo;
    late UserCollections collections;
    late FakeAudioEngine engine;
    late PlaybackQueue queue;
    late PlaybackController controller;
    late SettingsStore settingsStore;
    late AppNavigator navigator;

    final sampleTrack = Track(
      id: 1,
      folderId: 1,
      path: 'C:/Music/test_song.mp3',
      durationMs: 240000,
      title: 'أغنية عربية تجريبية',
      artist: 'فنان عربي تجريبي',
      album: 'ألبوم تجريبي',
      mtimeMs: 0,
      sizeBytes: 4000,
      addedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    setUp(() async {
      GlassBlurBudget.instance.resetForTesting();
      tempDir = Directory.systemTemp.createTempSync('rtl_guard_test_');
      repo = FakeLibraryRepository();
      await repo.addFolder('C:/Music');
      await repo.upsertTracks([sampleTrack]);

      collections = UserCollections(repository: repo);
      await collections.init();
      await collections.toggleFavorite(sampleTrack.path);

      engine = FakeAudioEngine();
      await engine.init();

      queue = PlaybackQueue();
      controller = PlaybackController(engine: engine, queue: queue);
      await controller.init();

      settingsStore = SettingsStore(directory: tempDir);
      await settingsStore.init();

      navigator = AppNavigator();
    });

    tearDown(() async {
      await controller.dispose();
      collections.dispose();
      await settingsStore.flush();
      settingsStore.dispose();
      await engine.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    void setupDesktopViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    Widget buildRtlContainer(Widget child) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: GlassScope(
            controller: GlassController(quality: GlassQuality.full),
            child: UserCollectionsScope(
              collections: collections,
              child: Scaffold(
                body: child,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'TracksView renders in RTL without layout overflows',
      (tester) async {
        setupDesktopViewport(tester);
        await tester.pumpWidget(
          buildRtlContainer(
            TracksView(
              repository: repo,
              controller: controller,
              settingsStore: settingsStore,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'AlbumsView renders in RTL without layout overflows',
      (tester) async {
        setupDesktopViewport(tester);
        await tester.pumpWidget(
          buildRtlContainer(
            AlbumsView(
              repository: repo,
              navigator: navigator,
              settingsStore: settingsStore,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'ArtistsView renders in RTL without layout overflows',
      (tester) async {
        setupDesktopViewport(tester);
        await tester.pumpWidget(
          buildRtlContainer(
            ArtistsView(
              repository: repo,
              navigator: navigator,
              settingsStore: settingsStore,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'AlbumDetailView renders in RTL without layout overflows',
      (tester) async {
        setupDesktopViewport(tester);
        await tester.pumpWidget(
          buildRtlContainer(
            AlbumDetailView(
              album: AlbumSummary(
                album: sampleTrack.album!,
                albumArtist: sampleTrack.artist!,
                trackCount: 1,
              ),
              repository: repo,
              controller: controller,
              navigator: navigator,
              settingsStore: settingsStore,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'ArtistDetailView renders in RTL without layout overflows',
      (tester) async {
        setupDesktopViewport(tester);
        await tester.pumpWidget(
          buildRtlContainer(
            ArtistDetailView(
              artist: ArtistSummary(
                name: sampleTrack.artist!,
                trackCount: 1,
                albumCount: 1,
              ),
              repository: repo,
              controller: controller,
              navigator: navigator,
              settingsStore: settingsStore,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'PlaylistsView and PlaylistDetailView render in RTL without layout overflows',
      (tester) async {
        setupDesktopViewport(tester);
        final playlist = await repo.createPlaylist('قائمة عربية');
        await tester.pumpWidget(
          buildRtlContainer(
            PlaylistsView(
              collections: collections,
              repository: repo,
              navigator: navigator,
              settingsStore: settingsStore,
              controller: controller,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          buildRtlContainer(
            PlaylistDetailView(
              playlistId: playlist.id,
              repository: repo,
              collections: collections,
              navigator: navigator,
              settingsStore: settingsStore,
              controller: controller,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'FavoritesView and RecentlyPlayedView render in RTL without layout overflows',
      (tester) async {
        setupDesktopViewport(tester);
        await tester.pumpWidget(
          buildRtlContainer(
            FavoritesView(
              repository: repo,
              collections: collections,
              controller: controller,
              settingsStore: settingsStore,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          buildRtlContainer(
            RecentlyPlayedView(
              repository: repo,
              collections: collections,
              controller: controller,
              settingsStore: settingsStore,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'QueueView renders in RTL without layout overflows',
      (tester) async {
        setupDesktopViewport(tester);
        await controller.playQueue([
          const AudioSource(
            'track1.flac',
            extras: {'title': 'مسار رقم واحد', 'artist': 'فنان عربي'},
          ),
        ], startIndex: 0);

        await tester.pumpWidget(
          buildRtlContainer(
            QueueView(
              controller: controller,
              navigator: navigator,
              settingsStore: settingsStore,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
