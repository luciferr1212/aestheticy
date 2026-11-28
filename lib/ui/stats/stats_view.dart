import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/playback_controller.dart';
import '../../../core/result.dart';
import '../../../library/library_repository.dart';
import '../common/error_presenter.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../library/library_data_cache.dart';
import '../settings/settings_store.dart';
import '../settings/widgets/settings_components.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'stats_controller.dart';
import 'stats_date_range.dart';
import 'widgets/stats_activity_heatmap.dart';
import 'widgets/stats_bar_chart.dart';
import 'widgets/stats_ranked_lists.dart';
import 'widgets/stats_summary_grid.dart';

/// Calm listening statistics screen presenting a segmented range selector,
/// 4 summary KPI tiles, daily/monthly bar chart, 7x24 weekly listening heat
/// strip, and top 10 tracks/artists/albums.
class StatsView extends StatefulWidget {
  /// Library storage repository (all queries are read-only).
  final LibraryRepository repository;

  /// Playback controller used when tapping a top track.
  final PlaybackController playbackController;

  /// Settings store governing language, numerals, and motion preferences.
  final SettingsStore settingsStore;

  /// Navigator used when opening a top album or artist detail view.
  final AppNavigator navigator;

  /// Shared library data cache used for artwork resolution and revalidation.
  final LibraryDataCache dataCache;

  /// Optional injected [StatsController] (for deterministic tests).
  final StatsController? statsController;

  /// Optional clock override passed to [StatsController].
  final DateTime Function()? clock;

  /// Creates a [StatsView].
  const StatsView({
    super.key,
    required this.repository,
    required this.playbackController,
    required this.settingsStore,
    required this.navigator,
    required this.dataCache,
    this.statsController,
    this.clock,
  });

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  late final StatsController _controller;
  late final bool _ownsController;
  AppError? _lastPresentedError;

  @override
  void initState() {
    super.initState();
    if (widget.statsController != null) {
      _controller = widget.statsController!;
      _ownsController = false;
    } else {
      _controller = StatsController(
        repository: widget.repository,
        settingsStore: widget.settingsStore,
        dataCache: widget.dataCache,
        clock: widget.clock,
      );
      _ownsController = true;
      unawaited(_controller.refresh());
    }
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final err = _controller.error;
    if (err != null && !identical(err, _lastPresentedError) && mounted) {
      _lastPresentedError = err;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _controller.error != err) return;
        ErrorPresenter.show(
          context,
          err,
          onRetry: () => unawaited(_controller.refresh()),
        );
      });
    } else if (err == null) {
      _lastPresentedError = null;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _controller,
        widget.settingsStore,
        widget.dataCache,
      ]),
      builder: (context, _) {
        final reduceMotion = widget.settingsStore.settings.reduceMotion;
        final snapshot = _controller.snapshot;
        final error = _controller.error;

        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPad = constraints.maxWidth < 720 ? 20.0 : 32.0;
            return SingleChildScrollView(
              key: const Key('stats_scroll_view'),
              padding: EdgeInsetsDirectional.only(
                start: horizontalPad,
                end: horizontalPad,
                top: AppSpacing.s24,
                bottom: 128.0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: AppSpacing.s24),
                      if (error != null && snapshot == null)
                        _StatsErrorCard(
                          message: ErrorPresenter.messageFor(context, error),
                          onRetry: () => unawaited(_controller.refresh()),
                        )
                      else if (_controller.isInitialLoading)
                        const _StatsSkeleton()
                      else if (snapshot != null && !snapshot.hasHistory)
                        const _StatsEmptyState()
                      else if (snapshot != null) ...[
                        StatsSummaryGrid(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s24),
                        StatsBarChart(
                          snapshot: snapshot,
                          reduceMotion: reduceMotion,
                        ),
                        const SizedBox(height: AppSpacing.s24),
                        StatsActivityHeatmap(
                          snapshot: snapshot,
                          reduceMotion: reduceMotion,
                        ),
                        const SizedBox(height: AppSpacing.s24),
                        StatsRankedLists(
                          snapshot: snapshot,
                          dataCache: widget.dataCache,
                          playbackController: widget.playbackController,
                          navigator: widget.navigator,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.s16,
      runSpacing: AppSpacing.s12,
      children: [
        Text(
          context.t('stats.title'),
          key: const Key('stats_header_title'),
          style: AppTypography.display.copyWith(color: AppColors.text),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SettingsSegmentedControl<StatsRange>(
            key: const Key('stats_range_selector'),
            value: _controller.range,
            onChanged: (next) => unawaited(_controller.setRange(next)),
            options: [
              SettingsSegmentedOption(
                value: StatsRange.week,
                label: context.t('stats.range.week'),
              ),
              SettingsSegmentedOption(
                value: StatsRange.month,
                label: context.t('stats.range.month'),
              ),
              SettingsSegmentedOption(
                value: StatsRange.year,
                label: context.t('stats.range.year'),
              ),
              SettingsSegmentedOption(
                value: StatsRange.allTime,
                label: context.t('stats.range.allTime'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsEmptyState extends StatelessWidget {
  const _StatsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('stats_empty_state'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s24,
        vertical: AppSpacing.s32,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: AppSpacing.br22,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(
            Icons.insights_outlined,
            size: 36,
            color: AppColors.accent.withValues(alpha: 0.8),
          ),
          const SizedBox(height: AppSpacing.s16),
          Text(
            context.t('stats.empty.title'),
            textAlign: TextAlign.center,
            style: AppTypography.title.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: AppSpacing.s8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              context.t('stats.empty.subtitle'),
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _StatsErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('stats_error_state'),
      padding: const EdgeInsets.all(AppSpacing.s24),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.78),
        borderRadius: AppSpacing.br22,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: AppSpacing.s16),
          GlassPillButton(
            key: const Key('stats_retry_button'),
            label: context.t('error.actionRetry'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('stats_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 108,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.45),
            borderRadius: AppSpacing.br16,
            border: Border.all(color: AppColors.borderSubtle),
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.45),
            borderRadius: AppSpacing.br22,
            border: Border.all(color: AppColors.borderSubtle),
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.45),
            borderRadius: AppSpacing.br22,
            border: Border.all(color: AppColors.borderSubtle),
          ),
        ),
      ],
    );
  }
}
