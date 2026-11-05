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

  /// Album tab sort key (e.g. 'recentlyAdded', 'title', 'artist').
  final String albumSort;

  /// Track tab sort key (e.g. 'title', 'artist', 'recentlyAdded').
  final String trackSort;

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

  /// Creates an [AppSettings] instance with strict defaults.
  const AppSettings({
    this.language = 'en',
    this.userName = '',
    this.glassQuality = GlassQuality.full,
    this.reduceMotion = false,
    this.sidebarCompact = false,
    this.libraryViewMode = 'square',
    this.albumSort = 'recentlyAdded',
    this.trackSort = 'title',
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
  }) : replayGainPreampDb = replayGainPreampDb < -15.0
            ? -15.0
            : (replayGainPreampDb > 15.0 ? 15.0 : replayGainPreampDb);

  static double _clampPreamp(num? value) {
    if (value == null) return 0.0;
    final d = value.toDouble();
    if (d.isNaN) return 0.0;
    return d.clamp(-15.0, 15.0);
  }

  /// Creates a copy of this settings instance with updated fields.
  AppSettings copyWith({
    String? language,
    String? userName,
    GlassQuality? glassQuality,
    bool? reduceMotion,
    bool? sidebarCompact,
    String? libraryViewMode,
    String? albumSort,
    String? trackSort,
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
  }) {
    return AppSettings(
      language: language ?? this.language,
      userName: userName ?? this.userName,
      glassQuality: glassQuality ?? this.glassQuality,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      sidebarCompact: sidebarCompact ?? this.sidebarCompact,
      libraryViewMode: libraryViewMode ?? this.libraryViewMode,
      albumSort: albumSort ?? this.albumSort,
      trackSort: trackSort ?? this.trackSort,
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
      'albumSort': albumSort,
      'trackSort': trackSort,
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

    final rawAlbumSort = json['albumSort'];
    final albumSort = (rawAlbumSort is String &&
            (rawAlbumSort == 'recentlyAdded' ||
                rawAlbumSort == 'title' ||
                rawAlbumSort == 'artist' ||
                rawAlbumSort == 'year'))
        ? rawAlbumSort
        : 'recentlyAdded';

    final rawTrackSort = json['trackSort'];
    final trackSort = (rawTrackSort is String &&
            (rawTrackSort == 'title' ||
                rawTrackSort == 'artist' ||
                rawTrackSort == 'album' ||
                rawTrackSort == 'duration'))
        ? rawTrackSort
        : 'title';

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

    return AppSettings(
      language: language,
      userName: userName,
      glassQuality: glassQuality,
      reduceMotion: reduceMotion,
      sidebarCompact: sidebarCompact,
      libraryViewMode: libraryViewMode,
      albumSort: albumSort,
      trackSort: trackSort,
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
          albumSort == other.albumSort &&
          trackSort == other.trackSort &&
          fullScreenGlassShapes == other.fullScreenGlassShapes &&
          arabicNumerals == other.arabicNumerals &&
          textScale == other.textScale &&
          uiFont == other.uiFont &&
          artistNameMode == other.artistNameMode &&
          outputDeviceId == other.outputDeviceId &&
          exclusiveMode == other.exclusiveMode &&
          replayGainMode == other.replayGainMode &&
          replayGainPreampDb == other.replayGainPreampDb &&
          resumeSession == other.resumeSession;

  @override
  int get hashCode => Object.hashAll([
        language,
        userName,
        glassQuality,
        reduceMotion,
        sidebarCompact,
        libraryViewMode,
        albumSort,
        trackSort,
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
      ]);
}
