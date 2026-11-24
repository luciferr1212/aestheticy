import 'package:sqlite3/sqlite3.dart';

import 'package:aestheticy/library/album_identity.dart';
import 'package:aestheticy/library/file_path_utils.dart';
import 'package:aestheticy/library/migrations.dart';
import 'package:aestheticy/library/text_normalizer.dart';

/// Applies schema migrations and registers custom SQLite scalar functions.
class SqliteDbInitializer {
  const SqliteDbInitializer._();

  /// Initializes [db] with migrations and custom SQLite functions.
  static void init(Database db) {
    SchemaMigrator.apply(db);
    db.createFunction(
      functionName: 'normalize_text',
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (args) {
        final val = args[0];
        if (val == null) return '';
        return TextNormalizer.normalize(val.toString());
      },
    );
    db.createFunction(
      functionName: 'album_identity_key',
      argumentCount: const AllowedArgumentCount(4),
      deterministic: true,
      directOnly: false,
      function: (args) {
        return AlbumIdentity.key(
          album: args[0]?.toString(),
          albumArtist: args[1]?.toString(),
          artist: args[2]?.toString(),
          trackPath: args[3]?.toString(),
        );
      },
    );
    db.createFunction(
      functionName: 'normalize_file_path',
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (args) {
        final val = args[0];
        if (val == null) return '';
        return FilePathUtils.canonicalKey(val.toString());
      },
    );
  }
}
