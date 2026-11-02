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
  });

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

    return AppSettings(
      language: language,
      userName: userName,
      glassQuality: glassQuality,
      reduceMotion: reduceMotion,
      sidebarCompact: sidebarCompact,
      libraryViewMode: libraryViewMode,
      albumSort: albumSort,
      trackSort: trackSort,
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
          trackSort == other.trackSort;

  @override
  int get hashCode => Object.hash(
        language,
        userName,
        glassQuality,
        reduceMotion,
        sidebarCompact,
        libraryViewMode,
        albumSort,
        trackSort,
      );
}
