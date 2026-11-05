import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../glass/glass_blur_budget.dart';
import '../glass/glass_button.dart';
import '../glass/glass_quality.dart';
import '../glass/glass_scope.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../l10n/locale_controller.dart';
import '../settings/settings_store.dart';
import '../settings/app_shortcuts.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'performance_metrics.dart';

/// Developer gallery screen showcasing design tokens, glass surfaces, controls,
/// and live frame performance measurements across all build modes.
class DesignGalleryScreen extends StatefulWidget {
  /// The active glass controller.
  final GlassController glassController;

  /// The active locale controller.
  final LocaleController localeController;

  /// The active persistent settings store.
  final SettingsStore settingsStore;

  /// Creates a [DesignGalleryScreen].
  const DesignGalleryScreen({
    super.key,
    required this.glassController,
    required this.localeController,
    required this.settingsStore,
  });

  @override
  State<DesignGalleryScreen> createState() => _DesignGalleryScreenState();
}

class _DesignGalleryScreenState extends State<DesignGalleryScreen>
    with SingleTickerProviderStateMixin {
  final List<FrameTiming> _timingsWindow = [];
  static const int _maxWindowSize = 300;

  bool _animateTest = false;
  late final AnimationController _animController;
  late final Animation<double> _blobAnimation;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _blobAnimation = Tween<double>(begin: -100.0, end: 100.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutSine),
    );

    _syncAnimationState();
  }

  @override
  void didUpdateWidget(DesignGalleryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimationState();
  }

  void _syncAnimationState() {
    if (widget.glassController.reduceMotion) {
      if (_animateTest) {
        _animateTest = false;
      }
      _animController.stop();
    } else if (_animateTest) {
      _animController.repeat(reverse: true);
    } else {
      _animController.stop();
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!mounted) return;
    setState(() {
      _timingsWindow.addAll(timings);
      if (_timingsWindow.length > _maxWindowSize) {
        _timingsWindow.removeRange(
          0,
          _timingsWindow.length - _maxWindowSize,
        );
      }
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _animController.dispose();
    super.dispose();
  }

  String get _buildMode {
    if (kReleaseMode) return 'Release';
    if (kProfileMode) return 'Profile';
    return 'Debug';
  }

  void _copyResults(PerformanceMetrics metrics) {
    final report = metrics.toExportString(
      qualityTier: widget.glassController.quality.name.toUpperCase(),
      buildMode: _buildMode,
    );
    Clipboard.setData(ClipboardData(text: report));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Performance report copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = PerformanceMetrics.compute(_timingsWindow);
    final isMotionReduced = widget.glassController.reduceMotion;
    final currentQuality = widget.glassController.quality;
    final currentLang = widget.localeController.language;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        shortcutById(AppShortcutId.back).activator: () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.base,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            title: const Text('Design Gallery — Aestheticy / by mido'),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close (Esc)',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          body: Stack(
            children: [
              // ── Background Blobs ──────────────────────────────────────────
              Positioned(
                top: 40,
                left: 60,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x38D3C9EA), Color(0x00D3C9EA)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 280,
                right: 80,
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x30A9C4AE), Color(0x00A9C4AE)],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 80,
                left: 200,
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x28D9908F), Color(0x00D9908F)],
                    ),
                  ),
                ),
              ),

              // Animated Test Blob
              if (_animateTest && !isMotionReduced)
                AnimatedBuilder(
                  animation: _blobAnimation,
                  builder: (context, _) => Positioned(
                    top: 450 + _blobAnimation.value,
                    left: 250 + _blobAnimation.value * 1.5,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x55D3C9EA), Color(0x00D3C9EA)],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Scrollable Content ─────────────────────────────────────────
              SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 1. Color and Typography Tokens ─────────────────────────
                    _buildSectionHeader('1. DESIGN TOKENS'),
                    const SizedBox(height: AppSpacing.s12),
                    _buildColorTokensGrid(),
                    const SizedBox(height: AppSpacing.s16),
                    _buildTypographyTokensCard(),

                    const SizedBox(height: AppSpacing.s24),

                    // ── 2. Glass Surfaces & Tier Selector ──────────────────────
                    _buildSectionHeader('2. GLASS SURFACE SAMPLES & QUALITY'),
                    const SizedBox(height: AppSpacing.s12),
                    _buildQualitySelector(currentQuality),
                    const SizedBox(height: AppSpacing.s16),
                    _buildGlassSurfaceSamples(),

                    const SizedBox(height: AppSpacing.s24),

                    // ── 3. Glass Control Buttons ───────────────────────────────
                    _buildSectionHeader('3. GLASS CONTROL BUTTONS'),
                    const SizedBox(height: AppSpacing.s12),
                    _buildButtonVariantsSection(),

                    const SizedBox(height: AppSpacing.s24),

                    // ── 4 & 5. Localization & Motion Controls ──────────────────
                    _buildSectionHeader('4 & 5. LOCALIZATION & MOTION CONTROLS'),
                    const SizedBox(height: AppSpacing.s12),
                    _buildLocalizationAndMotionControls(
                      currentLang,
                      isMotionReduced,
                    ),

                    const SizedBox(height: AppSpacing.s24),

                    // ── 6 & 7. Performance Panel & Animate Test ────────────────
                    _buildSectionHeader('6 & 7. PERFORMANCE PANEL & WORST-CASE TEST'),
                    const SizedBox(height: AppSpacing.s12),
                    _buildPerformancePanel(metrics, currentQuality),
                    const SizedBox(height: AppSpacing.s32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTypography.micro.copyWith(
        color: AppColors.accent,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildColorTokensGrid() {
    final swatches = <(String, Color)>[
      ('base', AppColors.base),
      ('surface', AppColors.surface),
      ('text', AppColors.text),
      ('textSecondary', AppColors.textSecondary),
      ('textMuted', AppColors.textMuted),
      ('accent', AppColors.accent),
      ('accentSoft', AppColors.accentSoft),
      ('accentFill', AppColors.accentFill),
      ('border', AppColors.border),
      ('borderSubtle', AppColors.borderSubtle),
      ('fillGlass', AppColors.fillGlass),
      ('fillControl', AppColors.fillControl),
      ('danger', AppColors.danger),
      ('success', AppColors.success),
    ];

    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: swatches.map((item) {
        return Container(
          width: 140,
          padding: const EdgeInsets.all(AppSpacing.s8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.r10),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: item.$2,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  item.$1,
                  style: AppTypography.caption.copyWith(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTypographyTokensCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Display 32 / w600 — Aestheticy', style: AppTypography.display),
          SizedBox(height: AppSpacing.s8),
          Text('Title 20 / w600 — Section Headline', style: AppTypography.title),
          SizedBox(height: AppSpacing.s8),
          Text('Body Strong 14 / w600 — Emphasized Text',
              style: AppTypography.bodyStrong),
          SizedBox(height: AppSpacing.s8),
          Text('Body 14 / w400 — Standard interface paragraph text',
              style: AppTypography.body),
          SizedBox(height: AppSpacing.s8),
          Text('Caption 12.5 / w400 — Secondary descriptive metadata',
              style: AppTypography.caption),
          SizedBox(height: AppSpacing.s8),
          Text('MICRO 11 / W500 — UPPERCASE SECTION BADGE',
              style: AppTypography.micro),
        ],
      ),
    );
  }

  Widget _buildQualitySelector(GlassQuality currentQuality) {
    return Row(
      children: [
        const Text('Quality Tier: ', style: AppTypography.bodyStrong),
        const SizedBox(width: AppSpacing.s8),
        for (final quality in GlassQuality.values) ...[
          GlassPillButton(
            label: quality.name.toUpperCase(),
            variant: currentQuality == quality
                ? GlassButtonVariant.selected
                : GlassButtonVariant.normal,
            size: GlassButtonSize.small,
            onPressed: () {
              widget.glassController.quality = quality;
              widget.settingsStore.update((s) => s.copyWith(glassQuality: quality));
            },
          ),
          const SizedBox(width: AppSpacing.s8),
        ],
      ],
    );
  }

  Widget _buildGlassSurfaceSamples() {
    return const Row(
      children: [
        Expanded(
          child: GlassSurface(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Full Glass (Budgeted)', style: AppTypography.bodyStrong),
                SizedBox(height: AppSpacing.s4),
                Text(
                  'Real 30px blur backdrop with subtle inner highlight.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: AppSpacing.s12),
        Expanded(
          child: GlassSurface(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Light Glass (Default)', style: AppTypography.bodyStrong),
                SizedBox(height: AppSpacing.s4),
                Text(
                  'Simulated gradient with soft shadow. Zero GPU blur cost.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: AppSpacing.s12),
        Expanded(
          child: GlassSurface(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Off (Solid)', style: AppTypography.bodyStrong),
                SizedBox(height: AppSpacing.s4),
                Text(
                  'Flat solid surface without blur or shadows.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButtonVariantsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s12,
          runSpacing: AppSpacing.s12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Normal (Small, Medium, Large)
            GlassIconButton(
              icon: Icons.skip_previous,
              tooltip: 'Previous',
              semanticLabel: 'Previous',
              size: GlassButtonSize.small,
              onPressed: () {},
            ),
            GlassIconButton(
              icon: Icons.skip_previous,
              tooltip: 'Previous',
              semanticLabel: 'Previous',
              size: GlassButtonSize.medium,
              onPressed: () {},
            ),
            // Primary (Large - strictly Play/Pause)
            GlassIconButton(
              icon: Icons.play_arrow,
              tooltip: 'Play',
              semanticLabel: 'Play',
              variant: GlassButtonVariant.primary,
              size: GlassButtonSize.large,
              onPressed: () {},
            ),
            // Selected (Medium)
            GlassIconButton(
              icon: Icons.shuffle,
              tooltip: 'Shuffle',
              semanticLabel: 'Shuffle',
              variant: GlassButtonVariant.selected,
              size: GlassButtonSize.medium,
              onPressed: () {},
            ),
            // Disabled (Medium)
            const GlassIconButton(
              icon: Icons.skip_next,
              tooltip: 'Next (Disabled)',
              semanticLabel: 'Next Disabled',
              size: GlassButtonSize.medium,
              onPressed: null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        Wrap(
          spacing: AppSpacing.s12,
          runSpacing: AppSpacing.s12,
          children: [
            GlassPillButton(
              label: 'Small Pill',
              size: GlassButtonSize.small,
              onPressed: () {},
            ),
            GlassPillButton(
              label: 'Medium Pill',
              leadingIcon: Icons.folder,
              size: GlassButtonSize.medium,
              onPressed: () {},
            ),
            GlassPillButton(
              label: 'Selected Pill',
              leadingIcon: Icons.check,
              variant: GlassButtonVariant.selected,
              size: GlassButtonSize.medium,
              onPressed: () {},
            ),
            const GlassPillButton(
              label: 'Disabled Pill',
              leadingIcon: Icons.block,
              size: GlassButtonSize.medium,
              onPressed: null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLocalizationAndMotionControls(
    String currentLang,
    bool isMotionReduced,
  ) {
    const sampleArabic = '123 فيروز — Fairouz (أغاني)';
    final sampleDir = textDirectionFor(sampleArabic);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Interface Language: ', style: AppTypography.bodyStrong),
              GlassPillButton(
                label: 'English',
                variant: currentLang == 'en'
                    ? GlassButtonVariant.selected
                    : GlassButtonVariant.normal,
                size: GlassButtonSize.small,
                onPressed: () {
                  widget.localeController.setLanguage('en');
                  widget.settingsStore.update((s) => s.copyWith(language: 'en'));
                },
              ),
              GlassPillButton(
                label: 'العربية',
                variant: currentLang == 'ar'
                    ? GlassButtonVariant.selected
                    : GlassButtonVariant.normal,
                size: GlassButtonSize.small,
                onPressed: () {
                  widget.localeController.setLanguage('ar');
                  widget.settingsStore.update((s) => s.copyWith(language: 'ar'));
                },
              ),
              const SizedBox(width: AppSpacing.s16),
              const Text('Reduce Motion: ', style: AppTypography.bodyStrong),
              Switch(
                value: isMotionReduced,
                onChanged: (val) {
                  widget.glassController.reduceMotion = val;
                  widget.settingsStore.update((s) => s.copyWith(reduceMotion: val));
                  _syncAnimationState();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          const Text('Bidi Sample with textDirectionFor():',
              style: AppTypography.caption),
          const SizedBox(height: AppSpacing.s4),
          Directionality(
            textDirection: sampleDir,
            child: Text(
              sampleArabic,
              style: AppTypography.body.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformancePanel(
    PerformanceMetrics metrics,
    GlassQuality currentQuality,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Mode: $_buildMode', style: AppTypography.bodyStrong),
              Text(
                'Tier: ${currentQuality.name.toUpperCase()}',
                style: AppTypography.bodyStrong,
              ),
              Text(
                'Blur surfaces in use: ${GlassBlurBudget.instance.activeCount} / $kMaxBlurredSurfaces',
                style: AppTypography.caption,
              ),
              Text(
                'Frames: ${metrics.totalFrames} / $_maxWindowSize',
                style: AppTypography.caption,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Animate test: ', style: AppTypography.caption),
                  Switch(
                    value: _animateTest,
                    onChanged: widget.glassController.reduceMotion
                        ? null
                        : (val) {
                            setState(() => _animateTest = val);
                            _syncAnimationState();
                          },
                  ),
                ],
              ),
              GlassPillButton(
                label: 'Reset',
                size: GlassButtonSize.small,
                onPressed: () => setState(() => _timingsWindow.clear()),
              ),
              GlassPillButton(
                label: 'Copy results',
                size: GlassButtonSize.small,
                leadingIcon: Icons.copy,
                onPressed: () => _copyResults(metrics),
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.borderSubtle),
          Wrap(
            spacing: AppSpacing.s24,
            runSpacing: AppSpacing.s12,
            children: [
              _buildMetricItem(
                label: 'Avg Build',
                value: '${metrics.avgBuildMs.toStringAsFixed(2)} ms',
              ),
              _buildMetricItem(
                label: 'P95 Build',
                value: '${metrics.p95BuildMs.toStringAsFixed(2)} ms',
              ),
              _buildMetricItem(
                label: 'Avg Raster',
                value: '${metrics.avgRasterMs.toStringAsFixed(2)} ms',
              ),
              _buildMetricItem(
                label: 'P95 Raster',
                value: '${metrics.p95RasterMs.toStringAsFixed(2)} ms',
              ),
              _buildMetricItem(
                label: 'Slow Frames (>16.7ms)',
                value: '${metrics.slowFramePercent.toStringAsFixed(1)}%',
                isWarning: metrics.slowFramePercent > 5.0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    bool isWarning = false,
  }) {
    return Column(
      children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: AppSpacing.s4),
        Text(
          value,
          style: AppTypography.title.copyWith(
            fontSize: 16,
            color: isWarning ? AppColors.danger : AppColors.text,
          ),
        ),
      ],
    );
  }
}
