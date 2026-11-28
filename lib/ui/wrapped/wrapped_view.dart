import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../features/wrapped/recap.dart';
import '../../library/library_repository.dart';
import '../common/error_presenter.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../library/library_data_cache.dart';
import '../settings/app_shortcuts.dart';
import '../settings/settings_store.dart';
import '../settings/widgets/settings_components.dart';
import '../shell/app_navigator.dart';
import '../stats/stats_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'wrapped_card_pages.dart';
import 'wrapped_controller.dart';
import 'wrapped_poster_renderer.dart';

/// Callback signature for invoking recap PNG image export from [WrappedView].
typedef WrappedShareHandler = Future<void> Function(
  BuildContext context,
  Recap recap,
  WrappedController controller,
);

/// Calm paged card flow for Monthly Wrapped and Weekly listening activity recaps.
class WrappedView extends StatefulWidget {
  /// Library storage repository (all queries are read-only).
  final LibraryRepository repository;

  /// Settings store governing language, numerals, and motion.
  final SettingsStore settingsStore;

  /// Navigation coordinator used for back navigation.
  final AppNavigator navigator;

  /// Shared library data cache used for cover art resolution and SWR.
  final LibraryDataCache dataCache;

  /// Initial recap period mode (`monthly` vs `weekly`).
  final RecapPeriodKind initialKind;

  /// Optional initial calendar year for monthly Wrapped.
  final int? initialYear;

  /// Optional initial calendar month for monthly Wrapped.
  final int? initialMonth;

  /// Optional shared [StatsController] reused when opened from Stats.
  final StatsController? statsController;

  /// Optional injected [WrappedController] for deterministic testing.
  final WrappedController? wrappedController;

  /// Optional clock override passed to [WrappedController].
  final DateTime Function()? clock;

  /// Optional directory picker override passed to image export in S3/tests.
  final Future<String?> Function()? directoryPicker;

  /// Optional folder opener callback invoked by the export "Open folder" action.
  final Future<void> Function(String path)? onOpenFolder;

  /// Optional custom export handler (used prior to or in tests of S3).
  final WrappedShareHandler? onShareRecap;

  /// Creates a [WrappedView].
  const WrappedView({
    super.key,
    required this.repository,
    required this.settingsStore,
    required this.navigator,
    required this.dataCache,
    this.initialKind = RecapPeriodKind.monthly,
    this.initialYear,
    this.initialMonth,
    this.statsController,
    this.wrappedController,
    this.clock,
    this.directoryPicker,
    this.onOpenFolder,
    this.onShareRecap,
  });

  @override
  State<WrappedView> createState() => _WrappedViewState();
}

class _WrappedViewState extends State<WrappedView> {
  late final WrappedController _controller;
  late final bool _ownsController;
  late final PageController _pageController;
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'wrapped_pager');
  AppError? _lastPresentedError;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    if (widget.wrappedController != null) {
      _controller = widget.wrappedController!;
      _ownsController = false;
    } else {
      _controller = WrappedController(
        repository: widget.repository,
        settingsStore: widget.settingsStore,
        dataCache: widget.dataCache,
        statsController: widget.statsController,
        initialKind: widget.initialKind,
        initialYear: widget.initialYear,
        initialMonth: widget.initialMonth,
        clock: widget.clock,
      );
      _ownsController = true;
      unawaited(_controller.refresh());
    }
    _pageController = PageController(initialPage: _controller.currentPage);
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _keyboardFocusNode.canRequestFocus) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_pageController.hasClients) {
      final target = _controller.currentPage;
      final current = _pageController.page?.round();
      if (current != target) {
        final reduceMotion = widget.settingsStore.settings.reduceMotion;
        if (reduceMotion) {
          _pageController.jumpToPage(target);
        } else {
          unawaited(
            _pageController.animateToPage(
              target,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            ),
          );
        }
      }
    }

    final err = _controller.error;
    if (err != null && !identical(err, _lastPresentedError)) {
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
    _pageController.dispose();
    _keyboardFocusNode.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _handleShare(Recap recap) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final handler = widget.onShareRecap;
      if (handler != null) {
        await handler(context, recap, _controller);
      } else {
        await WrappedPosterRenderer.exportRecapPng(
          context,
          recap: recap,
          controller: _controller,
          settingsStore: widget.settingsStore,
          directoryPicker: widget.directoryPicker,
          onOpenFolder: widget.onOpenFolder,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _goPrevious(bool isRtl) {
    _keyboardFocusNode.requestFocus();
    _controller.previousPage();
  }

  void _goNext(bool isRtl) {
    _keyboardFocusNode.requestFocus();
    _controller.nextPage();
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
        final recap = _controller.recap;
        final error = _controller.error;
        final isRtl = Directionality.of(context) == TextDirection.rtl;

        return Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent || recap == null || !recap.isEligible) {
              return KeyEventResult.ignored;
            }
            if (isArrowRightKey(event)) {
              if (isRtl) {
                _controller.previousPage();
              } else {
                _controller.nextPage();
              }
              return KeyEventResult.handled;
            }
            if (isArrowLeftKey(event)) {
              if (isRtl) {
                _controller.nextPage();
              } else {
                _controller.previousPage();
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPad = constraints.maxWidth < 720 ? 20.0 : 32.0;
              return SingleChildScrollView(
                key: const Key('wrapped_scroll_view'),
                padding: EdgeInsetsDirectional.only(
                  start: horizontalPad,
                  end: horizontalPad,
                  top: AppSpacing.s24,
                  bottom: 120.0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context, recap),
                        const SizedBox(height: AppSpacing.s24),
                        if (error != null && recap == null)
                          _WrappedErrorState(
                            message: ErrorPresenter.messageFor(context, error),
                            onRetry: () => unawaited(_controller.refresh()),
                          )
                        else if (_controller.isInitialLoading)
                          const _WrappedSkeleton()
                        else if (recap != null && !recap.isEligible)
                          _WrappedNotEnoughState(
                            recap: recap,
                            hasAnyMonths: _controller.availableMonths.isNotEmpty,
                            onSwitchToWeekly:
                                recap.kind == RecapPeriodKind.monthly
                                    ? () => unawaited(
                                        _controller.setKind(
                                          RecapPeriodKind.weekly,
                                        ),
                                      )
                                    : null,
                          )
                        else if (recap != null)
                          _buildPagerSection(context, recap, isRtl),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Recap? recap) {
    final months = _controller.availableMonths;
    final showShare = recap != null && recap.isEligible;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.s16,
      runSpacing: AppSpacing.s12,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.navigator.canGoBack) ...[
              GlassIconButton(
                key: const Key('wrapped_back_button'),
                icon: Icons.arrow_back_rounded,
                matchTextDirection: true,
                tooltip: context.t('common.back'),
                semanticLabel: context.t('common.back'),
                onPressed: widget.navigator.goBack,
              ),
              const SizedBox(width: AppSpacing.s12),
            ],
            Text(
              _controller.kind == RecapPeriodKind.weekly
                  ? context.t('wrapped.weeklyTitle')
                  : context.t('wrapped.title'),
              key: const Key('wrapped_header_title'),
              style: AppTypography.display.copyWith(color: AppColors.text),
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.s12,
          runSpacing: AppSpacing.s8,
          children: [
            SettingsSegmentedControl<RecapPeriodKind>(
              key: const Key('wrapped_kind_selector'),
              value: _controller.kind,
              onChanged: (next) => unawaited(_controller.setKind(next)),
              options: [
                SettingsSegmentedOption(
                  value: RecapPeriodKind.monthly,
                  label: context.t('wrapped.mode.monthly'),
                ),
                SettingsSegmentedOption(
                  value: RecapPeriodKind.weekly,
                  label: context.t('wrapped.mode.weekly'),
                ),
              ],
            ),
            if (_controller.kind == RecapPeriodKind.monthly &&
                months.isNotEmpty)
              _MonthDropdown(
                months: months,
                selectedYear: _controller.selectedYear,
                selectedMonth: _controller.selectedMonth,
                onChanged: (option) =>
                    unawaited(_controller.selectMonth(option.year, option.month)),
              ),
            if (showShare)
              GlassPillButton(
                key: const Key('wrapped_header_share_button'),
                size: GlassButtonSize.small,
                leadingIcon: Icons.ios_share_outlined,
                label: _isExporting
                    ? context.t('wrapped.exporting')
                    : context.t('wrapped.shareImage'),
                onPressed: _isExporting ? null : () => _handleShare(recap),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPagerSection(BuildContext context, Recap recap, bool isRtl) {
    final page = _controller.currentPage;
    const total = WrappedController.pageCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 390,
          child: PageView.builder(
            key: const Key('wrapped_page_view'),
            controller: _pageController,
            itemCount: total,
            onPageChanged: _controller.setPage,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: WrappedCardBody(
                  pageIndex: index,
                  recap: recap,
                  palette: _controller.coverPalette,
                  controller: _controller,
                  onShareImage: () => _handleShare(recap),
                  isExporting: _isExporting,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GlassIconButton(
              key: const Key('wrapped_prev_button'),
              icon: Icons.chevron_left_rounded,
              matchTextDirection: true,
              tooltip: context.t('wrapped.prevCardTooltip'),
              semanticLabel: context.t('wrapped.prevCardTooltip'),
              onPressed: page > 0 ? () => _goPrevious(isRtl) : null,
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.s8,
              children: [
                for (var i = 0; i < total; i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _controller.setPage(i),
                    child: Container(
                      width: i == page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == page
                            ? AppColors.accent
                            : AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  context.localizeDigitsText(
                    context.t(
                      'wrapped.pageIndicator',
                      args: {'current': '${page + 1}', 'total': '$total'},
                    ),
                  ),
                  key: const Key('wrapped_page_indicator'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            GlassIconButton(
              key: const Key('wrapped_next_button'),
              icon: Icons.chevron_right_rounded,
              matchTextDirection: true,
              tooltip: context.t('wrapped.nextCardTooltip'),
              semanticLabel: context.t('wrapped.nextCardTooltip'),
              onPressed: page < total - 1 ? () => _goNext(isRtl) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _MonthDropdown extends StatelessWidget {
  final List<RecapMonthOption> months;
  final int? selectedYear;
  final int? selectedMonth;
  final ValueChanged<RecapMonthOption> onChanged;

  const _MonthDropdown({
    required this.months,
    required this.selectedYear,
    required this.selectedMonth,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = months.firstWhere(
      (m) => m.year == selectedYear && m.month == selectedMonth,
      orElse: () => months.first,
    );

    return Container(
      key: const Key('wrapped_month_selector'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: AppSpacing.br10,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RecapMonthOption>(
          value: current,
          dropdownColor: AppColors.surface,
          style: AppTypography.caption.copyWith(color: AppColors.text),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
          items: [
            for (final opt in months)
              DropdownMenuItem<RecapMonthOption>(
                value: opt,
                child: Text(
                  context.localizeDigitsText(
                    context.t(
                      'wrapped.monthLabel',
                      args: {
                        'month': context.t('wrapped.month.full.${opt.month}'),
                        'year': '${opt.year}',
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WrappedNotEnoughState extends StatelessWidget {
  final Recap recap;
  final bool hasAnyMonths;
  final VoidCallback? onSwitchToWeekly;

  const _WrappedNotEnoughState({
    required this.recap,
    required this.hasAnyMonths,
    this.onSwitchToWeekly,
  });

  @override
  Widget build(BuildContext context) {
    final String body;
    if (recap.kind == RecapPeriodKind.weekly) {
      body = context.t('wrapped.notEnough.weeklyBody');
    } else if (!hasAnyMonths && recap.playsCounted == 0) {
      body = context.t('wrapped.notEnough.noMonths');
    } else {
      body = context.localizeDigitsText(
        context.t(
          'wrapped.notEnough.monthlyBody',
          args: {
            'plays': '${recap.playsCounted}',
            'required': '${recap.requiredCountedPlays}',
          },
        ),
      );
    }

    return Container(
      key: const Key('wrapped_not_enough_state'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s24,
        vertical: AppSpacing.s32,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.78),
        borderRadius: AppSpacing.br22,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(
            Icons.hourglass_empty_rounded,
            size: 36,
            color: AppColors.accent.withValues(alpha: 0.82),
          ),
          const SizedBox(height: AppSpacing.s16),
          Text(
            context.t('wrapped.notEnough.title'),
            textAlign: TextAlign.center,
            style: AppTypography.title.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: AppSpacing.s8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (onSwitchToWeekly != null) ...[
            const SizedBox(height: AppSpacing.s24),
            GlassPillButton(
              key: const Key('wrapped_try_weekly_button'),
              label: context.t('wrapped.mode.weekly'),
              onPressed: onSwitchToWeekly,
            ),
          ],
        ],
      ),
    );
  }
}

class _WrappedErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _WrappedErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('wrapped_error_state'),
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
            key: const Key('wrapped_retry_button'),
            label: context.t('error.actionRetry'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _WrappedSkeleton extends StatelessWidget {
  const _WrappedSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('wrapped_skeleton'),
      height: 360,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.45),
        borderRadius: AppSpacing.br26,
        border: Border.all(color: AppColors.borderSubtle),
      ),
    );
  }
}
