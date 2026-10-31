/// Audio file metadata tag reader interface and implementations.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Raw audio tags extracted directly from a file before domain normalization.
class RawTags {
  /// Track title.
  final String? title;

  /// Primary performing artist.
  final String? artist;

  /// Album-level artist (e.g. for compilations).
  final String? albumArtist;

  /// Album title.
  final String? album;

  /// Track position index on the disc.
  final int? trackNo;

  /// Disc index in multi-disc releases.
  final int? discNo;

  /// Release year.
  final int? year;

  /// Audio duration in milliseconds, if available from headers.
  final int? durationMs;

  /// Embedded front album artwork image bytes, if present.
  final Uint8List? embeddedCover;

  /// Creates a [RawTags] container.
  const RawTags({
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.trackNo,
    this.discNo,
    this.year,
    this.durationMs,
    this.embeddedCover,
  });

  @override
  String toString() =>
      'RawTags(title: $title, artist: $artist, album: $album, trackNo: $trackNo, year: $year, durationMs: $durationMs)';
}

/// Abstract contract for reading audio metadata tags from local audio files.
abstract class TagReader {
  /// Reads metadata tags from [filePath].
  ///
  /// Set [readCover] to `false` to skip extracting embedded image bytes for faster parsing.
  FutureOr<RawTags> readTags(String filePath, {bool readCover = true});
}

/// Pure Dart [TagReader] implementation powered by `audio_metadata_reader`.
class AudioMetadataTagReader implements TagReader {
  /// Creates an [AudioMetadataTagReader].
  const AudioMetadataTagReader();

  @override
  RawTags readTags(String filePath, {bool readCover = true}) {
    final file = File(filePath);
    final metadata = readMetadata(file, getImage: readCover);

    Uint8List? coverBytes;
    if (readCover && metadata.pictures.isNotEmpty) {
      // Prefer front cover if present, otherwise take the first available image.
      final front = metadata.pictures
          .where((p) => p.pictureType == PictureType.coverFront)
          .firstOrNull;
      coverBytes = (front ?? metadata.pictures.first).bytes;
    }

    final trimmedTitle = metadata.title?.trim();
    final trimmedArtist = metadata.artist?.trim();
    final trimmedAlbumArtist = metadata.albumArtist?.trim();
    final trimmedAlbum = metadata.album?.trim();

    return RawTags(
      title: trimmedTitle != null && trimmedTitle.isNotEmpty ? trimmedTitle : null,
      artist: trimmedArtist != null && trimmedArtist.isNotEmpty ? trimmedArtist : null,
      albumArtist: trimmedAlbumArtist != null && trimmedAlbumArtist.isNotEmpty
          ? trimmedAlbumArtist
          : null,
      album: trimmedAlbum != null && trimmedAlbum.isNotEmpty ? trimmedAlbum : null,
      trackNo: metadata.trackNumber,
      discNo: metadata.discNumber,
      year: metadata.year?.year,
      durationMs: metadata.duration?.inMilliseconds,
      embeddedCover: coverBytes,
    );
  }
}
