import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/models.dart';

/// Shared SQLite row mappers and query helpers for library stores.
class SqliteRowMappers {
  const SqliteRowMappers._();

  /// Escapes SQL LIKE wildcards for backslash-escaped queries.
  static String escapeLike(String term) {
    return term
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  /// Maps a SQLite album aggregation [row] to an [AlbumSummary].
  static AlbumSummary mapAlbum(Row row) {
    final rawAlbumArtist = row['album_artist'] as String?;
    final distinctArtistCount = row['distinct_artist_count'] as int;
    final singleArtist = row['single_artist'] as String?;
    final addedAtVal = row['latest_added_at'] as int?;

    final String? displayArtist;
    if (rawAlbumArtist != null && rawAlbumArtist.isNotEmpty) {
      displayArtist = rawAlbumArtist;
    } else if (distinctArtistCount == 1 &&
        singleArtist != null &&
        singleArtist.isNotEmpty) {
      displayArtist = singleArtist;
    } else if (distinctArtistCount > 1) {
      displayArtist = 'various';
    } else {
      displayArtist = null;
    }

    return AlbumSummary(
      album: row['album_name'] as String,
      albumArtist: rawAlbumArtist,
      year: row['release_year'] as int?,
      trackCount: row['track_count'] as int,
      coverKey: row['cover_key'] as String?,
      displayArtist: displayArtist,
      identityKey: row['album_key'] as String?,
      addedAt: addedAtVal != null
          ? DateTime.fromMillisecondsSinceEpoch(addedAtVal, isUtc: true)
          : null,
    );
  }

  /// Maps a `play_events` [row] to a [PlayEvent].
  static PlayEvent mapPlayEvent(Row row) {
    return PlayEvent(
      id: row['id'] as int,
      uri: row['uri'] as String,
      title: row['title'] as String?,
      artist: row['artist'] as String?,
      album: row['album'] as String?,
      albumArtist: row['album_artist'] as String?,
      durationMs: row['duration_ms'] as int?,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        row['started_at_ms'] as int,
        isUtc: true,
      ),
      listenedMs: row['listened_ms'] as int,
      counted: (row['counted'] as int) == 1,
      completed: (row['completed'] as int) == 1,
      trackUid: row.containsKey('track_uid') ? row['track_uid'] as String? : null,
      source: row.containsKey('source')
          ? ((row['source'] as String?) ?? 'unknown')
          : 'unknown',
      sessionId:
          row.containsKey('session_id') ? row['session_id'] as String? : null,
      endedReason: row.containsKey('ended_reason')
          ? row['ended_reason'] as String?
          : null,
    );
  }

  /// Maps a `tracks` [row] to a [Track].
  static Track mapTrack(Row row) {
    return Track(
      id: row['id'] as int,
      path: row['path'] as String,
      folderId: row['folder_id'] as int,
      title: row['title'] as String?,
      artist: row['artist'] as String?,
      albumArtist: row['album_artist'] as String?,
      album: row['album'] as String?,
      trackNo: row['track_no'] as int?,
      discNo: row['disc_no'] as int?,
      year: row['year'] as int?,
      durationMs: row['duration_ms'] as int,
      mtimeMs: row['mtime_ms'] as int,
      sizeBytes: row['size_bytes'] as int,
      coverKey: row['cover_key'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        row['added_at'] as int,
        isUtc: true,
      ),
    );
  }
}
