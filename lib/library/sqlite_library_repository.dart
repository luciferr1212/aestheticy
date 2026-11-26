/// SQLite-backed implementation of [LibraryRepository].
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/diagnostics/app_logger.dart';
import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/sqlite/database_protection.dart';
import 'package:aestheticy/library/sqlite/legacy_userdata_migrator.dart';
import 'package:aestheticy/library/sqlite/sqlite_albums_store.dart';
import 'package:aestheticy/library/sqlite/sqlite_artists_store.dart';
import 'package:aestheticy/library/sqlite/sqlite_collections_store.dart';
import 'package:aestheticy/library/sqlite/sqlite_db_initializer.dart';
import 'package:aestheticy/library/sqlite/sqlite_history_store.dart';
import 'package:aestheticy/library/sqlite/sqlite_tracks_store.dart';
import 'package:aestheticy/library/sqlite/userdata_backup_service.dart';
import 'package:aestheticy/library/sqlite/userdata_migrator.dart';
import 'package:aestheticy/library/user_data_access_mode.dart';

/// SQLite storage implementation for the music library and user data.
class SqliteLibraryRepository implements LibraryRepository {
  final Database _db;

  /// Resolved path to `library.db`, or null for in-memory instances.
  final String? libraryFilePath;

  /// Resolved path to `userdata.db`, or null for in-memory instances.
  final String? userDataFilePath;

  final Directory? _backupsDirectory;
  final UserDataAccessMode _userDataAccessMode;

  /// Active SQLite schema name holding user data (`'userdata'` normally, or
  /// `'main'` in safe read-only fallback before legacy table rename).
  final String userDataSchema;
  final DatabaseStartupReport _startupReport;
  bool _migrationAttemptedInRun = false;

  late final SqliteTracksStore _tracks;
  late final SqliteAlbumsStore _albums;
  late final SqliteArtistsStore _artists;
  late final SqliteCollectionsStore _collections;
  late final SqliteHistoryStore _history;

  SqliteLibraryRepository._(
    this._db, {
    this.libraryFilePath,
    this.userDataFilePath,
    Directory? backupsDirectory,
    UserDataAccessMode userDataAccessMode = UserDataAccessMode.normal,
    this.userDataSchema = 'userdata',
    DatabaseStartupReport? startupReport,
    bool migrationAttempted = true,
  })  : _backupsDirectory = backupsDirectory,
        _userDataAccessMode = userDataAccessMode,
        _migrationAttemptedInRun = migrationAttempted,
        _startupReport = startupReport ??
            DatabaseStartupReport(
              accessMode: userDataAccessMode,
              backupsDirectory: backupsDirectory,
            ) {
    String schemaProvider() => userDataSchema;
    UserDataAccessMode modeProvider() => _userDataAccessMode;
    _tracks = SqliteTracksStore(_db, userSchema: schemaProvider);
    _albums = SqliteAlbumsStore(_db, userSchema: schemaProvider);
    _artists = SqliteArtistsStore(
      _db,
      userSchema: schemaProvider,
      accessMode: modeProvider,
    );
    _collections = SqliteCollectionsStore(
      _db,
      userSchema: schemaProvider,
      accessMode: modeProvider,
    );
    _history = SqliteHistoryStore(
      _db,
      userSchema: schemaProvider,
      accessMode: modeProvider,
    );
  }

  /// Effective user-data access mode for this repository.
  @override
  UserDataAccessMode get userDataAccessMode => _userDataAccessMode;

  /// Startup corruption/recovery/access report for this repository.
  DatabaseStartupReport get startupReport => _startupReport;

  /// Underlying SQLite connection (visible for testing and backup service).
  @visibleForTesting
  Database get rawDatabase => _db;

  /// Resolved `backups/` directory under `Aestheticy`, or null for in-memory.
  Directory? get backupsDirectory => _backupsDirectory;

  /// Creates a [SqliteUserDataBackupService] bound to this file-backed
  /// repository, or `null` for in-memory databases.
  SqliteUserDataBackupService? createBackupService({DateTime Function()? clock}) {
    final userPath = userDataFilePath;
    final backupsDir = _backupsDirectory;
    if (userPath == null || backupsDir == null) return null;
    return SqliteUserDataBackupService(
      backupsUserDataDir: Directory(p.join(backupsDir.path, 'userdata')),
      userDataDbPath: userPath,
      databaseProvider: () => _db,
      clock: clock,
    );
  }

  /// Whether legacy migration has already been attempted in this run.
  bool get migrationAttemptedInRun => _migrationAttemptedInRun;

  /// Attempts to retry legacy migration at most once per app start.
  ///
  /// Always returns `false` once migration has already been attempted in the
  /// current run (e.g. when already in [UserDataAccessMode.safeReadOnly]).
  Future<bool> retryLegacyMigrationOnce() async {
    if (_migrationAttemptedInRun) {
      return false;
    }
    _migrationAttemptedInRun = true;
    final result = LegacyUserDataMigrator.run(
      _db,
      libraryFilePath: libraryFilePath,
      backupsDir: _backupsDirectory,
    );
    return result.accessMode == UserDataAccessMode.normal;
  }

  /// Opens an in-memory SQLite database with an attached in-memory `userdata`
  /// database, applying schema migrations to both.
  ///
  /// Primarily intended for isolated unit testing.
  factory SqliteLibraryRepository.inMemory() {
    final db = sqlite3.openInMemory();
    SqliteDbInitializer.init(db, attachMemoryUserData: true);
    LegacyUserDataMigrator.run(db);
    return SqliteLibraryRepository._(db);
  }

  /// Opens or creates `library.db` at [filePath] and attaches `userdata.db`
  /// in the same directory (or [userDataPath] if provided), running integrity
  /// checks (`PRAGMA quick_check`), WAL setup, corruption recovery, and
  /// crash-recoverable legacy migration.
  factory SqliteLibraryRepository.openFile(
    String filePath, {
    String? userDataPath,
    Directory? backupsDir,
    DateTime Function()? clock,
    void Function(int fromVersion, int toVersion)? onBeforeUserDataUpgrade,
    @visibleForTesting LegacyMigrationTestHooks? migrationHooks,
  }) {
    final file = File(filePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final resolvedUserDataPath =
        userDataPath ?? p.join(file.parent.path, 'userdata.db');
    final resolvedBackupsDir =
        backupsDir ?? Directory(p.join(file.parent.path, 'backups'));
    final resolvedUserDataBackupsDir =
        Directory(p.join(resolvedBackupsDir.path, 'userdata'));

    // Ensure parent dir for userdata.db if creatable; failure enters safeReadOnly.
    var userDataParentError = false;
    String? parentErrorReason;
    final userFile = File(resolvedUserDataPath);
    try {
      if (!userFile.parent.existsSync()) {
        userFile.parent.createSync(recursive: true);
      }
    } catch (e) {
      userDataParentError = true;
      parentErrorReason = 'Cannot prepare userdata directory: $e';
      AppLogger.instance.error('Database', parentErrorReason);
    }

    final libPrep = DatabaseProtection.prepareLibraryDb(
      filePath,
      clock: clock,
    );
    final userPrep = userDataParentError
        ? (
            restoredFromBackup: false,
            resetEmpty: false,
            safeReadOnly: true,
            error: parentErrorReason,
          )
        : DatabaseProtection.prepareUserDataDb(
            userDataPath: resolvedUserDataPath,
            backupsUserDataDir: resolvedUserDataBackupsDir,
            clock: clock,
          );

    if (userPrep.safeReadOnly) {
      return _openFileSafeReadOnlyFallback(
        filePath: filePath,
        userDataPath: resolvedUserDataPath,
        backupsDir: resolvedBackupsDir,
        libraryRecreated: libPrep.recreated,
        reason: userPrep.error ?? 'userdata.db could not be opened or restored',
      );
    }

    final db = sqlite3.open(filePath);
    try {
      final escapedUserDataPath = resolvedUserDataPath.replaceAll("'", "''");
      db.execute("ATTACH DATABASE '$escapedUserDataPath' AS userdata;");
      DatabaseProtection.enableWalForFileDbs(db, hasFileUserData: true);
      final effectiveUpgradeHook = onBeforeUserDataUpgrade ??
          (fromVersion, toVersion) {
            SqliteUserDataBackupService(
              backupsUserDataDir: resolvedUserDataBackupsDir,
              userDataDbPath: resolvedUserDataPath,
              databaseProvider: () => db,
              clock: clock,
            ).backupBeforeSchemaMigrationSync(
              fromVersion: fromVersion,
              toVersion: toVersion,
            );
          };
      SqliteDbInitializer.init(
        db,
        applyUserDataSchema: false,
        onBeforeUserDataUpgrade: effectiveUpgradeHook,
      );

      final migrationResult = LegacyUserDataMigrator.run(
        db,
        libraryFilePath: filePath,
        backupsDir: resolvedBackupsDir,
        clock: clock,
        hooks: migrationHooks,
      );

      final mode = migrationResult.accessMode;
      final schema = migrationResult.readLegacyFromMain ? 'main' : 'userdata';
      final report = DatabaseStartupReport(
        accessMode: mode,
        libraryRecreatedAfterCorruption: libPrep.recreated,
        userDataRestoredFromBackup: userPrep.restoredFromBackup,
        userDataResetEmptyAfterCorruption: userPrep.resetEmpty,
        safeReadOnlyReason: migrationResult.failureReason,
        backupsDirectory: resolvedBackupsDir,
        logsDirectory: AppLogger.instance.logDirectory,
      );

      return SqliteLibraryRepository._(
        db,
        libraryFilePath: filePath,
        userDataFilePath: resolvedUserDataPath,
        backupsDirectory: resolvedBackupsDir,
        userDataAccessMode: mode,
        userDataSchema: schema,
        startupReport: report,
      );
    } on SimulatedCrashException {
      db.close();
      rethrow;
    } on SqliteException catch (e, st) {
      AppLogger.instance.error(
        'Database',
        'Failed opening/migrating userdata.db; entering safe read-only mode: $e',
        e,
        st,
      );
      db.close();
      return _openFileSafeReadOnlyFallback(
        filePath: filePath,
        userDataPath: resolvedUserDataPath,
        backupsDir: resolvedBackupsDir,
        libraryRecreated: libPrep.recreated,
        reason: e.toString(),
      );
    } on FileSystemException catch (e, st) {
      AppLogger.instance.error(
        'Database',
        'Filesystem error opening userdata.db; entering safe read-only mode: $e',
        e,
        st,
      );
      db.close();
      return _openFileSafeReadOnlyFallback(
        filePath: filePath,
        userDataPath: resolvedUserDataPath,
        backupsDir: resolvedBackupsDir,
        libraryRecreated: libPrep.recreated,
        reason: e.toString(),
      );
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static SqliteLibraryRepository _openFileSafeReadOnlyFallback({
    required String filePath,
    required String userDataPath,
    required Directory backupsDir,
    required bool libraryRecreated,
    required String reason,
  }) {
    final db = sqlite3.open(filePath);
    try {
      DatabaseProtection.enableWalForFileDbs(db, hasFileUserData: false);
      SqliteDbInitializer.init(
        db,
        attachMemoryUserData: true,
        applyUserDataSchema: true,
      );
      final mainTables = db
          .select("SELECT name FROM main.sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      final hasLegacyInMain = kUserDataTables.any(mainTables.contains);
      final schema = hasLegacyInMain ? 'main' : 'userdata';
      final report = DatabaseStartupReport(
        accessMode: UserDataAccessMode.safeReadOnly,
        libraryRecreatedAfterCorruption: libraryRecreated,
        safeReadOnlyReason: reason,
        backupsDirectory: backupsDir,
        logsDirectory: AppLogger.instance.logDirectory,
      );
      return SqliteLibraryRepository._(
        db,
        libraryFilePath: filePath,
        userDataFilePath: userDataPath,
        backupsDirectory: backupsDir,
        userDataAccessMode: UserDataAccessMode.safeReadOnly,
        userDataSchema: schema,
        startupReport: report,
      );
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// Wraps an existing [Database] instance, attaching `:memory:` as `userdata`
  /// if not already attached, and applying schema + legacy migrations.
  factory SqliteLibraryRepository.fromDatabase(Database db) {
    SqliteDbInitializer.init(
      db,
      attachMemoryUserData: true,
      applyUserDataSchema: false,
    );
    final migrationResult = LegacyUserDataMigrator.run(db);
    return SqliteLibraryRepository._(
      db,
      userDataAccessMode: migrationResult.accessMode,
      userDataSchema: migrationResult.readLegacyFromMain ? 'main' : 'userdata',
    );
  }

  /// Opens the default database files in the injected [supportDir] (or the
  /// application support directory via [supportDirProvider] / `path_provider`).
  static Future<SqliteLibraryRepository> openDefault({
    Directory? supportDir,
    Future<Directory> Function()? supportDirProvider,
    DateTime Function()? clock,
    @visibleForTesting LegacyMigrationTestHooks? migrationHooks,
  }) async {
    final baseSupportDir = supportDir ??
        await (supportDirProvider ?? getApplicationSupportDirectory)();
    final dbDir = Directory(p.join(baseSupportDir.path, 'Aestheticy'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final dbPath = p.join(dbDir.path, 'library.db');
    return SqliteLibraryRepository.openFile(
      dbPath,
      clock: clock,
      migrationHooks: migrationHooks,
    );
  }

  /// Resets the rebuildable library (`folders`, `tracks`, `track_artists`) in
  /// `library.db` without deleting any user data in `userdata.db`.
  Future<void> resetLibrary() => _tracks.resetLibrary();

  @override
  Future<LibraryFolder> addFolder(String path) => _tracks.addFolder(path);

  @override
  Future<void> removeFolder(int folderId) => _tracks.removeFolder(folderId);

  @override
  Future<List<LibraryFolder>> listFolders() => _tracks.listFolders();

  @override
  Future<void> markFolderScanned(int folderId, DateTime timestamp) =>
      _tracks.markFolderScanned(folderId, timestamp);

  @override
  Future<void> upsertTracks(List<Track> tracks) => _tracks.upsertTracks(tracks);

  @override
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> existingFiles(
    int folderId,
  ) =>
      _tracks.existingFiles(folderId);

  @override
  Future<void> removeTracksByPath(List<String> paths) =>
      _tracks.removeTracksByPath(paths);

  @override
  Future<List<AlbumSummary>> listAlbums({int? limit, int? offset}) =>
      _albums.listAlbums(limit: limit, offset: offset);

  @override
  Future<List<AlbumSummary>> listAlbumsByArtistKey(String artistKey) =>
      _albums.listAlbumsByArtistKey(artistKey);

  @override
  Future<List<AlbumSummary>> listAlbumsByArtistKeys(List<String> artistKeys) =>
      _albums.listAlbumsByArtistKeys(artistKeys);

  @override
  Future<List<ArtistSummary>> listArtists({int? limit, int? offset}) =>
      _artists.listArtists(limit: limit, offset: offset);

  @override
  Future<List<Track>> tracksOfAlbum(
    String album, {
    String? albumArtist,
    String? albumKey,
  }) =>
      _albums.tracksOfAlbum(album, albumArtist: albumArtist, albumKey: albumKey);

  @override
  Future<List<Track>> tracksOfArtist(String artist, {String? artistKey}) =>
      _artists.tracksOfArtist(artist, artistKey: artistKey);

  @override
  Future<List<Track>> listTracks({
    TrackSort sort = TrackSort.titleAsc,
    int? limit,
    int? offset,
  }) =>
      _tracks.listTracks(sort: sort, limit: limit, offset: offset);

  @override
  Future<List<Track>> search(String query) => _tracks.search(query);

  @override
  Future<List<AlbumSummary>> searchAlbums(String query, {int? limit}) =>
      _albums.searchAlbums(query, limit: limit);

  @override
  Future<List<ArtistSummary>> searchArtists(String query, {int? limit}) =>
      _artists.searchArtists(query, limit: limit);

  @override
  Future<int> albumCount() => _albums.albumCount();

  @override
  Future<int> artistCount() => _artists.artistCount();

  @override
  Future<int> trackCount() => _tracks.trackCount();

  @override
  Future<void> mergeArtists(
    String sourceKey,
    String targetKey, {
    String? targetName,
  }) =>
      _artists.mergeArtists(sourceKey, targetKey, targetName: targetName);

  @override
  Future<void> unmergeArtist(String aliasKey) =>
      _artists.unmergeArtist(aliasKey);

  @override
  Future<List<ArtistAlias>> listAliases() => _artists.listAliases();

  @override
  Future<void> addNoSplit(String name) => _artists.addNoSplit(name);

  @override
  Future<void> removeNoSplit(String key) => _artists.removeNoSplit(key);

  @override
  Future<List<ArtistNoSplit>> listNoSplit() => _artists.listNoSplit();

  @override
  Future<void> rebuildArtistLinks() => _artists.rebuildArtistLinks();

  @override
  Future<int> insertPlayEvent(PlayEvent e) => _history.insertPlayEvent(e);

  @override
  Future<void> updatePlayEvent(
    int id, {
    required int listenedMs,
    required bool counted,
    required bool completed,
  }) =>
      _history.updatePlayEvent(
        id,
        listenedMs: listenedMs,
        counted: counted,
        completed: completed,
      );

  @override
  Future<List<PlayEvent>> recentPlayEvents({int limit = 50}) =>
      _history.recentPlayEvents(limit: limit);

  @override
  Future<int> playEventCount({bool countedOnly = false}) =>
      _history.playEventCount(countedOnly: countedOnly);

  @override
  Future<void> clearPlayEvents() => _history.clearPlayEvents();

  @override
  Future<Set<String>> favoritePaths() => _collections.favoritePaths();

  @override
  Future<void> setFavorite(String path, bool value) =>
      _collections.setFavorite(path, value);

  @override
  Future<List<Track>> favoriteTracks() => _collections.favoriteTracks();

  @override
  Future<Map<String, int>> allRatings() => _collections.allRatings();

  @override
  Future<void> setRating(String path, int stars) =>
      _collections.setRating(path, stars);

  @override
  Future<PlaylistSummary> createPlaylist(String name) =>
      _collections.createPlaylist(name);

  @override
  Future<void> renamePlaylist(int id, String name) =>
      _collections.renamePlaylist(id, name);

  @override
  Future<void> deletePlaylist(int id) => _collections.deletePlaylist(id);

  @override
  Future<List<PlaylistSummary>> listPlaylists() =>
      _collections.listPlaylists();

  @override
  Future<List<PlaylistEntry>> playlistEntries(int id) =>
      _collections.playlistEntries(id);

  @override
  Future<int> addToPlaylist(int id, List<String> paths) =>
      _collections.addToPlaylist(id, paths);

  @override
  Future<void> removePlaylistEntries(int id, List<int> entryIds) =>
      _collections.removePlaylistEntries(id, entryIds);

  @override
  Future<void> movePlaylistEntry(int id, int entryId, int newPosition) =>
      _collections.movePlaylistEntry(id, entryId, newPosition);

  @override
  Future<List<Track>> recentlyPlayedTracks({int limit = 200}) =>
      _history.recentlyPlayedTracks(limit: limit);

  @override
  Future<void> close() async {
    _db.close();
  }
}
