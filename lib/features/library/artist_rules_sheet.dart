/// Sheet displaying and managing artist merge aliases and no-split rules.
library;

import 'package:flutter/material.dart';

import 'package:aestheticy/library/library_repository.dart';
import 'package:aestheticy/library/models.dart';

/// Modal bottom sheet displaying active artist rules (merges and never-split entries).
class ArtistRulesSheet extends StatefulWidget {
  /// The library storage repository.
  final LibraryRepository repository;

  /// Creates an [ArtistRulesSheet].
  const ArtistRulesSheet({super.key, required this.repository});

  /// Shows the rules sheet modally.
  static Future<void> show(
    BuildContext context, {
    required LibraryRepository repository,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ArtistRulesSheet(repository: repository),
    );
  }

  @override
  State<ArtistRulesSheet> createState() => _ArtistRulesSheetState();
}

class _ArtistRulesSheetState extends State<ArtistRulesSheet> {
  List<ArtistAlias> _aliases = [];
  List<ArtistNoSplit> _noSplits = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final aliases = await widget.repository.listAliases();
    final noSplits = await widget.repository.listNoSplit();
    if (mounted) {
      setState(() {
        _aliases = aliases;
        _noSplits = noSplits;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeAlias(String aliasKey) async {
    await widget.repository.unmergeArtist(aliasKey);
    await _loadRules();
  }

  Future<void> _removeNoSplit(String artistKey) async {
    await widget.repository.removeNoSplit(artistKey);
    await _loadRules();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag Handle
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.rule, color: Color(0xFFC3B1E1), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Artist Rules',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Manage merges and never-split artist entries • by mido',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Section: Merges
                        const Text(
                          'Merged Artists',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFC3B1E1),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_aliases.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'No merged artists.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        else
                          ..._aliases.map((alias) {
                            return Card(
                              color: const Color(0xFF222226),
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                dense: true,
                                title: Text(
                                  alias.aliasKey,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  'Merged into ${alias.canonicalName}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                trailing: IconButton(
                                  key: Key('remove_merge_${alias.aliasKey}'),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.white70,
                                  ),
                                  tooltip: 'Remove merge',
                                  onPressed: () => _removeAlias(alias.aliasKey),
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 18),
                        // Section: Never-Split
                        const Text(
                          'Never-Split Artists',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFC3B1E1),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_noSplits.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'No never-split rules.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        else
                          ..._noSplits.map((entry) {
                            return Card(
                              color: const Color(0xFF222226),
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                dense: true,
                                title: Text(
                                  entry.artistName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                trailing: IconButton(
                                  key: Key('remove_nosplit_${entry.artistKey}'),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.white70,
                                  ),
                                  tooltip: 'Remove rule',
                                  onPressed: () =>
                                      _removeNoSplit(entry.artistKey),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
