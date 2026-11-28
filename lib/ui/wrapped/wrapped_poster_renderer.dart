import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;

import '../../core/result.dart';
import '../../diagnostics/app_logger.dart';
import '../../features/wrapped/recap.dart';
import '../../features/wrapped/wrapped_image_exporter.dart';
import '../../library/cover_cache.dart';
import '../common/error_presenter.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../now_playing/cover_palette.dart';
import '../settings/app_settings.dart';
import '../settings/settings_scope.dart';
import '../settings/settings_store.dart';
import '../stats/stats_formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'wrapped_card_pages.dart';
import 'wrapped_controller.dart';

/// Fixed 1080x1350 offscreen matte poster rendered into a shareable PNG for
/// either a Monthly Wrapped or Weekly listening recap.
class WrappedPosterCard extends StatelessWidget {
  /// Standard shareable export dimensions (4:5 vertical portrait).
  static const Size posterSize = Size(1080, 1350);

  /// Bundled asset font family used so English metrics are identical across hosts
  /// while falling back gracefully for Arabic glyphs.
  static const String bundledFontFamily = 'Roboto';

  /// Recap dataset summarized on the poster.
  final Recap recap;

  /// Muted palette sampled from the recap's top artwork.
  final CoverPalette palette;

  /// Pre-decoded top cover thumbnail, or `null` when unavailable.
  final ui.Image? coverImage;

  /// Creates a [WrappedPosterCard].
  const WrappedPosterCard({
    super.key,
    required this.recap,
    required this.palette,
    this.coverImage,
  });

  TextStyle _posterStyle(TextStyle base) {
    return base.copyWith(
      fontFamily: bundledFontFamily,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgTop = Color.lerp(AppColors.surface, palette.primary, 0.30)!;
    final bgMid = Color.lerp(AppColors.base, palette.secondary, 0.34)!;
    final bgBottom = Color.lerp(AppColors.base, palette.tertiary, 0.44)!;

    final eyebrow = recap.kind == RecapPeriodKind.monthly
        ? context.t('wrapped.card.introMonthlyEyebrow')
        : context.t('wrapped.card.introWeeklyEyebrow');
    final periodLabel = WrappedCardBody.formatPeriodLabel(context, recap);
    final personalityKey = WrappedCardBody.personalityTitleKey(
      recap.personality,
    );
    final includeYear = recap.kind == RecapPeriodKind.monthly;

    return SizedBox(
      width: posterSize.width,
      height: posterSize.height,
      child: DefaultTextStyle(
        style: _posterStyle(AppTypography.body),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 64),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [bgTop, bgMid, bgBottom],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top header + optional cover artwork
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow,
                          style: _posterStyle(
                            AppTypography.bodyStrong.copyWith(
                              fontSize: 22,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          periodLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: textDirectionFor(periodLabel),
                          style: _posterStyle(
                            AppTypography.display.copyWith(
                              fontSize: 52,
                              height: 1.15,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (coverImage != null) ...[
                    const SizedBox(width: 28),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        width: 176,
                        height: 176,
                        child: RawImage(
                          image: coverImage,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Listening hero figure
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('wrapped.card.minutesTitle'),
                    style: _posterStyle(
                      AppTypography.title.copyWith(
                        fontSize: 24,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.localizeDigitsText(
                      context.t(
                        'wrapped.card.minutesValue',
                        args: {'minutes': '${recap.totalMinutes}'},
                      ),
                    ),
                    style: _posterStyle(
                      AppTypography.display.copyWith(
                        fontSize: 64,
                        height: 1.1,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.localizeDigitsText(
                      context.t(
                        'wrapped.card.minutesSubtitle',
                        args: {
                          'formatted': StatsFormatters.formatHoursMinutes(
                            context,
                            recap.totalListenedMs,
                          ),
                          'tracks': '${recap.distinctTracks}',
                        },
                      ),
                    ),
                    style: _posterStyle(
                      AppTypography.body.copyWith(
                        fontSize: 22,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),

              // Two-column summary highlights
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PosterTile(
                          titleStyle: _posterStyle(AppTypography.caption),
                          valueStyle: _posterStyle(AppTypography.title),
                          label: context.t('wrapped.card.topArtistTitle'),
                          value:
                              recap.topArtist?.artist ??
                              context.t('stats.summary.none'),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _PosterTile(
                          titleStyle: _posterStyle(AppTypography.caption),
                          valueStyle: _posterStyle(AppTypography.title),
                          label: context.t('wrapped.card.topAlbumTitle'),
                          value:
                              recap.topAlbum?.album ??
                              context.t('stats.summary.none'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _PosterTile(
                          titleStyle: _posterStyle(AppTypography.caption),
                          valueStyle: _posterStyle(AppTypography.title),
                          label: context.t('wrapped.card.discoveriesTitle'),
                          value: context.localizeDigitsText(
                            context.t(
                              'wrapped.card.discoveriesValue',
                              args: {'count': '${recap.newTracksDiscovered}'},
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _PosterTile(
                          titleStyle: _posterStyle(AppTypography.caption),
                          valueStyle: _posterStyle(AppTypography.title),
                          label: context.t('wrapped.card.busiestDayLabel'),
                          value: recap.busiestDay != null
                              ? StatsFormatters.formatCalendarDay(
                                  context,
                                  recap.busiestDay!.date,
                                  includeYear: includeYear,
                                )
                              : context.t('stats.summary.none'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Top tracks + personality card
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('wrapped.card.topTracksTitle'),
                      style: _posterStyle(
                        AppTypography.title.copyWith(
                          fontSize: 22,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < recap.topTracks.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              context.formatCountLocalized(i + 1),
                              style: _posterStyle(
                                AppTypography.bodyStrong.copyWith(
                                  fontSize: 20,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _trackLine(context, recap.topTracks[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: textDirectionFor(
                                _trackLine(context, recap.topTracks[i]),
                              ),
                              style: _posterStyle(
                                AppTypography.bodyStrong.copyWith(
                                  fontSize: 20,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            StatsFormatters.formatHoursMinutes(
                              context,
                              recap.topTracks[i].totalListenedMs,
                            ),
                            style: _posterStyle(
                              AppTypography.body.copyWith(
                                fontSize: 18,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(color: AppColors.borderSubtle, height: 1),
                    const SizedBox(height: 16),
                    Text(
                      context.t(personalityKey),
                      style: _posterStyle(
                        AppTypography.title.copyWith(
                          fontSize: 24,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('$personalityKey.caption'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _posterStyle(
                        AppTypography.body.copyWith(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Strict footer credit
              Column(
                children: [
                  const Divider(color: AppColors.borderSubtle, height: 1),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      context.t('wrapped.export.footer'),
                      style: _posterStyle(
                        AppTypography.bodyStrong.copyWith(
                          fontSize: 20,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _trackLine(BuildContext context, dynamic track) {
    final title = (track.title as String?)?.trim();
    final artist = (track.artist as String?)?.trim();
    final resolvedTitle = (title != null && title.isNotEmpty)
        ? title
        : context.t('stats.ranked.unknownTrack');
    if (artist != null && artist.isNotEmpty) {
      return '$resolvedTitle · $artist';
    }
    return resolvedTitle;
  }
}

class _PosterTile extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle titleStyle;
  final TextStyle valueStyle;

  const _PosterTile({
    required this.label,
    required this.value,
    required this.titleStyle,
    required this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle.copyWith(
              fontSize: 18,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: textDirectionFor(value),
            style: valueStyle.copyWith(
              fontSize: 26,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders an offscreen 1080x1350 [WrappedPosterCard] through [RenderRepaintBoundary.toImage]
/// and handles safe directory-picked `.png` export.
abstract final class WrappedPosterRenderer {
  /// Renders [recap] as an offscreen 1080x1350 PNG byte buffer.
  static Future<Uint8List> renderRecapPng({
    required Recap recap,
    required CoverPalette palette,
    required AppSettings settings,
    String? coverKey,
    Size size = WrappedPosterCard.posterSize,
  }) async {
    final coverImage = await _loadCoverImage(coverKey);
    final tempStore = SettingsStore(initialSettings: settings);
    final textDir = settings.language == 'ar'
        ? TextDirection.rtl
        : TextDirection.ltr;

    final repaintBoundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: WidgetsBinding.instance.platformDispatcher.views.first,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        physicalConstraints: BoxConstraints.tight(size),
        devicePixelRatio: 1.0,
      ),
      child: RenderPositionedBox(
        alignment: AlignmentDirectional.center,
        textDirection: textDir,
        child: repaintBoundary,
      ),
    );

    final pipelineOwner = PipelineOwner();
    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildOwner = BuildOwner(focusManager: FocusManager());
    final rootWidget = Directionality(
      textDirection: textDir,
      child: MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: 1.0),
        child: Theme(
          data: buildAppTheme(uiFont: WrappedPosterCard.bundledFontFamily),
          child: SettingsScope(
            store: tempStore,
            child: WrappedPosterCard(
              recap: recap,
              palette: palette,
              coverImage: coverImage,
            ),
          ),
        ),
      ),
    );

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: rootWidget,
    ).attachToRenderTree(buildOwner);

    ui.Image? image;
    try {
      buildOwner.buildScope(rootElement);
      buildOwner.finalizeTree();
      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();

      image = await repaintBoundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Failed encoding 1080x1350 PNG byte data.');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image?.dispose();
      coverImage?.dispose();
      pipelineOwner.rootNode = null;
      renderView.dispose();
      buildOwner.finalizeTree();
      tempStore.dispose();
      pipelineOwner.dispose();
    }
  }

  static Future<ui.Image?> _loadCoverImage(String? coverKey) async {
    if (coverKey == null || coverKey.isEmpty) return null;
    ui.Codec? codec;
    try {
      final path = CoverCache.pathFor(coverKey);
      final file = File(path);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 320,
        targetHeight: 320,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e, st) {
      // ignore-silent: Reading optional cover cache falls back cleanly when uninitialized
      AppLogger.instance.debug(
        'WrappedPosterRenderer',
        'Optional poster cover load skipped',
        e,
        st,
      );
      return null;
    } finally {
      codec?.dispose();
    }
  }

  /// Guides the user through picking a target directory (never `saveFile`),
  /// validating the `.png` extension, confirming overwrite if an existing
  /// `.png` matches, writing atomically, and offering an "Open folder" action.
  static Future<Result<String?>> exportRecapPng(
    BuildContext context, {
    required Recap recap,
    required WrappedController controller,
    required SettingsStore settingsStore,
    Future<String?> Function()? directoryPicker,
    Future<bool> Function(BuildContext context, String fileName)?
    confirmOverwrite,
    Future<void> Function(String folderPath)? onOpenFolder,
    Future<Uint8List> Function({
      required Recap recap,
      required CoverPalette palette,
      required AppSettings settings,
      String? coverKey,
    })?
    renderBytes,
    String? targetFileNameOverride,
  }) async {
    try {
      final dialogTitle = context.t('wrapped.shareImage');
      final selectedDir =
          await (directoryPicker ??
              () => FilePicker.getDirectoryPath(dialogTitle: dialogTitle))();
      if (selectedDir == null || selectedDir.trim().isEmpty) {
        return const Ok(null);
      }

      final fileName = targetFileNameOverride ?? recap.suggestedExportFileName;
      final candidatePath = p.join(selectedDir, fileName);
      final validation = WrappedImageExporter.validateTargetPath(candidatePath);

      if (!validation.isAllowed) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(context.t('wrapped.exportRefusedExtension')),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return const Ok(null);
      }

      final targetPath = validation.targetPath!;
      if (validation.requiresOverwriteConfirmation) {
        if (!context.mounted) return const Ok(null);
        final confirmed = await (confirmOverwrite ?? _defaultConfirmOverwrite)(
          context,
          p.basename(targetPath),
        );
        if (!confirmed) return const Ok(null);
      }

      final coverKey = controller.resolveRecapHeroCoverKey(recap);
      final pngBytes = await (renderBytes ?? renderRecapPng)(
        recap: recap,
        palette: controller.coverPalette,
        settings: settingsStore.settings,
        coverKey: coverKey,
      );

      await WrappedImageExporter.writePngAtomically(targetPath, pngBytes);

      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                'wrapped.exportSuccess',
                args: {'file': p.basename(targetPath)},
              ),
            ),
            duration: const Duration(seconds: 5),
            action: onOpenFolder != null
                ? SnackBarAction(
                    label: context.t('wrapped.openFolder'),
                    onPressed: () => unawaited(onOpenFolder(selectedDir)),
                  )
                : null,
          ),
        );
      }
      return Ok(targetPath);
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'WrappedExport',
        'Failed exporting Wrapped PNG',
        error,
        stackTrace,
      );
      final appError = AppError.fromException(
        error,
        stackTrace,
        'wrapped.exportFailed',
      );
      if (context.mounted) {
        ErrorPresenter.show(context, appError);
      }
      return Err(appError);
    }
  }

  static Future<bool> _defaultConfirmOverwrite(
    BuildContext context,
    String fileName,
  ) async {
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(dialogCtx.t('wrapped.overwriteTitle')),
          content: Text(
            dialogCtx.t('wrapped.overwriteMessage', args: {'name': fileName}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(dialogCtx.t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(dialogCtx.t('wrapped.overwriteConfirm')),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }
}
