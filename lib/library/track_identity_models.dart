/// Domain models for stable track identities (`track_identity`) and relinking.
library;

/// Persistent stable identity for a track across file moves, renames, and
/// temporary unavailability.
class TrackIdentity {
  /// Random 128-bit lowercase hexadecimal identifier.
  final String uid;

  /// Latest known filesystem path (or URI) for this track.
  final String path;

  /// File size in bytes when last seen, if known.
  final int? sizeBytes;

  /// Track duration in milliseconds when last seen, if known.
  final int? durationMs;

  /// Normalized title key (`TextNormalizer.normalize`).
  final String? titleKey;

  /// Normalized artist key (`TextNormalizer.normalize`).
  final String? artistKey;

  /// Normalized album key (`TextNormalizer.normalize`).
  final String? albumKey;

  /// UTC epoch milliseconds when this identity was first recorded.
  final int firstSeenMs;

  /// UTC epoch milliseconds when this identity was last confirmed present.
  final int lastSeenMs;

  /// UTC epoch milliseconds when the file went missing, or null when present.
  final int? missingSinceMs;

  /// Creates an immutable [TrackIdentity].
  const TrackIdentity({
    required this.uid,
    required this.path,
    this.sizeBytes,
    this.durationMs,
    this.titleKey,
    this.artistKey,
    this.albumKey,
    required this.firstSeenMs,
    required this.lastSeenMs,
    this.missingSinceMs,
  });

  /// Whether this track is currently marked missing.
  bool get isMissing => missingSinceMs != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackIdentity &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          path == other.path &&
          sizeBytes == other.sizeBytes &&
          durationMs == other.durationMs &&
          titleKey == other.titleKey &&
          artistKey == other.artistKey &&
          albumKey == other.albumKey &&
          firstSeenMs == other.firstSeenMs &&
          lastSeenMs == other.lastSeenMs &&
          missingSinceMs == other.missingSinceMs;

  @override
  int get hashCode => Object.hash(
        uid,
        path,
        sizeBytes,
        durationMs,
        titleKey,
        artistKey,
        albumKey,
        firstSeenMs,
        lastSeenMs,
        missingSinceMs,
      );
}

/// Summary of an identity reconciliation / relink pass.
class RelinkReport {
  /// New identities created for newly seen tracks.
  final int created;

  /// Existing identities refreshed at their matching path.
  final int refreshed;

  /// Missing identities relinked to moved/renamed tracks.
  final int relinked;

  /// Identities newly marked missing (`missing_since_ms` set).
  final int markedMissing;

  /// Ambiguous candidate sets skipped without relinking.
  final int ambiguousCount;

  /// Legacy user-data paths backfilled with identities.
  final int backfilledUserPaths;

  /// Creates a [RelinkReport].
  const RelinkReport({
    this.created = 0,
    this.refreshed = 0,
    this.relinked = 0,
    this.markedMissing = 0,
    this.ambiguousCount = 0,
    this.backfilledUserPaths = 0,
  });

  /// Empty no-op report.
  static const RelinkReport empty = RelinkReport();
}
