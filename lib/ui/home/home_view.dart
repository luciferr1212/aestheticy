import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/playback_controller.dart';
import '../../features/session/session_restorer.dart';
import '../../features/session/session_store.dart';
import '../../library/album_identity.dart';
import '../../library/library_repository.dart';
import '../../library/track_audio_source_mapper.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../library/library_data_cache.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'home_controller.dart';
import 'home_greeting.dart';
import 'home_models.dart';
import 'widgets/home_hero_card.dart';
import 'widgets/home_media_row.dart';

/// Calm, uncluttered 3-element Home screen:
/// 1) Personalized time-of-day greeting + Now Playing / Resume hero card
/// 2) "Continue listening" horizontal row of recent albums
/// 3) One daily rotating highlight row with title & "why this row" caption
class HomeView extends StatefulWidget {
  /// Library storage repository.
  final LibraryRepository repository;

  /// Playback controller.
  final PlaybackController controller;

  /// Persistent user settings store.
  final SettingsStore settingsStore;

  /// Navigation coordinator.
  final AppNavigator navigator;

  /// Shared library data cache.
  final LibraryDataCache dataCache;

  /// Optional session store for resuming the last queue.
  final SessionStore? sessionStore;

  /// Optional injected [HomeController] (intended for tests).
  final HomeController? homeController;

  /// Optional clock override for greeting and rotation tests.
  final DateTime Function()? clock;

  /// Creates a [HomeView].
  const HomeView({
    super.key,
    required this.repository,
    required this.controller,
    required this.settingsStore,
    required this.navigator,
    required this.dataCache,
    this.sessionStore,
    this.homeController,
    this.clock,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late final HomeController _homeController;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (widget.homeController != null) {
      _homeController = widget.homeController!;
      _ownsController = false;
    } else {
      _homeController = HomeController(
        repository: widget.repository,
        playbackController: widget.controller,
        dataCache: widget.dataCache,
        sessionStore: widget.sessionStore,
        clock: widget.clock,
      );
      _ownsController = true;
    }
    unawaited(_homeController.refresh());
  }

  @override
  void dispose() {
    if (_ownsController) {
      _homeController.dispose();
    }
    super.dispose();
  }

  Future<void> _resumeSavedSession() async {
    final store = widget.sessionStore;
    if (store == null) return;
    final res = await restoreSession(
      controller: widget.controller,
      sessionStore: store,
      settingsStore: widget.settingsStore,
    );
    if (res.restoredCount > 0) {
      await widget.controller.play();
    }
  }

  String _rotatingTitleKey(HomeRotatingRowKind kind) {
    return switch (kind) {
      HomeRotatingRowKind.recentlyAdded => 'home.row.recentlyAdded',
      HomeRotatingRowKind.forgottenFavorites => 'home.row.forgottenFavorites',
      HomeRotatingRowKind.onThisDay => 'home.row.onThisDay',
      HomeRotatingRowKind.mostPlayedThisMonth =>
        'home.row.mostPlayedThisMonth',
    };
  }

  String _rotatingWhyKey(HomeRotatingRowKind kind) {
    return switch (kind) {
      HomeRotatingRowKind.recentlyAdded => 'home.row.recentlyAddedWhy',
      HomeRotatingRowKind.forgottenFavorites =>
        'home.row.forgottenFavoritesWhy',
      HomeRotatingRowKind.onThisDay => 'home.row.onThisDayWhy',
      HomeRotatingRowKind.mostPlayedThisMonth =>
        'home.row.mostPlayedThisMonthWhy',
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.settingsStore,
        _homeController,
      ]),
      builder: (context, _) {
        final settings = widget.settingsStore.settings;
        final reduceMotion = settings.reduceMotion;
        final now = _homeController.clock();
        final greeting = formatHomeGreeting(
          now,
          userName: settings.userName,
          language: settings.language,
        );
        final continueAlbums = _homeController.continueListening;
        final rotating = _homeController.rotatingRow;
        final showEmptyHistory =
            _homeController.hasLoaded && _homeController.isHistoryEmpty;

        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPad = constraints.maxWidth < 720 ? 20.0 : 32.0;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPad,
                vertical: AppSpacing.s24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Element 1: Greeting + Hero card
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.s12,
                        runSpacing: AppSpacing.s8,
                        children: [
                          Text(
                            greeting,
                            key: const Key('home_greeting_text'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: textDirectionFor(greeting),
                            style: AppTypography.display.copyWith(
                              color: AppColors.text,
                            ),
                          ),
                          GlassPillButton(
                            key: const Key('home_wrapped_button'),
                            size: GlassButtonSize.small,
                            leadingIcon: Icons.auto_awesome_outlined,
                            label: context.t('home.wrappedButton'),
                            onPressed: widget.navigator.openWrapped,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      HomeHeroCard(
                        nowPlaying: _homeController.nowPlaying,
                        resumeSession: _homeController.resumeSession,
                        playbackController: widget.controller,
                        reduceMotion: reduceMotion,
                        onOpenNowPlaying: widget.navigator.openNowPlaying,
                        onResumeSession: _resumeSavedSession,
                        onBrowseAlbums: () =>
                            widget.navigator.navigateTo(AppDestination.albums),
                      ),

                      if (continueAlbums.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s32),
                        // Element 2: Continue listening
                        HomeMediaRow.albums(
                          key: const Key('home_continue_listening_row'),
                          title: context.t('home.continueListening'),
                          albums: continueAlbums,
                          reduceMotion: reduceMotion,
                          onAlbumTap: (album) =>
                              widget.navigator.openAlbumDetail(
                            AlbumIdentity.forSummary(album),
                            album: album,
                          ),
                        ),
                      ],

                      if (rotating != null && !rotating.isEmpty) ...[
                        const SizedBox(height: AppSpacing.s32),
                        // Element 3: Single daily rotating row
                        if (rotating.isAlbumRow)
                          HomeMediaRow.albums(
                            key: const Key('home_rotating_row'),
                            title: context.t(_rotatingTitleKey(rotating.kind)),
                            whyCaption:
                                context.t(_rotatingWhyKey(rotating.kind)),
                            albums: rotating.albums,
                            reduceMotion: reduceMotion,
                            onAlbumTap: (album) =>
                                widget.navigator.openAlbumDetail(
                              AlbumIdentity.forSummary(album),
                              album: album,
                            ),
                          )
                        else
                          HomeMediaRow.tracks(
                            key: const Key('home_rotating_row'),
                            title: context.t(_rotatingTitleKey(rotating.kind)),
                            whyCaption:
                                context.t(_rotatingWhyKey(rotating.kind)),
                            tracks: rotating.tracks,
                            reduceMotion: reduceMotion,
                            onTrackTap: (track) {
                              unawaited(
                                widget.controller.playQueue(
                                  [track.toAudioSource()],
                                ),
                              );
                            },
                          ),
                      ],

                      if (showEmptyHistory) ...[
                        const SizedBox(height: AppSpacing.s32),
                        Container(
                          key: const Key('home_empty_history'),
                          padding: const EdgeInsets.all(AppSpacing.s24),
                          decoration: BoxDecoration(
                            color: AppColors.fillControl,
                            borderRadius: BorderRadius.circular(AppSpacing.r16),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.t('home.emptyHistoryTitle'),
                                style: AppTypography.title
                                    .copyWith(color: AppColors.text),
                              ),
                              const SizedBox(height: AppSpacing.s8),
                              Text(
                                context.t('home.emptyHistorySubtitle'),
                                style: AppTypography.body.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s16),
                              GlassPillButton(
                                key: const Key('home_empty_browse_albums'),
                                label: context.t('home.browseAlbums'),
                                variant: GlassButtonVariant.normal,
                                size: GlassButtonSize.medium,
                                onPressed: () => widget.navigator
                                    .navigateTo(AppDestination.albums),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
