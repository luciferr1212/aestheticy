import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/album_identity.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/sqlite_row_mappers.dart';
import 'package:aestheticy/library/text_normalizer.dart';

/// Internal SQLite store for album listing, grouping, search, and track queries.
class SqliteAlbumsStore {
  final Database _db;
  final String Function() _userSchema;

  /// Creates a [SqliteAlbumsStore] backed by [_db].
  SqliteAlbumsStore(
    this._db, {
    String Function()? userSchema,
  }) : _userSchema = userSchema ?? (() => 'userdata');

  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) async {
    final sql = StringBuffer('''
      SELECT
        album_identity_key(album, album_artist, artist, path) AS album_key,
        MIN(COALESCE(NULLIF(TRIM(album), ''), 'Unknown Album')) AS album_name,
        MAX(NULLIF(TRIM(album_artist), '')) AS album_artist,
        MAX(year) AS release_year,
        COUNT(*) AS track_count,
        MAX(cover_key) AS cover_key,
        COUNT(DISTINCT NULLIF(artist, '')) AS distinct_artist_count,
        MIN(NULLIF(artist, '')) AS single_artist,
        MAX(added_at) AS latest_added_at
      FROM main.tracks
      GROUP BY album_key
      ORDER BY album_name COLLATE NOCASE ASC
    ''');
    final params = <Object?>[];
    if (limit != null) {
      sql.write(' LIMIT ?');
      params.add(limit);
      if (offset != null) {
        sql.write(' OFFSET ?');
        params.add(offset);
      }
    }
    sql.write(';');

    final rows = _db.select(sql.toString(), params);
    return rows.map(SqliteRowMappers.mapAlbum).toList();
  }

  Future<List<AlbumSummary>> listAlbumsByArtistKey(String artistKey) {
    return listAlbumsByArtistKeys([artistKey]);
  }

  Future<List<AlbumSummary>> listAlbumsByArtistKeys(
    List<String> artistKeys,
  ) async {
    if (artistKeys.isEmpty) return [];

    // Deduplicate keys while keeping non-empty callers consistent with
    // single-key lookups.
    final uniqueKeys = artistKeys.toSet().toList(growable: false);
    if (uniqueKeys.length <= 100) {
      return _queryAlbumsByArtistKeyChunk(uniqueKeys);
    }

    // Batch queries to stay well below SQLite's bind parameter limit (7 params
    // per key -> 700 params max per batch), then union/deduplicate albums.
    final seen = <String, AlbumSummary>{};
    for (var i = 0; i < uniqueKeys.length; i += 100) {
      final end = (i + 100 < uniqueKeys.length) ? i + 100 : uniqueKeys.length;
      final chunk = uniqueKeys.sublist(i, end);
      final chunkAlbums = await _queryAlbumsByArtistKeyChunk(chunk);
      for (final album in chunkAlbums) {
        seen.putIfAbsent(
          AlbumIdentity.forSummary(album),
          () => album,
        );
      }
    }

    final result = seen.values.toList()
      ..sort((a, b) {
        final cmp = a.album.toLowerCase().compareTo(b.album.toLowerCase());
        if (cmp != 0) return cmp;
        return a.album.compareTo(b.album);
      });
    return result;
  }

  Future<List<AlbumSummary>> _queryAlbumsByArtistKeyChunk(
    List<String> artistKeys,
  ) async {
    final u = _userSchema();
    final placeholders = List.filled(artistKeys.length, '?').join(', ');
    final normalizedPlaceholders =
        List.filled(artistKeys.length, 'normalize_text(?)').join(', ');

    final rows = _db.select(
      '''
      SELECT
        album_identity_key(t.album, t.album_artist, t.artist, t.path) AS album_key,
        MIN(COALESCE(NULLIF(TRIM(t.album), ''), 'Unknown Album')) AS album_name,
        MAX(NULLIF(TRIM(t.album_artist), '')) AS album_artist,
        MAX(t.year) AS release_year,
        COUNT(*) AS track_count,
        MAX(t.cover_key) AS cover_key,
        COUNT(DISTINCT NULLIF(t.artist, '')) AS distinct_artist_count,
        MIN(NULLIF(t.artist, '')) AS single_artist,
        MAX(t.added_at) AS latest_added_at
      FROM main.tracks t
      WHERE t.album IS NOT NULL AND TRIM(t.album) != ''
        AND EXISTS (
          SELECT 1
          FROM main.tracks t2
          JOIN main.track_artists ta ON ta.track_id = t2.id
          WHERE album_identity_key(t2.album, t2.album_artist, t2.artist, t2.path) =
              album_identity_key(t.album, t.album_artist, t.artist, t.path)
            AND (
              ta.artist_key IN ($placeholders)
              OR ta.artist_key IN ($normalizedPlaceholders)
              OR ta.artist_name IN ($placeholders)
              OR ta.artist_key IN (
                SELECT canonical_key FROM $u.artist_aliases
                WHERE alias_key IN ($placeholders) OR alias_key IN ($normalizedPlaceholders)
              )
              OR ta.artist_key IN (
                SELECT alias_key FROM $u.artist_aliases
                WHERE canonical_key IN ($placeholders) OR canonical_key IN ($normalizedPlaceholders)
              )
            )
        )
      GROUP BY album_key
      ORDER BY album_name COLLATE NOCASE ASC;
      ''',
      [
        ...artistKeys,
        ...artistKeys,
        ...artistKeys,
        ...artistKeys,
        ...artistKeys,
        ...artistKeys,
        ...artistKeys,
      ],
    );

    return rows.map(SqliteRowMappers.mapAlbum).toList();
  }

  Future<List<Track>> tracksOfAlbum(
    String album, {
    String? albumArtist,
    String? albumKey,
  }) async {
    final trimmedKey = albumKey?.trim() ?? '';
    final String targetKey;
    if (trimmedKey.isNotEmpty) {
      targetKey = trimmedKey;
    } else {
      final effectiveAlbum =
          album.trim() == AlbumIdentity.unknownAlbumTitle ? null : album;
      targetKey = AlbumIdentity.key(
        album: effectiveAlbum,
        albumArtist: albumArtist,
      );
    }

    final rows = _db.select(
      '''
      SELECT * FROM main.tracks
      WHERE album_identity_key(album, album_artist, artist, path) = ?
      ORDER BY COALESCE(disc_no, 1) ASC, COALESCE(track_no, 0) ASC, title COLLATE NOCASE ASC;
      ''',
      [targetKey],
    );

    return rows.map(SqliteRowMappers.mapTrack).toList();
  }

  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) async {
    final normalized = TextNormalizer.normalize(query);
    if (normalized.isEmpty) return [];

    final terms = normalized
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];

    final whereClauses =
        terms.map((_) => "searchable LIKE ? ESCAPE '\\'").join(' AND ');

    final u = _userSchema();
    final effectiveLimit = limit ?? 50;
    final sql = '''
      WITH album_rows AS (
        SELECT
          album_identity_key(t.album, t.album_artist, t.artist, t.path) AS album_key,
          MIN(COALESCE(NULLIF(TRIM(t.album), ''), 'Unknown Album')) AS album_name,
          MAX(NULLIF(TRIM(t.album_artist), '')) AS album_artist,
          MAX(t.year) AS release_year,
          COUNT(*) AS track_count,
          MAX(t.cover_key) AS cover_key,
          COUNT(DISTINCT NULLIF(t.artist, '')) AS distinct_artist_count,
          MIN(NULLIF(t.artist, '')) AS single_artist,
          MAX(t.added_at) AS latest_added_at,
          COALESCE(GROUP_CONCAT(DISTINCT NULLIF(t.album_artist, '')), '') || ' ' ||
          COALESCE(GROUP_CONCAT(DISTINCT NULLIF(t.artist, '')), '') AS raw_artists_text
        FROM main.tracks t
        GROUP BY album_key
      ),
      album_artists AS (
        SELECT
          album_identity_key(t.album, t.album_artist, t.artist, t.path) AS album_key,
          COALESCE(GROUP_CONCAT(DISTINCT ta.artist_name), '') || ' ' ||
          COALESCE(GROUP_CONCAT(DISTINCT aa.canonical_name), '') AS linked_artists_text
        FROM main.track_artists ta
        JOIN main.tracks t ON t.id = ta.track_id
        LEFT JOIN $u.artist_aliases aa ON aa.canonical_key = ta.artist_key
        GROUP BY album_key
      ),
      searchable_albums AS (
        SELECT
          ar.*,
          normalize_text(
            ar.album_name || ' ' ||
            ar.raw_artists_text || ' ' ||
            COALESCE(aar.linked_artists_text, '')
          ) AS searchable
        FROM album_rows ar
        LEFT JOIN album_artists aar ON aar.album_key = ar.album_key
      )
      SELECT
        album_key,
        album_name,
        album_artist,
        release_year,
        track_count,
        cover_key,
        distinct_artist_count,
        single_artist,
        latest_added_at
      FROM searchable_albums
      WHERE $whereClauses
      ORDER BY album_name COLLATE NOCASE ASC
      LIMIT ?;
    ''';

    final params = <Object?>[];
    for (final t in terms) {
      params.add('%${SqliteRowMappers.escapeLike(t)}%');
    }
    params.add(effectiveLimit);

    final rows = _db.select(sql, params);
    return rows.map(SqliteRowMappers.mapAlbum).toList();
  }

  Future<int> albumCount() async {
    final row = _db.select('''
      SELECT COUNT(*) AS total FROM (
        SELECT 1 FROM main.tracks
        GROUP BY album_identity_key(album, album_artist, artist, path)
      );
    ''').first;
    return row['total'] as int;
  }
}
