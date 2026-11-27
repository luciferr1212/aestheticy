import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fallback screen shown when the audio engine fails to initialize.
class AudioInitErrorApp extends StatelessWidget {
  /// The error description.
  final String error;

  /// The stack trace, if available.
  final String stackTrace;

  /// Creates an [AudioInitErrorApp].
  const AudioInitErrorApp({
    super.key,
    required this.error,
    this.stackTrace = '',
  });

  @override
  Widget build(BuildContext context) {
    final fullError = stackTrace.isNotEmpty ? '$error\n\n$stackTrace' : error;

    return MaterialApp(
      title: 'Aestheticy — Audio Error',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Aestheticy / by mido'),
          backgroundColor: const Color(0xFF1E1E1E),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Audio Engine Initialization Failed',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The audio engine (libmpv) could not be loaded or initialized on this device. '
                    'Please copy the error log below and report it:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        fullError,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (ctx) => ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullError));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Error copied to clipboard!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy Error Log'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fallback screen shown when the library database fails to open.
class LibraryInitErrorApp extends StatelessWidget {
  /// The error description.
  final String error;

  /// The stack trace, if available.
  final String stackTrace;

  /// Creates a [LibraryInitErrorApp].
  const LibraryInitErrorApp({
    super.key,
    required this.error,
    this.stackTrace = '',
  });

  @override
  Widget build(BuildContext context) {
    final fullError = stackTrace.isNotEmpty ? '$error\n\n$stackTrace' : error;

    return MaterialApp(
      title: 'Aestheticy — Database Error',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Aestheticy / by mido'),
          backgroundColor: const Color(0xFF1E1E1E),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.folder_off, color: Colors.redAccent, size: 36),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Library database failed to open',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The local library database could not be opened or migrated on this device. '
                    'Please copy the error log below and report it:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        fullError,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (ctx) => ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullError));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Error copied to clipboard!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy Error Log'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
