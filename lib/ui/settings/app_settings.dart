import 'package:flutter/foundation.dart';

import '../../audio/audio_models.dart';
import '../glass/glass_quality.dart';

/// Immutable model representing persistent user preferences and UI configuration.
class AppSettings {
  /// Selected interface language ('en' or 'ar').
  final String language;

  /// User display name for personalized greetings.
  final String userName;

  /// Active glass rendering quality tier.
  final GlassQuality glassQuality;

  /// Whether animations and motion transitions are disabled.
  final bool reduceMotion;

  /// Whether the navigation sidebar renders in compact icon-only mode.
  final bool sidebarCompact;

  /// Music library grid/list layout mode ('square', 'wide', or 'list').
  final String libraryViewMode;

  /// Artists list layout mode ('circle', 'square', or 'list').
  final String artistsViewMode;

  /// Playlists list layout mode ('square', 'wide', or 'list').
  final String playlistsViewMode;

  /// Album tab sort key (e.g. 'recentlyAdded', 'title', 'artist').
  final String albumSort;

  /// Whether album list sorting is in reverse direction (e.g. descending).
  final bool albumsSortReversed;

  /// Track tab sort key (e.g. 'title', 'artist', 'recentlyAdded').
  final String trackSort;

  /// Whether track list sorting is in reverse direction.
  final bool tracksSortReversed;

  /// Artists tab sort key (e.g. 'name', 'mostSongs', 'mostAlbums', 'recentlyAdded').
  final String artistsSort;

  /// Whether artists list sorting is in reverse direction.
  final bool artistsSortReversed;

  /// Playlists tab sort key (e.g. 'name', 'trackCount', 'recentlyAdded').
  final String playlistsSort;

  /// Whether playlists list sorting is in reverse direction.
  final bool playlistsSortReversed;

  /// Favorites tab sort key (e.g. 'recentlyAdded', 'title', 'artist', 'album', 'duration').
  final String favoritesSort;

  /// Whether favorites list sorting is in reverse direction.
  final bool favoritesSortReversed;

  /// Recently played tab sort key (e.g. 'playedAt', 'title', 'artist', 'duration').
  final String recentlyPlayedSort;

  /// Whether recently played list sorting is in reverse direction.
  final bool recentlyPlayedSortReversed;

  /// Artist detail track list sort key (e.g. 'title', 'album', 'mostPlayed', 'recentlyAdded', 'duration').
  final String artistDetailTrackSort;

  /// Whether artist detail track list sorting is in reverse direction.
  final bool artistDetailTrackSortReversed;

  /// Custom ordered artist keys for Albums page artist chips.
  final List<String> albumsArtistChipsOrder;

  /// Whether floating decorative glass shapes appear in full-screen view.
  final bool fullScreenGlassShapes;

  /// Whether Arabic-Indic digits (٠-٩) replace Western digits when language is 'ar'.
  final bool arabicNumerals;

  /// Interface text scaling tier ('small', 'normal', 'large').
  final String textScale;

  /// Chosen UI font family ('system' or a bundled family name).
  final String uiFont;

  /// Display mode for artist names ('asTagged', 'followLanguage', 'alwaysArabic').
  final String artistNameMode;

  /// Selected audio output device ID ('auto' for default).
  final String outputDeviceId;

  /// Whether exclusive audio output mode is enabled.
  final bool exclusiveMode;

  /// ReplayGain normalization mode ('off', 'track', 'album').
  final String replayGainMode;

  /// ReplayGain pre-amplification in dB (-15.0 to +15.0).
  final double replayGainPreampDb;

  /// Whether to save and restore playback queue, position, and modes across app restarts.
  final bool resumeSession;

  /// Output playback volume (0.0 to 1.0).
  final double volume;

  /// Whether Windows System Media Transport Controls (SMTC) integration is enabled.
  final bool mediaControls;

  /// Whether to prevent system sleep while audio is actively playing.
  final bool preventSleepWhilePlaying;

  /// Window close button behavior ('quit' or 'tray').
  final String closeBehavior;

  /// Active lyrics retrieval strategy ('localThenOnline', 'onlineThenLocal', 'localOnly', 'onlineOnly', 'off').
  final String lyricsSource;

  /// Highlighting granularity ('line' or 'word').
  final String lyricsHighlight;

  /// Whether lyrics are shown in full-screen playback mode.
  final bool showLyricsInFullScreen;

  /// Step size in seconds for arrow-key seeking (1, 2, or 5).
  final int seekStepSeconds;

  /// Window shape in mini player mode ('wide' or 'square').
  final String miniPlayerShape;

  /// Default desktop placement position for mini player ('bottomRight', 'topCenter', or 'remember').
  final String miniPlayerPosition;

  /// Whether mini player window stays pinned always on top of other windows.
  final bool miniPlayerAlwaysOnTop;

  /// Last remembered X coordinate in logical pixels (used when position is 'remember').
  final double? miniPlayerLastX;

  /// Last remembered Y coordinate in logical pixels (used when position is 'remember').
  final double? miniPlayerLastY;

  /// Whether compact lyrics are displayed in the mini player window.
  final bool miniPlayerShowLyrics;

  /// Transition smoothness mode for audio playback ('off', 'soft', or 'smooth').
  final String transitionSmoothness;

  /// Whether the docked right side panel is open.
  final bool sidePanelOpen;

  /// Active tab in the docked right side panel ('queue' or 'lyrics').
  final String sidePanelTab;

  /// Whether smooth volume fade transitions are enabled around playback changes.
  bool get smoothTransitions => transitionSmoothness != 'off';

  /// Resolves the active [FadeProfile] for this configuration.
  FadeProfile get fadeProfile {
    switch (transitionSmoothness) {
      case 'off':
        return FadeProfile.off;
      case 'soft':
        return FadeProfile.soft;
      case 'smooth':
      default:
        return FadeProfile.smooth;
    }
  }

  /// Creates an [AppSettings] instance with strict defaults.
  const AppSettings({
    this.language = 'en',
    this.userName = '',
    this.glassQuality = GlassQuality.full,
    this.reduceMotion = false,
    this.sidebarCompact = false,
    this.libraryViewMode = 'square',
    this.artistsViewMode = 'circle',
    this.playlistsViewMode = 'square',
    this.albumSort = 'recentlyAdded',
    this.albumsSortReversed = false,
    this.trackSort = 'title',
    this.tracksSortReversed = false,
    this.artistsSort = 'name',
    this.artistsSortReversed = false,
    this.playlistsSort = 'name',
    this.playlistsSortReversed = false,
    this.favoritesSort = 'recentlyAdded',
    this.favoritesSortReversed = false,
    this.recentlyPlayedSort = 'playedAt',
    this.recentlyPlayedSortReversed = false,
    this.artistDetailTrackSort = 'title',
    this.artistDetailTrackSortReversed = false,
    this.albumsArtistChipsOrder = const [],
    this.fullScreenGlassShapes = true,
    this.arabicNumerals = false,
    this.textScale = 'normal',
    this.uiFont = 'system',
    this.artistNameMode = 'followLanguage',
    this.outputDeviceId = 'auto',
    this.exclusiveMode = false,
    this.replayGainMode = 'off',
    double replayGainPreampDb = 0.0,
    this.resumeSession = true,
    double volume = 1.0,
    this.mediaControls = true,
    this.preventSleepWhilePlaying = true,
    String closeBehavior = 'quit',
    String lyricsSource = 'localThenOnline',
    String lyricsHighlight = 'word',
    this.showLyricsInFullScreen = true,
    int seekStepSeconds = 2,
    String miniPlayerShape = 'wide',
    String miniPlayerPosition = 'bottomRight',
    this.miniPlayerAlwaysOnTop = true,
    this.miniPlayerLastX,
    this.miniPlayerLastY,
    this.miniPlayerShowLyrics = false,
    String transitionSmoothness = 'smooth',
    bool? smoothTransitions,
    this.sidePanelOpen = false,
    String sidePanelTab = 'queue',
  })  : replayGainPreampDb = replayGainPreampDb < -15.0
            ? -15.0
            : (replayGainPreampDb > 15.0 ? 15.0 : replayGainPreampDb),
        volume = volume < 0.0 ? 0.0 : (volume > 1.0 ? 1.0 : volume),
        closeBehavior = closeBehavior == 'tray' ? 'tray' : 'quit',
        lyricsSource = (lyricsSource == 'onlineThenLocal' ||
                lyricsSource == 'localOnly' ||
                lyricsSource == 'onlineOnly' ||
                lyricsSource == 'off')
            ? lyricsSource
            : 'localThenOnline',
        lyricsHighlight = lyricsHighlight == 'line' ? 'line' : 'word',
        seekStepSeconds =
            (seekStepSeconds == 1 || seekStepSeconds == 5) ? seekStepSeconds : 2,
        miniPlayerShape = (miniPlayerShape == 'square') ? 'square' : 'wide',
        miniPlayerPosition = (miniPlayerPosition == 'topCenter' ||
                miniPlayerPosition == 'remember')
            ? miniPlayerPosition
            : 'bottomRight',
        transitionSmoothness = (transitionSmoothness == 'off' ||
                transitionSmoothness == 'soft' ||
                transitionSmoothness == 'smooth')
            ? (smoothTransitions == false && transitionSmoothness == 'smooth'
                ? 'off'
                : transitionSmoothness)
            : 'smooth',
        sidePanelTab = sidePanelTab == 'lyrics' ? 'lyrics' : 'queue';

  static double _clampPreamp(num? value) {
    if (value == null) return 0.0;
    final d = value.toDouble();
    if (d.isNaN) return 0.0;
    return d.clamp(-15.0, 15.0);
  }

  static double _clampVolume(num? value) {
    if (value == null) return 1.0;
    final d = value.toDouble();
    if (d.isNaN) return 1.0;
    return d.clamp(0.0, 1.0);
  }

  /// Creates a copy of this settings instance with updated fields.
  AppSettings copyWith({
    String? language,
    String? userName,
    GlassQuality? glassQuality,
    bool? reduceMotion,
    bool? sidebarCompact,
    String? libraryViewMode,
    String? artistsViewMode,
    String? playlistsViewMode,
    String? albumSort,
    bool? albumsSortReversed,
    String? trackSort,
    bool? tracksSortReversed,
    String? artistsSort,
    bool? artistsSortReversed,
    String? playlistsSort,
    bool? playlistsSortReversed,
    String? favoritesSort,
    bool? favoritesSortReversed,
    String? recentlyPlayedSort,
    bool? recentlyPlayedSortReversed,
    String? artistDetailTrackSort,
    bool? artistDetailTrackSortReversed,
    List<String>? albumsArtistChipsOrder,
    bool? fullScreenGlassShapes,
    bool? arabicNumerals,
    String? textScale,
    String? uiFont,
    String? artistNameMode,
    String? outputDeviceId,
    bool? exclusiveMode,
    String? replayGainMode,
    double? replayGainPreampDb,
    bool? resumeSession,
    double? volume,
    bool? mediaControls,
    bool? preventSleepWhilePlaying,
    String? closeBehavior,
    String? lyricsSource,
    String? lyricsHighlight,
    bool? showLyricsInFullScreen,
    int? seekStepSeconds,
    String? miniPlayerShape,
    String? miniPlayerPosition,
    bool? miniPlayerAlwaysOnTop,
    double? miniPlayerLastX,
    double? miniPlayerLastY,
    bool? miniPlayerShowLyrics,
    String? transitionSmoothness,
    bool? smoothTransitions,
    bool? sidePanelOpen,
    String? sidePanelTab,
  }) {
    String resolvedSmoothness = this.transitionSmoothness;
    if (transitionSmoothness != null) {
      resolvedSmoothness = (transitionSmoothness == 'off' ||
              transitionSmoothness == 'soft' ||
              transitionSmoothness == 'smooth')
          ? transitionSmoothness
          : 'smooth';
    } else if (smoothTransitions != null) {
      resolvedSmoothness = smoothTransitions ? 'smooth' : 'off';
    }
    return AppSettings(
      language: language ?? this.language,
      userName: userName ?? this.userName,
      glassQuality: glassQuality ?? this.glassQuality,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      sidebarCompact: sidebarCompact ?? this.sidebarCompact,
      libraryViewMode: libraryViewMode ?? this.libraryViewMode,
      artistsViewMode: artistsViewMode ?? this.artistsViewMode,
      playlistsViewMode: playlistsViewMode ?? this.playlistsViewMode,
      albumSort: albumSort ?? this.albumSort,
      albumsSortReversed: albumsSortReversed ?? this.albumsSortReversed,
      trackSort: trackSort ?? this.trackSort,
      tracksSortReversed: tracksSortReversed ?? this.tracksSortReversed,
      artistsSort: artistsSort ?? this.artistsSort,
      artistsSortReversed: artistsSortReversed ?? this.artistsSortReversed,
      playlistsSort: playlistsSort ?? this.playlistsSort,
      playlistsSortReversed: playlistsSortReversed ?? this.playlistsSortReversed,
      favoritesSort: favoritesSort ?? this.favoritesSort,
      favoritesSortReversed: favoritesSortReversed ?? this.favoritesSortReversed,
      recentlyPlayedSort: recentlyPlayedSort ?? this.recentlyPlayedSort,
      recentlyPlayedSortReversed:
          recentlyPlayedSortReversed ?? this.recentlyPlayedSortReversed,
      artistDetailTrackSort:
          artistDetailTrackSort ?? this.artistDetailTrackSort,
      artistDetailTrackSortReversed:
          artistDetailTrackSortReversed ?? this.artistDetailTrackSortReversed,
      albumsArtistChipsOrder:
          albumsArtistChipsOrder ?? this.albumsArtistChipsOrder,
      fullScreenGlassShapes:
          fullScreenGlassShapes ?? this.fullScreenGlassShapes,
      arabicNumerals: arabicNumerals ?? this.arabicNumerals,
      textScale: textScale ?? this.textScale,
      uiFont: uiFont ?? this.uiFont,
      artistNameMode: artistNameMode ?? this.artistNameMode,
      outputDeviceId: outputDeviceId ?? this.outputDeviceId,
      exclusiveMode: exclusiveMode ?? this.exclusiveMode,
      replayGainMode: replayGainMode ?? this.replayGainMode,
      replayGainPreampDb: replayGainPreampDb != null
          ? _clampPreamp(replayGainPreampDb)
          : this.replayGainPreampDb,
      resumeSession: resumeSession ?? this.resumeSession,
      volume: volume != null ? _clampVolume(volume) : this.volume,
      mediaControls: mediaControls ?? this.mediaControls,
      preventSleepWhilePlaying:
          preventSleepWhilePlaying ?? this.preventSleepWhilePlaying,
      closeBehavior: closeBehavior ?? this.closeBehavior,
      lyricsSource: lyricsSource ?? this.lyricsSource,
      lyricsHighlight: lyricsHighlight ?? this.lyricsHighlight,
      showLyricsInFullScreen:
          showLyricsInFullScreen ?? this.showLyricsInFullScreen,
      seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
      miniPlayerShape: miniPlayerShape ?? this.miniPlayerShape,
      miniPlayerPosition: miniPlayerPosition ?? this.miniPlayerPosition,
      miniPlayerAlwaysOnTop:
          miniPlayerAlwaysOnTop ?? this.miniPlayerAlwaysOnTop,
      miniPlayerLastX: miniPlayerLastX ?? this.miniPlayerLastX,
      miniPlayerLastY: miniPlayerLastY ?? this.miniPlayerLastY,
      miniPlayerShowLyrics: miniPlayerShowLyrics ?? this.miniPlayerShowLyrics,
      transitionSmoothness: resolvedSmoothness,
      sidePanelOpen: sidePanelOpen ?? this.sidePanelOpen,
      sidePanelTab: sidePanelTab == null
          ? this.sidePanelTab
          : (sidePanelTab == 'lyrics' ? 'lyrics' : 'queue'),
    );
  }

  /// Serializes this instance to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'language': language,
      'userName': userName,
      'glassQuality': glassQuality.name,
      'reduceMotion': reduceMotion,
      'sidebarCompact': sidebarCompact,
      'libraryViewMode': libraryViewMode,
      'artistsViewMode': artistsViewMode,
      'playlistsViewMode': playlistsViewMode,
      'albumSort': albumSort,
      'albumsSortReversed': albumsSortReversed,
      'trackSort': trackSort,
      'tracksSortReversed': tracksSortReversed,
      'artistsSort': artistsSort,
      'artistsSortReversed': artistsSortReversed,
      'playlistsSort': playlistsSort,
      'playlistsSortReversed': playlistsSortReversed,
      'favoritesSort': favoritesSort,
      'favoritesSortReversed': favoritesSortReversed,
      'recentlyPlayedSort': recentlyPlayedSort,
      'recentlyPlayedSortReversed': recentlyPlayedSortReversed,
      'artistDetailTrackSort': artistDetailTrackSort,
      'artistDetailTrackSortReversed': artistDetailTrackSortReversed,
      'albumsArtistChipsOrder': albumsArtistChipsOrder,
      'fullScreenGlassShapes': fullScreenGlassShapes,
      'arabicNumerals': arabicNumerals,
      'textScale': textScale,
      'uiFont': uiFont,
      'artistNameMode': artistNameMode,
      'outputDeviceId': outputDeviceId,
      'exclusiveMode': exclusiveMode,
      'replayGainMode': replayGainMode,
      'replayGainPreampDb': replayGainPreampDb,
      'resumeSession': resumeSession,
      'volume': volume,
      'mediaControls': mediaControls,
      'preventSleepWhilePlaying': preventSleepWhilePlaying,
      'closeBehavior': closeBehavior,
      'lyricsSource': lyricsSource,
      'lyricsHighlight': lyricsHighlight,
      'showLyricsInFullScreen': showLyricsInFullScreen,
      'seekStepSeconds': seekStepSeconds,
      'miniPlayerShape': miniPlayerShape,
      'miniPlayerPosition': miniPlayerPosition,
      'miniPlayerAlwaysOnTop': miniPlayerAlwaysOnTop,
      'miniPlayerLastX': miniPlayerLastX,
      'miniPlayerLastY': miniPlayerLastY,
      'miniPlayerShowLyrics': miniPlayerShowLyrics,
      'transitionSmoothness': transitionSmoothness,
      'smoothTransitions': smoothTransitions,
      'sidePanelOpen': sidePanelOpen,
      'sidePanelTab': sidePanelTab,
    };
  }

  /// Deserializes an [AppSettings] instance from a JSON map with tolerant fallback.
  factory AppSettings.fromJson(Map<String, Object?>? json) {
    if (json == null) return const AppSettings();

    final rawLang = json['language'];
    final language =
        (rawLang is String && (rawLang == 'en' || rawLang == 'ar'))
            ? rawLang
            : 'en';

    final rawName = json['userName'];
    final userName = rawName is String ? rawName : '';

    final rawQuality = json['glassQuality'];
    final glassQuality = switch (rawQuality) {
      'full' => GlassQuality.full,
      'light' => GlassQuality.light,
      'off' => GlassQuality.off,
      _ => GlassQuality.full,
    };

    final rawMotion = json['reduceMotion'];
    final reduceMotion = rawMotion is bool ? rawMotion : false;

    final rawSidebar = json['sidebarCompact'];
    final sidebarCompact = rawSidebar is bool ? rawSidebar : false;

    final rawView = json['libraryViewMode'];
    final libraryViewMode = (rawView is String &&
            (rawView == 'square' || rawView == 'wide' || rawView == 'list'))
        ? rawView
        : 'square';

    final rawArtistsView = json['artistsViewMode'];
    final artistsViewMode = (rawArtistsView is String &&
            (rawArtistsView == 'circle' ||
                rawArtistsView == 'square' ||
                rawArtistsView == 'list'))
        ? rawArtistsView
        : 'circle';

    final rawPlaylistsView = json['playlistsViewMode'];
    final playlistsViewMode = (rawPlaylistsView is String &&
            (rawPlaylistsView == 'square' ||
                rawPlaylistsView == 'wide' ||
                rawPlaylistsView == 'list'))
        ? rawPlaylistsView
        : 'square';

    final rawAlbumSort = json['albumSort'];
    final albumSort = (rawAlbumSort is String &&
            (rawAlbumSort == 'recentlyAdded' ||
                rawAlbumSort == 'title' ||
                rawAlbumSort == 'artist' ||
                rawAlbumSort == 'year'))
        ? rawAlbumSort
        : 'recentlyAdded';

    final rawAlbumsReversed = json['albumsSortReversed'];
    final albumsSortReversed =
        rawAlbumsReversed is bool ? rawAlbumsReversed : false;

    final rawTrackSort = json['trackSort'];
    final trackSort = (rawTrackSort is String &&
            (rawTrackSort == 'title' ||
                rawTrackSort == 'artist' ||
                rawTrackSort == 'album' ||
                rawTrackSort == 'duration' ||
                rawTrackSort == 'recentlyAdded'))
        ? rawTrackSort
        : 'title';

    final rawTracksReversed = json['tracksSortReversed'];
    final tracksSortReversed =
        rawTracksReversed is bool ? rawTracksReversed : false;

    final rawArtistsSort = json['artistsSort'];
    final artistsSort = (rawArtistsSort is String &&
            (rawArtistsSort == 'name' ||
                rawArtistsSort == 'mostSongs' ||
                rawArtistsSort == 'mostAlbums' ||
                rawArtistsSort == 'recentlyAdded'))
        ? rawArtistsSort
        : 'name';

    final rawArtistsReversed = json['artistsSortReversed'];
    final artistsSortReversed =
        rawArtistsReversed is bool ? rawArtistsReversed : false;

    final rawPlaylistsSort = json['playlistsSort'];
    final playlistsSort = (rawPlaylistsSort is String &&
            (rawPlaylistsSort == 'name' ||
                rawPlaylistsSort == 'trackCount' ||
                rawPlaylistsSort == 'recentlyAdded'))
        ? rawPlaylistsSort
        : 'name';

    final rawPlaylistsReversed = json['playlistsSortReversed'];
    final playlistsSortReversed =
        rawPlaylistsReversed is bool ? rawPlaylistsReversed : false;

    final rawFavoritesSort = json['favoritesSort'];
    final favoritesSort = (rawFavoritesSort is String &&
            (rawFavoritesSort == 'recentlyAdded' ||
                rawFavoritesSort == 'title' ||
                rawFavoritesSort == 'artist' ||
                rawFavoritesSort == 'album' ||
                rawFavoritesSort == 'duration'))
        ? rawFavoritesSort
        : 'recentlyAdded';

    final rawFavoritesReversed = json['favoritesSortReversed'];
    final favoritesSortReversed =
        rawFavoritesReversed is bool ? rawFavoritesReversed : false;

    final rawRecentSort = json['recentlyPlayedSort'];
    final recentlyPlayedSort = (rawRecentSort is String &&
            (rawRecentSort == 'playedAt' ||
                rawRecentSort == 'title' ||
                rawRecentSort == 'artist' ||
                rawRecentSort == 'duration'))
        ? rawRecentSort
        : 'playedAt';

    final rawRecentReversed = json['recentlyPlayedSortReversed'];
    final recentlyPlayedSortReversed =
        rawRecentReversed is bool ? rawRecentReversed : false;

    final rawDetailTrackSort = json['artistDetailTrackSort'];
    final artistDetailTrackSort = (rawDetailTrackSort is String &&
            (rawDetailTrackSort == 'title' ||
                rawDetailTrackSort == 'album' ||
                rawDetailTrackSort == 'mostPlayed' ||
                rawDetailTrackSort == 'recentlyAdded' ||
                rawDetailTrackSort == 'duration'))
        ? rawDetailTrackSort
        : 'title';

    final rawDetailTrackReversed = json['artistDetailTrackSortReversed'];
    final artistDetailTrackSortReversed =
        rawDetailTrackReversed is bool ? rawDetailTrackReversed : false;

    final rawChips = json['albumsArtistChipsOrder'];
    final albumsArtistChipsOrder = (rawChips is List)
        ? rawChips.whereType<String>().toList()
        : const <String>[];

    final rawGlassShapes = json['fullScreenGlassShapes'];
    final fullScreenGlassShapes =
        rawGlassShapes is bool ? rawGlassShapes : true;

    final rawArabicNumerals = json['arabicNumerals'];
    final arabicNumerals =
        rawArabicNumerals is bool ? rawArabicNumerals : false;

    final rawTextScale = json['textScale'];
    final textScale = (rawTextScale is String &&
            (rawTextScale == 'small' ||
                rawTextScale == 'normal' ||
                rawTextScale == 'large'))
        ? rawTextScale
        : 'normal';

    final rawUiFont = json['uiFont'];
    final uiFont =
        rawUiFont is String && rawUiFont.isNotEmpty ? rawUiFont : 'system';

    final rawArtistNameMode = json['artistNameMode'];
    final artistNameMode = (rawArtistNameMode is String &&
            (rawArtistNameMode == 'asTagged' ||
                rawArtistNameMode == 'followLanguage' ||
                rawArtistNameMode == 'alwaysArabic'))
        ? rawArtistNameMode
        : 'followLanguage';

    final rawOutputDeviceId = json['outputDeviceId'];
    final outputDeviceId =
        rawOutputDeviceId is String && rawOutputDeviceId.isNotEmpty
            ? rawOutputDeviceId
            : 'auto';

    final rawExclusive = json['exclusiveMode'];
    final exclusiveMode = rawExclusive is bool ? rawExclusive : false;

    final rawReplayGain = json['replayGainMode'];
    final replayGainMode = (rawReplayGain is String &&
            (rawReplayGain == 'off' ||
                rawReplayGain == 'track' ||
                rawReplayGain == 'album'))
        ? rawReplayGain
        : 'off';

    final rawPreamp = json['replayGainPreampDb'];
    final replayGainPreampDb =
        rawPreamp is num ? _clampPreamp(rawPreamp) : 0.0;

    final rawResume = json['resumeSession'];
    final resumeSession = rawResume is bool ? rawResume : true;

    final rawVolume = json['volume'];
    final volume = rawVolume is num ? _clampVolume(rawVolume) : 1.0;

    final rawMediaControls = json['mediaControls'];
    final mediaControls =
        rawMediaControls is bool ? rawMediaControls : true;

    final rawPreventSleep = json['preventSleepWhilePlaying'];
    final preventSleepWhilePlaying =
        rawPreventSleep is bool ? rawPreventSleep : true;

    final rawCloseBehavior = json['closeBehavior'];
    final closeBehavior =
        rawCloseBehavior == 'tray' ? 'tray' : 'quit';

    final rawLyricsSource = json['lyricsSource'];
    final lyricsSource = (rawLyricsSource == 'onlineThenLocal' ||
            rawLyricsSource == 'localOnly' ||
            rawLyricsSource == 'onlineOnly' ||
            rawLyricsSource == 'off')
        ? rawLyricsSource as String
        : 'localThenOnline';

    final rawLyricsHighlight = json['lyricsHighlight'];
    final lyricsHighlight =
        rawLyricsHighlight == 'line' ? 'line' : 'word';

    final rawShowLyricsInFS = json['showLyricsInFullScreen'];
    final showLyricsInFullScreen =
        rawShowLyricsInFS is bool ? rawShowLyricsInFS : true;

    final rawSeekStep = json['seekStepSeconds'];
    final seekStepSeconds =
        (rawSeekStep == 1 || rawSeekStep == 5) ? rawSeekStep as int : 2;

    final rawMiniShape = json['miniPlayerShape'];
    final miniPlayerShape = (rawMiniShape is String &&
            (rawMiniShape == 'wide' || rawMiniShape == 'square'))
        ? rawMiniShape
        : 'wide';

    final rawMiniPos = json['miniPlayerPosition'];
    final miniPlayerPosition = (rawMiniPos is String &&
            (rawMiniPos == 'bottomRight' ||
                rawMiniPos == 'topCenter' ||
                rawMiniPos == 'remember'))
        ? rawMiniPos
        : 'bottomRight';

    final rawMiniPin = json['miniPlayerAlwaysOnTop'];
    final miniPlayerAlwaysOnTop =
        rawMiniPin is bool ? rawMiniPin : true;

    final rawLastX = json['miniPlayerLastX'];
    final miniPlayerLastX =
        rawLastX is num ? rawLastX.toDouble() : null;

    final rawLastY = json['miniPlayerLastY'];
    final miniPlayerLastY =
        rawLastY is num ? rawLastY.toDouble() : null;

    final rawMiniLyrics = json['miniPlayerShowLyrics'];
    final miniPlayerShowLyrics = rawMiniLyrics is bool ? rawMiniLyrics : false;

    final rawTransitionSmoothness = json['transitionSmoothness'];
    final rawSmoothTransitions = json['smoothTransitions'];
    final String transitionSmoothness;
    if (rawTransitionSmoothness is String) {
      if (rawTransitionSmoothness == 'off' ||
          rawTransitionSmoothness == 'soft' ||
          rawTransitionSmoothness == 'smooth') {
        transitionSmoothness = rawTransitionSmoothness;
      } else {
        transitionSmoothness = 'smooth';
      }
    } else if (rawSmoothTransitions is bool) {
      transitionSmoothness = rawSmoothTransitions ? 'smooth' : 'off';
    } else {
      transitionSmoothness = 'smooth';
    }

    final rawSidePanelOpen = json['sidePanelOpen'];
    final sidePanelOpen = rawSidePanelOpen is bool ? rawSidePanelOpen : false;

    final rawSidePanelTab = json['sidePanelTab'];
    final sidePanelTab = rawSidePanelTab == 'lyrics' ? 'lyrics' : 'queue';

    return AppSettings(
      language: language,
      userName: userName,
      glassQuality: glassQuality,
      reduceMotion: reduceMotion,
      sidebarCompact: sidebarCompact,
      libraryViewMode: libraryViewMode,
      artistsViewMode: artistsViewMode,
      playlistsViewMode: playlistsViewMode,
      albumSort: albumSort,
      albumsSortReversed: albumsSortReversed,
      trackSort: trackSort,
      tracksSortReversed: tracksSortReversed,
      artistsSort: artistsSort,
      artistsSortReversed: artistsSortReversed,
      playlistsSort: playlistsSort,
      playlistsSortReversed: playlistsSortReversed,
      favoritesSort: favoritesSort,
      favoritesSortReversed: favoritesSortReversed,
      recentlyPlayedSort: recentlyPlayedSort,
      recentlyPlayedSortReversed: recentlyPlayedSortReversed,
      artistDetailTrackSort: artistDetailTrackSort,
      artistDetailTrackSortReversed: artistDetailTrackSortReversed,
      albumsArtistChipsOrder: albumsArtistChipsOrder,
      fullScreenGlassShapes: fullScreenGlassShapes,
      arabicNumerals: arabicNumerals,
      textScale: textScale,
      uiFont: uiFont,
      artistNameMode: artistNameMode,
      outputDeviceId: outputDeviceId,
      exclusiveMode: exclusiveMode,
      replayGainMode: replayGainMode,
      replayGainPreampDb: replayGainPreampDb,
      resumeSession: resumeSession,
      volume: volume,
      mediaControls: mediaControls,
      preventSleepWhilePlaying: preventSleepWhilePlaying,
      closeBehavior: closeBehavior,
      lyricsSource: lyricsSource,
      lyricsHighlight: lyricsHighlight,
      showLyricsInFullScreen: showLyricsInFullScreen,
      seekStepSeconds: seekStepSeconds,
      miniPlayerShape: miniPlayerShape,
      miniPlayerPosition: miniPlayerPosition,
      miniPlayerAlwaysOnTop: miniPlayerAlwaysOnTop,
      miniPlayerLastX: miniPlayerLastX,
      miniPlayerLastY: miniPlayerLastY,
      miniPlayerShowLyrics: miniPlayerShowLyrics,
      transitionSmoothness: transitionSmoothness,
      sidePanelOpen: sidePanelOpen,
      sidePanelTab: sidePanelTab,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          language == other.language &&
          userName == other.userName &&
          glassQuality == other.glassQuality &&
          reduceMotion == other.reduceMotion &&
          sidebarCompact == other.sidebarCompact &&
          libraryViewMode == other.libraryViewMode &&
          artistsViewMode == other.artistsViewMode &&
          playlistsViewMode == other.playlistsViewMode &&
          albumSort == other.albumSort &&
          albumsSortReversed == other.albumsSortReversed &&
          trackSort == other.trackSort &&
          tracksSortReversed == other.tracksSortReversed &&
          artistsSort == other.artistsSort &&
          artistsSortReversed == other.artistsSortReversed &&
          playlistsSort == other.playlistsSort &&
          playlistsSortReversed == other.playlistsSortReversed &&
          favoritesSort == other.favoritesSort &&
          favoritesSortReversed == other.favoritesSortReversed &&
          recentlyPlayedSort == other.recentlyPlayedSort &&
          recentlyPlayedSortReversed == other.recentlyPlayedSortReversed &&
          artistDetailTrackSort == other.artistDetailTrackSort &&
          artistDetailTrackSortReversed ==
              other.artistDetailTrackSortReversed &&
          listEquals(albumsArtistChipsOrder, other.albumsArtistChipsOrder) &&
          fullScreenGlassShapes == other.fullScreenGlassShapes &&
          arabicNumerals == other.arabicNumerals &&
          textScale == other.textScale &&
          uiFont == other.uiFont &&
          artistNameMode == other.artistNameMode &&
          outputDeviceId == other.outputDeviceId &&
          exclusiveMode == other.exclusiveMode &&
          replayGainMode == other.replayGainMode &&
          replayGainPreampDb == other.replayGainPreampDb &&
          resumeSession == other.resumeSession &&
          volume == other.volume &&
          mediaControls == other.mediaControls &&
          preventSleepWhilePlaying == other.preventSleepWhilePlaying &&
          closeBehavior == other.closeBehavior &&
          lyricsSource == other.lyricsSource &&
          lyricsHighlight == other.lyricsHighlight &&
          showLyricsInFullScreen == other.showLyricsInFullScreen &&
          seekStepSeconds == other.seekStepSeconds &&
          miniPlayerShape == other.miniPlayerShape &&
          miniPlayerPosition == other.miniPlayerPosition &&
          miniPlayerAlwaysOnTop == other.miniPlayerAlwaysOnTop &&
          miniPlayerLastX == other.miniPlayerLastX &&
          miniPlayerLastY == other.miniPlayerLastY &&
          miniPlayerShowLyrics == other.miniPlayerShowLyrics &&
          transitionSmoothness == other.transitionSmoothness &&
          sidePanelOpen == other.sidePanelOpen &&
          sidePanelTab == other.sidePanelTab;

  @override
  int get hashCode => Object.hashAll([
        language,
        userName,
        glassQuality,
        reduceMotion,
        sidebarCompact,
        libraryViewMode,
        artistsViewMode,
        playlistsViewMode,
        albumSort,
        albumsSortReversed,
        trackSort,
        tracksSortReversed,
        artistsSort,
        artistsSortReversed,
        playlistsSort,
        playlistsSortReversed,
        favoritesSort,
        favoritesSortReversed,
        recentlyPlayedSort,
        recentlyPlayedSortReversed,
        artistDetailTrackSort,
        artistDetailTrackSortReversed,
        Object.hashAll(albumsArtistChipsOrder),
        fullScreenGlassShapes,
        arabicNumerals,
        textScale,
        uiFont,
        artistNameMode,
        outputDeviceId,
        exclusiveMode,
        replayGainMode,
        replayGainPreampDb,
        resumeSession,
        volume,
        mediaControls,
        preventSleepWhilePlaying,
        closeBehavior,
        lyricsSource,
        lyricsHighlight,
        showLyricsInFullScreen,
        seekStepSeconds,
        miniPlayerShape,
        miniPlayerPosition,
        miniPlayerAlwaysOnTop,
        miniPlayerLastX,
        miniPlayerLastY,
        miniPlayerShowLyrics,
        transitionSmoothness,
        sidePanelOpen,
        sidePanelTab,
      ]);
}
