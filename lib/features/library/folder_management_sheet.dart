/// Folder management bottom sheet / dialog for managing library folders and scans.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';
import 'package:aestheticy/library/scan_service.dart';

/// Modal view displaying library folders, rescan controls, and scanning progress.
class FolderManagementSheet extends StatefulWidget {
  /// The underlying library repository.
  final LibraryRepository repository;

  /// The active scan service coordinating directory scans.
  final ScanService scanService;

  /// Optional injected directory picker for unit and widget tests.
  final Future<String?> Function()? directoryPicker;

  /// Creates a [FolderManagementSheet].
  const FolderManagementSheet({
    super.key,
    required this.repository,
    required this.scanService,
    this.directoryPicker,
  });

  /// Shows the folder management dialog.
  static Future<void> show(
    BuildContext context, {
    required LibraryRepository repository,
    required ScanService scanService,
    Future<String?> Function()? directoryPicker,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => FolderManagementSheet(
        repository: repository,
        scanService: scanService,
        directoryPicker: directoryPicker,
      ),
    );
  }

  @override
  State<FolderManagementSheet> createState() => _FolderManagementSheetState();
}

class _FolderManagementSheetState extends State<FolderManagementSheet> {
  List<LibraryFolder> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    widget.scanService.addListener(_onScanChanged);
  }

  @override
  void dispose() {
    widget.scanService.removeListener(_onScanChanged);
    super.dispose();
  }

  void _onScanChanged() {
    if (mounted) {
      _loadFolders();
    }
  }

  Future<void> _loadFolders() async {
    final folders = await widget.repository.listFolders();
    if (mounted) {
      setState(() {
        _folders = folders;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndAddFolder() async {
    try {
      final picker = widget.directoryPicker ?? FilePicker.getDirectoryPath;
      final selectedPath = await picker();
      if (selectedPath != null && selectedPath.isNotEmpty) {
        await widget.scanService.addFolder(selectedPath);
        await _loadFolders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding folder: $e')),
        );
      }
    }
  }

  Future<void> _removeFolder(LibraryFolder folder) async {
    if (folder.id == null) return;
    await widget.repository.removeFolder(folder.id!);
    await _loadFolders();
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Never scanned';
    final local = dt.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final isScanning = widget.scanService.isScanning;
    final progress = widget.scanService.currentProgress;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_special, size: 22, color: Color(0xFFC3B1E1)),
              const SizedBox(width: 10),
              Text(
                'Music Folders',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action buttons: Add folder & Rescan
          Row(
            children: [
              ElevatedButton.icon(
                key: const Key('add_folder_button'),
                onPressed: isScanning ? null : _pickAndAddFolder,
                icon: const Icon(Icons.create_new_folder, size: 18),
                label: const Text('Add folder'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('rescan_button'),
                onPressed: isScanning || _folders.isEmpty
                    ? null
                    : () async {
                        await widget.scanService.rescanAll();
                        await _loadFolders();
                      },
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Rescan'),
              ),
            ],
          ),
          if (isScanning) ...[
            const SizedBox(height: 16),
            Card(
              color: const Color(0xFF2A2A2E),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            progress.found > 0
                                ? 'Scanning: ${progress.processed} / ${progress.found} files'
                                : 'Discovering audio files...',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                        TextButton(
                          key: const Key('scan_cancel_button'),
                          onPressed: () => widget.scanService.cancel(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress.found > 0
                          ? (progress.processed / progress.found).clamp(0.0, 1.0)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Added: ${progress.added} • Updated: ${progress.updated} • Errors: ${progress.errors}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_folders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No folders added yet. Click "Add folder" to scan music.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _folders.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final folder = _folders[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder, color: Color(0xFFC3B1E1)),
                      title: Text(
                        folder.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Last scan: ${_formatDateTime(folder.lastScanAt)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        tooltip: 'Remove folder',
                        onPressed: isScanning ? null : () => _removeFolder(folder),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
