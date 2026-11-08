/// Injectable HTTP client abstraction for network lyrics lookup.
library;

import 'dart:convert';
import 'dart:io';

/// Response representation for lyrics HTTP requests.
class LyricsHttpResponse {
  /// HTTP status code (e.g. 200, 404, 500).
  final int statusCode;

  /// Response body text decoded as UTF-8.
  final String body;

  /// Creates a [LyricsHttpResponse].
  const LyricsHttpResponse({
    required this.statusCode,
    required this.body,
  });
}

/// Abstract contract for HTTP GET calls in lyrics lookups.
abstract class LyricsHttp {
  /// Performs an HTTP GET request to [uri].
  Future<LyricsHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  });
}

/// Production implementation of [LyricsHttp] using [dart:io] [HttpClient].
///
/// Restricted strictly to `https://lrclib.net` with an 8-second timeout,
/// no redirects, and identifying User-Agent `Aestheticy/1 (by mido)`.
class DefaultLyricsHttp implements LyricsHttp {
  /// User-Agent header value sent on all outgoing requests.
  static const String userAgent = 'Aestheticy/1 (by mido)';

  /// Creates a [DefaultLyricsHttp] client.
  const DefaultLyricsHttp();

  @override
  Future<LyricsHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // Security enforcements: HTTPS only, lrclib.net only
    if (uri.scheme != 'https' || uri.host != 'lrclib.net') {
      throw ArgumentError(
        'Forbidden lyrics host or scheme: Only https://lrclib.net is allowed.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      if (headers != null) {
        headers.forEach((k, v) => request.headers.set(k, v));
      }

      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join().timeout(timeout);

      return LyricsHttpResponse(
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }
}
