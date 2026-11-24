import 'package:flutter/material.dart';

import '../../library/text_normalizer.dart';
import '../artist_names/artist_name_store.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Displays and edits display-only artist name translations in [SettingsView].
class ArtistNameTranslationsPanel extends StatefulWidget {
  /// Backing store for localized artist display names.
  final ArtistNameStore nameStore;

  /// Creates an [ArtistNameTranslationsPanel].
  const ArtistNameTranslationsPanel({
    super.key,
    required this.nameStore,
  });

  @override
  State<ArtistNameTranslationsPanel> createState() =>
      _ArtistNameTranslationsPanelState();
}

class _ArtistNameTranslationsPanelState
    extends State<ArtistNameTranslationsPanel> {
  final TextEditingController _originalController = TextEditingController();
  final TextEditingController _arController = TextEditingController();
  final TextEditingController _enController = TextEditingController();

  String? _addErrorKey;

  @override
  void dispose() {
    _originalController.dispose();
    _arController.dispose();
    _enController.dispose();
    super.dispose();
  }

  void _clearAddError() {
    if (_addErrorKey != null) {
      setState(() => _addErrorKey = null);
    }
  }

  void _submitAdd() {
    final original = _originalController.text.trim();
    final ar = _arController.text.trim();
    final en = _enController.text.trim();

    if (original.isEmpty) {
      setState(() => _addErrorKey = 'settings.artistValidationEmptyOriginal');
      return;
    }
    if (ar.isEmpty && en.isEmpty) {
      setState(
        () => _addErrorKey = 'settings.artistValidationEmptyTranslation',
      );
      return;
    }
    if (widget.nameStore.getEntry(original) != null) {
      setState(() => _addErrorKey = 'settings.artistValidationDuplicate');
      return;
    }

    widget.nameStore.setEntry(original, ar: ar, en: en);
    _originalController.clear();
    _arController.clear();
    _enController.clear();
    setState(() => _addErrorKey = null);
  }

  Future<void> _openEditDialog(ArtistDisplayNameEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _EditArtistTranslationDialog(
        entry: entry,
        nameStore: widget.nameStore,
      ),
    );
  }

  void _removeWithUndo(ArtistDisplayNameEntry entry) {
    final messenger = ScaffoldMessenger.of(context);
    final removedMsg = context.t(
      'settings.artistRemovedMessage',
      args: {'name': entry.original},
    );
    final undoLabel = context.t('settings.artistUndo');

    widget.nameStore.removeEntry(entry.original);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(removedMsg),
        action: SnackBarAction(
          label: undoLabel,
          onPressed: () {
            widget.nameStore.setEntry(
              entry.original,
              ar: entry.ar,
              en: entry.en,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAddForm(context),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: widget.nameStore,
          builder: (context, _) {
            final entries = widget.nameStore.entries.take(200).toList();
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.t('settings.artistNoEntries'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _ArtistNameEntryRow(
                    key: ValueKey(
                      'artist_name_row_${TextNormalizer.normalize(entry.original)}',
                    ),
                    entry: entry,
                    onEdit: () => _openEditDialog(entry),
                    onRemove: () => _removeWithUndo(entry),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAddForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 560;
          final originalField = _ArtistInputField(
            fieldKey: const Key('settings_artist_add_original_field'),
            controller: _originalController,
            hintText: context.t('settings.artistOriginalName'),
            onChanged: (_) => _clearAddError(),
            onSubmitted: (_) => _submitAdd(),
          );
          final arField = _ArtistInputField(
            fieldKey: const Key('settings_artist_add_ar_field'),
            controller: _arController,
            hintText: context.t('settings.artistArabicName'),
            onChanged: (_) => _clearAddError(),
            onSubmitted: (_) => _submitAdd(),
          );
          final enField = _ArtistInputField(
            fieldKey: const Key('settings_artist_add_en_field'),
            controller: _enController,
            hintText: context.t('settings.artistEnglishName'),
            onChanged: (_) => _clearAddError(),
            onSubmitted: (_) => _submitAdd(),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('settings.artistAddTranslation'),
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (isWide)
                Row(
                  children: [
                    Expanded(child: originalField),
                    const SizedBox(width: 8),
                    Expanded(child: arField),
                    const SizedBox(width: 8),
                    Expanded(child: enField),
                  ],
                )
              else ...[
                originalField,
                const SizedBox(height: 8),
                arField,
                const SizedBox(height: 8),
                enField,
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _addErrorKey != null
                        ? Text(
                            context.t(_addErrorKey!),
                            key: const Key('settings_artist_add_error'),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.danger,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  GlassPillButton(
                    key: const Key('settings_artist_add_submit_button'),
                    label: context.t('settings.artistAddAction'),
                    onPressed: _submitAdd,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ArtistNameEntryRow extends StatelessWidget {
  final ArtistDisplayNameEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ArtistNameEntryRow({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final normKey = TextNormalizer.normalize(entry.original);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(AppSpacing.r10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.original,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body,
                ),
                if (entry.ar.isNotEmpty || entry.en.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      if (entry.ar.isNotEmpty)
                        Text(
                          entry.ar,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                      if (entry.en.isNotEmpty)
                        Text(
                          entry.en,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlassIconButton(
            key: ValueKey('artist_name_edit_$normKey'),
            icon: Icons.edit_outlined,
            tooltip: context.t('settings.artistEditTooltip'),
            semanticLabel: context.t('settings.artistEditTooltip'),
            size: GlassButtonSize.small,
            onPressed: onEdit,
          ),
          const SizedBox(width: 6),
          GlassIconButton(
            key: ValueKey('artist_name_remove_$normKey'),
            icon: Icons.delete_outline,
            tooltip: context.t('settings.artistRemoveTooltip'),
            semanticLabel: context.t('settings.artistRemoveTooltip'),
            size: GlassButtonSize.small,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _EditArtistTranslationDialog extends StatefulWidget {
  final ArtistDisplayNameEntry entry;
  final ArtistNameStore nameStore;

  const _EditArtistTranslationDialog({
    required this.entry,
    required this.nameStore,
  });

  @override
  State<_EditArtistTranslationDialog> createState() =>
      _EditArtistTranslationDialogState();
}

class _EditArtistTranslationDialogState
    extends State<_EditArtistTranslationDialog> {
  late final TextEditingController _originalController;
  late final TextEditingController _arController;
  late final TextEditingController _enController;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _originalController = TextEditingController(text: widget.entry.original);
    _arController = TextEditingController(text: widget.entry.ar);
    _enController = TextEditingController(text: widget.entry.en);
  }

  @override
  void dispose() {
    _originalController.dispose();
    _arController.dispose();
    _enController.dispose();
    super.dispose();
  }

  void _save() {
    final original = _originalController.text.trim();
    final ar = _arController.text.trim();
    final en = _enController.text.trim();

    if (original.isEmpty) {
      setState(() => _errorKey = 'settings.artistValidationEmptyOriginal');
      return;
    }
    if (ar.isEmpty && en.isEmpty) {
      setState(() => _errorKey = 'settings.artistValidationEmptyTranslation');
      return;
    }

    final oldKey = TextNormalizer.normalize(widget.entry.original);
    final newKey = TextNormalizer.normalize(original);
    if (newKey != oldKey && widget.nameStore.getEntry(original) != null) {
      setState(() => _errorKey = 'settings.artistValidationDuplicate');
      return;
    }

    if (original != widget.entry.original) {
      widget.nameStore.removeEntry(widget.entry.original);
    }
    widget.nameStore.setEntry(original, ar: ar, en: en);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassSurface(
          borderRadius: AppSpacing.r16,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('settings.artistEditTitle'),
                style: AppTypography.title,
              ),
              const SizedBox(height: 14),
              _ArtistInputField(
                fieldKey: const Key('settings_artist_edit_original_field'),
                controller: _originalController,
                hintText: context.t('settings.artistOriginalName'),
                labelText: context.t('settings.artistOriginalName'),
                onChanged: (_) => setState(() => _errorKey = null),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 10),
              _ArtistInputField(
                fieldKey: const Key('settings_artist_edit_ar_field'),
                controller: _arController,
                hintText: context.t('settings.artistArabicName'),
                labelText: context.t('settings.artistArabicName'),
                onChanged: (_) => setState(() => _errorKey = null),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 10),
              _ArtistInputField(
                fieldKey: const Key('settings_artist_edit_en_field'),
                controller: _enController,
                hintText: context.t('settings.artistEnglishName'),
                labelText: context.t('settings.artistEnglishName'),
                onChanged: (_) => setState(() => _errorKey = null),
                onSubmitted: (_) => _save(),
              ),
              if (_errorKey != null) ...[
                const SizedBox(height: 10),
                Text(
                  context.t(_errorKey!),
                  key: const Key('settings_artist_edit_error'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GlassPillButton(
                    key: const Key('settings_artist_edit_cancel_button'),
                    label: context.t('common.cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  GlassPillButton(
                    key: const Key('settings_artist_edit_save_button'),
                    label: context.t('settings.artistSave'),
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistInputField extends StatelessWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _ArtistInputField({
    required this.fieldKey,
    required this.controller,
    required this.hintText,
    this.labelText,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      style: AppTypography.body,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.fillGlass,
        labelText: labelText,
        labelStyle: AppTypography.caption.copyWith(color: AppColors.textMuted),
        hintText: hintText,
        hintStyle: AppTypography.caption.copyWith(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.r10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.r10),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.r10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}
