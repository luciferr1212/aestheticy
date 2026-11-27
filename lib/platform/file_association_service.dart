/// Abstract interface for OS file-extension association management
/// (e.g. registering `.mp3`/`.flac` open-with handlers on Windows).
abstract class FileAssociationService {
  /// Whether this platform supports file-association registration.
  bool get isSupported;

  /// Returns whether Aestheticy is registered for [extension] (e.g. `.mp3`).
  Future<bool> isRegistered(String extension);

  /// Requests registration for the given audio file [extensions].
  Future<bool> registerExtensions(List<String> extensions);
}
