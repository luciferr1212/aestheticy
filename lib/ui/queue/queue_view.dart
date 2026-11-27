import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/audio_models.dart';
import '../../audio/playback_controller.dart';
import '../../diagnostics/app_logger.dart';
import '../../features/collections/user_collections.dart';
import '../../library/models.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'queue_content.dart';

/// Full-page interactive playback queue view.
///
/// Features active playback order, distinct entry identity, user-queue sections,
/// animated drag reordering, track jumping, track deletion, clear actions, and playlist export.
class QueueView extends StatefulWidget {
  /// The audio playback controller coordinating queue and engine.
  final PlaybackController controller;

  /// Application navigator.
  final AppNavigator navigator;

  /// User settings store.
  final SettingsStore settingsStore;

  /// User collections for favorites and playlist management.
  final UserCollections? userCollections;

  /// Creates a [QueueView].
  const QueueView({
    super.key,
    required this.controller,
    required this.navigator,
    required this.settingsStore,
    this.userCollections,
  });

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  StreamSubscription<void>? _queueSub;
  StreamSubscription<AudioSource?>? _currentSub;

  @override
  void initState() {
    super.initState();
    _queueSub = widget.controller.queueChangeStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _currentSub = widget.controller.currentStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(QueueView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _queueSub?.cancel();
      _currentSub?.cancel();
      _queueSub = widget.controller.queueChangeStream.listen((_) {
        if (mounted) setState(() {});
      });
      _currentSub = widget.controller.currentStream.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _currentSub?.cancel();
    super.dispose();
  }

  Duration _calculateUpcomingDuration(
    List<QueueEntry> entries,
    int currentIndex,
  ) {
    var totalMs = 0;
    if (currentIndex >= 0 && currentIndex < entries.length) {
      for (var i = currentIndex + 1; i < entries.length; i++) {
        final ms = int.tryParse(entries[i].source.extras?['durationMs'] ?? '');
        if (ms != null && ms > 0) totalMs += ms;
      }
    }
    return Duration(milliseconds: totalMs);
  }

  Future<void> _showClearAllDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.r16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          dialogCtx.t('queue.clearAllTitle'),
          style: AppTypography.title.copyWith(color: AppColors.text),
        ),
        content: Text(
          dialogCtx.t('queue.clearAllConfirm'),
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            key: const Key('queue_clear_all_cancel_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(dialogCtx.t('common.cancel')),
          ),
          ElevatedButton(
            key: const Key('queue_clear_all_confirm_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(dialogCtx.t('common.delete')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.controller.clearQueue();
      if (mounted) setState(() {});
    }
  }

  Future<void> _showSavePlaylistDialog() async {
    final now = DateTime.now();
    final datePart =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final defaultName =
        '${context.t('queue.defaultPlaylistPrefix')} ${context.localizeDigitsText(datePart)}';

    final collections =
        widget.userCollections ?? UserCollectionsScope.maybeOf(context);
    if (collections == null) return;

    final textCtrl = TextEditingController(text: defaultName);
    String? errorMessage;

    final created = await showDialog<PlaylistSummary>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (innerCtx, setDialogState) {
            void validateAndSubmit() async {
              final trimmed = textCtrl.text.trim();
              if (trimmed.isEmpty) {
                setDialogState(
                  () => errorMessage = innerCtx.t('playlist.nameEmpty'),
                );
                return;
              }
              if (trimmed.length > 60) {
                setDialogState(
                  () => errorMessage = innerCtx.t('playlist.nameTooLong'),
                );
                return;
              }
              final duplicate = collections.playlists.any(
                (p) => p.name.trim().toLowerCase() == trimmed.toLowerCase(),
              );
              if (duplicate) {
                setDialogState(
                  () => errorMessage = innerCtx.t('playlist.nameDuplicate'),
                );
                return;
              }

              try {
                final pl = await collections.createPlaylist(trimmed);
                final currentItems = widget.controller.queue.items;
                final paths = <String>[];
                var skippedCount = 0;

                for (final item in currentItems) {
                  final p = item.uri;
                  if (!p.startsWith('http://') && !p.startsWith('https://')) {
                    paths.add(p);
                  } else {
                    skippedCount++;
                  }
                }

                if (paths.isNotEmpty) {
                  await collections.addToPlaylist(pl.id, paths);
                }

                if (innerCtx.mounted) {
                  Navigator.of(innerCtx).pop(pl);
                  if (mounted) {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.clearSnackBars();
                    final msg = skippedCount > 0
                        ? context.t(
                            'queue.playlistSavedWithSkipped',
                            args: {
                              'name': pl.name,
                              'skipped': context.localizeDigitsText(
                                skippedCount.toString(),
                              ),
                            },
                          )
                        : context.t(
                            'queue.playlistSaved',
                            args: {'name': pl.name},
                          );
                    final actionLabel = context.t('queue.viewPlaylist');
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        action: SnackBarAction(
                          label: actionLabel,
                          onPressed: () {
                            widget.navigator
                                .openPlaylistDetail(pl.id, playlist: pl);
                          },
                        ),
                      ),
                    );
                  }
                }
              } catch (e, st) {
                AppLogger.instance.warn(
                  'QueueView',
                  'Save queue as playlist failed',
                  e,
                  st,
                );
                setDialogState(() => errorMessage = e.toString());
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.r16),
                side: const BorderSide(color: AppColors.border),
              ),
              title: Text(
                innerCtx.t('queue.savePlaylistTitle'),
                style: AppTypography.title.copyWith(color: AppColors.text),
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('save_queue_playlist_text_field'),
                      controller: textCtrl,
                      autofocus: true,
                      style: AppTypography.body.copyWith(color: AppColors.text),
                      decoration: InputDecoration(
                        hintText: innerCtx.t('queue.savePlaylistHint'),
                        errorText: errorMessage,
                        isDense: true,
                      ),
                      onChanged: (_) {
                        if (errorMessage != null) {
                          setDialogState(() => errorMessage = null);
                        }
                      },
                      onSubmitted: (_) => validateAndSubmit(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const Key('save_queue_playlist_cancel_button'),
                  onPressed: () => Navigator.of(innerCtx).pop(null),
                  child: Text(innerCtx.t('common.cancel')),
                ),
                ElevatedButton(
                  key: const Key('save_queue_playlist_submit_button'),
                  onPressed: validateAndSubmit,
                  child: Text(innerCtx.t('common.save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.queue.entries;
    final currentIndex = widget.controller.queue.currentIndex;
    final hasUpcoming = currentIndex >= 0 && currentIndex < entries.length - 1;
    final upcomingDuration = _calculateUpcomingDuration(entries, currentIndex);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 24, end: 24, top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('queue.title'),
                    style: AppTypography.display,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        context.t('queue.itemCount', args: {
                          'count': context
                              .localizeDigitsText(entries.length.toString()),
                        }),
                        style: AppTypography.body
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      if (hasUpcoming && upcomingDuration > Duration.zero) ...[
                        Text(
                          ' • ',
                          style: AppTypography.body
                              .copyWith(color: AppColors.textMuted),
                        ),
                        Text(
                          context.t('queue.upcomingDuration', args: {
                            'duration': context
                                .formatDurationLocalized(upcomingDuration),
                          }),
                          style: AppTypography.caption
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GlassPillButton(
                    key: const Key('queue_clear_upcoming_button'),
                    label: context.t('queue.clearUpcoming'),
                    onPressed:
                        hasUpcoming ? () => widget.controller.clearUpcoming() : null,
                  ),
                  GlassPillButton(
                    key: const Key('queue_clear_all_button'),
                    label: context.t('queue.clearAll'),
                    onPressed: entries.isNotEmpty ? _showClearAllDialog : null,
                  ),
                  GlassPillButton(
                    key: const Key('queue_save_playlist_button'),
                    variant: GlassButtonVariant.primary,
                    label: context.t('queue.saveAsPlaylist'),
                    onPressed:
                        entries.isNotEmpty ? _showSavePlaylistDialog : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Shared queue body
          Expanded(
            child: QueueContent(
              controller: widget.controller,
              navigator: widget.navigator,
              settingsStore: widget.settingsStore,
              userCollections: widget.userCollections,
              compact: false,
              autofocus: true,
            ),
          ),
        ],
      ),
    );
  }
}
