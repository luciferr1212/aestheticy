import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../../audio/audio_models.dart';
import '../glass/glass_button.dart';
import '../glass/glass_surface.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/app_shortcuts.dart';
import '../settings/audio_settings_applier.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'eq_controller.dart';
import 'eq_scope.dart';
import 'eq_store.dart';
import 'signal_path_model.dart';

/// Combined Audio Panels view hosting Equalizer and Signal Path panels side-by-side
/// (or stacked vertically on narrow viewports).
class AudioPanelsView extends StatefulWidget {
  /// The audio engine.
  final AudioEngine engine;

  /// The equalizer controller.
  final EqController? eqController;

  /// The audio settings applier.
  final AudioSettingsApplier? audioSettingsApplier;

  /// The settings store.
  final SettingsStore settingsStore;

  /// The application navigator.
  final AppNavigator navigator;

  /// Creates an [AudioPanelsView].
  const AudioPanelsView({
    super.key,
    required this.engine,
    this.eqController,
    this.audioSettingsApplier,
    required this.settingsStore,
    required this.navigator,
  });

  @override
  State<AudioPanelsView> createState() => _AudioPanelsViewState();
}

class _AudioPanelsViewState extends State<AudioPanelsView> {
  final FocusNode _focusNode = FocusNode();
  final Set<int> _expandedStages = {};
  bool _isSavingPreset = false;
  final TextEditingController _presetNameController = TextEditingController();
  String? _presetErrorKey;
  String? _actionFeedback;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _focusNode.dispose();
    _presetNameController.dispose();
    super.dispose();
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    _feedbackTimer?.cancel();
    setState(() => _actionFeedback = message);
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _actionFeedback = null);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (matchesShortcut(event, AppShortcutId.back)) {
      widget.navigator.goBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final eq = widget.eqController ?? EqScope.maybeOf(context);

    Widget buildContent(BuildContext context) {
      return Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top page header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Row(
                  children: [
                    GlassIconButton(
                      key: const Key('audio_panels_back_button'),
                      icon: Icons.arrow_back,
                      tooltip: context.t('shortcuts.back'),
                      semanticLabel: context.t('shortcuts.back'),
                      onPressed: () => widget.navigator.goBack(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        context.t('audioPanels.title'),
                        style: AppTypography.title,
                      ),
                    ),
                    if (_actionFeedback != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppSpacing.r10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          _actionFeedback!,
                          style: AppTypography.caption
                              .copyWith(color: AppColors.accent),
                        ),
                      ),
                  ],
                ),
              ),

              // Main body
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 1100;

                    if (isWide) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 640,
                              child: _buildEqualizerCard(context, eq),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 552,
                              child: _buildSignalPathCard(context, eq),
                            ),
                          ],
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 520,
                            child: _buildEqualizerCard(context, eq),
                          ),
                          const SizedBox(height: 16),
                          _buildSignalPathCard(context, eq),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (eq != null) {
      return ListenableBuilder(
        listenable: eq,
        builder: (context, _) => buildContent(context),
      );
    }
    return buildContent(context);
  }

  // ── Equalizer Panel ───────────────────────────────────────────────────────
  Widget _buildEqualizerCard(BuildContext context, EqController? eq) {
    final canEq = widget.engine.capabilities.equalizer && eq != null;

    return GlassSurface(
      density: GlassDensity.regular,
      borderRadius: AppSpacing.r22,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title & Enabled switch
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.t('audioPanels.equalizer'),
                    style: AppTypography.title,
                  ),
                ),
                Switch(
                  key: const Key('eq_enabled_switch'),
                  value: eq?.enabled ?? false,
                  activeThumbColor: AppColors.accent,
                  onChanged: canEq ? (val) => eq.setEnabled(val) : null,
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!canEq) ...[
              Expanded(
                child: Center(
                  child: Text(
                    context.t('audioPanels.eqDisabled'),
                    style: AppTypography.body
                        .copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ] else ...[
              // Presets row
              _buildPresetsRow(context, eq),
              const SizedBox(height: 16),

              // Sliders (low to high, LTR in both languages)
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Preamp slider
                      _buildVerticalSlider(
                        context,
                        label: context.t('audioPanels.preamp'),
                        value: eq.preampDb,
                        frequency: null,
                        enabled: eq.enabled,
                        onChanged: (val) => eq.setPreamp(val),
                        onReset: () => eq.setPreamp(0.0),
                      ),
                      const VerticalDivider(
                        color: AppColors.borderSubtle,
                        width: 20,
                        indent: 16,
                        endIndent: 16,
                      ),
                      // 10 bands
                      Expanded(
                        child: Row(
                          children: [
                            for (int i = 0; i < 10; i++)
                              Expanded(
                                child: _buildVerticalSlider(
                                  context,
                                  label: _formatFrequency(
                                      AudioEngine.eqFrequencies[i]),
                                  value: eq.gains[i],
                                  frequency: AudioEngine.eqFrequencies[i],
                                  enabled: eq.enabled,
                                  onChanged: (val) => eq.setBand(i, val),
                                  onReset: () => eq.setBand(i, 0.0),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Footer: Range & Reset button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      context.t('audioPanels.rangeHint'),
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GlassPillButton(
                    key: const Key('eq_reset_button'),
                    label: context.t('audioPanels.reset'),
                    onPressed: canEq ? () => eq.reset() : null,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPresetsRow(BuildContext context, EqController eq) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in kBuiltInEqPresets) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildPresetChip(
                context,
                title: context.t(preset.nameKey),
                isSelected: eq.presetId == preset.id,
                onTap: () => eq.applyPreset(preset.id),
              ),
            ),
          ],
          for (final custom in eq.customPresets) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildPresetChip(
                context,
                title: custom.name,
                isSelected: eq.presetId == custom.name,
                onTap: () => eq.applyPreset(custom.name),
                onDelete: () => eq.deleteCustomPreset(custom.name),
              ),
            ),
          ],
          // Save preset chip
          if (!_isSavingPreset)
            InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.pill),
              onTap: () {
                setState(() {
                  _isSavingPreset = true;
                  _presetErrorKey = null;
                  _presetNameController.clear();
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.pill),
                  border: Border.all(
                    color: AppColors.border,
                    style: BorderStyle.solid,
                  ),
                  color: AppColors.fillGlass,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 14, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      context.t('audioPanels.savePreset'),
                      style: AppTypography.caption
                          .copyWith(color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 140,
                  height: 32,
                  child: TextField(
                    controller: _presetNameController,
                    autofocus: true,
                    style: AppTypography.caption,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      hintText: context.t('audioPanels.presetName'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.r10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onSubmitted: (name) => _submitCustomPreset(eq, name),
                  ),
                ),
                const SizedBox(width: 6),
                GlassIconButton(
                  icon: Icons.check,
                  tooltip: context.t('audioPanels.save'),
                  semanticLabel: context.t('audioPanels.save'),
                  onPressed: () =>
                      _submitCustomPreset(eq, _presetNameController.text),
                ),
                GlassIconButton(
                  icon: Icons.close,
                  tooltip: context.t('audioPanels.cancel'),
                  semanticLabel: context.t('audioPanels.cancel'),
                  onPressed: () {
                    setState(() {
                      _isSavingPreset = false;
                      _presetErrorKey = null;
                    });
                  },
                ),
              ],
            ),
          ],
          if (_presetErrorKey != null) ...[
            const SizedBox(width: 8),
            Text(
              context.t(_presetErrorKey!),
              style: AppTypography.caption.copyWith(color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  void _submitCustomPreset(EqController eq, String name) {
    final err = eq.saveCustomPreset(name);
    if (err == null) {
      setState(() {
        _isSavingPreset = false;
        _presetErrorKey = null;
        _presetNameController.clear();
      });
    } else {
      setState(() => _presetErrorKey = err);
    }
  }

  Widget _buildPresetChip(
    BuildContext context, {
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentFill : AppColors.fillControl,
          borderRadius: BorderRadius.circular(AppSpacing.pill),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTypography.caption.copyWith(
                color: isSelected ? AppColors.accent : AppColors.text,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onDelete,
                child: const Icon(Icons.close,
                    size: 12, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalSlider(
    BuildContext context, {
    required String label,
    required double value,
    required int? frequency,
    required bool enabled,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    final formattedValue = localizeDigits(
      '${value > 0 ? '+' : ''}${value.toStringAsFixed(0)}',
      arabicIndic: context.usesArabicIndicDigits,
    );

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final step = HardwareKeyboard.instance.isShiftPressed ? 2.0 : 0.5;
        if (isArrowUpKey(event)) {
          onChanged((value + step).clamp(-12.0, 12.0));
          return KeyEventResult.handled;
        }
        if (isArrowDownKey(event)) {
          onChanged((value - step).clamp(-12.0, 12.0));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (focusCtx) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Focus.of(focusCtx).requestFocus(),
          onDoubleTap: onReset,
          child: Semantics(
            label: frequency != null
                ? '${frequency}Hz, ${value.toStringAsFixed(1)}dB'
                : 'Preamp, ${value.toStringAsFixed(1)}dB',
            child: Column(
              children: [
                // Value top label
                Text(
                  formattedValue,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: enabled ? AppColors.textSecondary : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),

                // Vertical slider area
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Faint 0 dB line
                      Container(
                        width: 24,
                        height: 1,
                        color: AppColors.borderSubtle,
                      ),
                      RotatedBox(
                        quarterTurns: 3,
                        child: ExcludeFocus(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              activeTrackColor: enabled
                                  ? AppColors.accent
                                  : AppColors.borderSubtle,
                              inactiveTrackColor: AppColors.borderSubtle,
                              thumbColor: enabled
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              value: value.clamp(-12.0, 12.0),
                              min: -12.0,
                              max: 12.0,
                              onChanged: enabled ? onChanged : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Frequency / bottom label
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatFrequency(int freq) {
    return freq >= 1000 ? '${freq ~/ 1000}k' : '$freq';
  }

  // ── Signal Path Panel ─────────────────────────────────────────────────────
  Widget _buildSignalPathCard(BuildContext context, EqController? eq) {
    return StreamBuilder<AudioStreamInfo?>(
      stream: widget.engine.streamInfoStream,
      initialData: widget.engine.currentStreamInfo,
      builder: (context, streamSnap) {
        return StreamBuilder<List<AudioDevice>>(
          stream: widget.engine.devicesStream,
          initialData: widget.engine.devices,
          builder: (context, devSnap) {
            final applier = widget.audioSettingsApplier ??
                AudioSettingsApplier(
                  engine: widget.engine,
                  settingsStore: widget.settingsStore,
                );

            final model = buildSignalPathModel(
              streamInfo: streamSnap.data,
              eqEnabled: eq?.enabled ?? false,
              eqPresetId: eq?.presetId ?? 'flat',
              eqPreampDb: eq?.preampDb ?? 0.0,
              replayGainMode: widget.engine.replayGainMode,
              replayGainPreamp: widget.engine.replayGainPreamp,
              currentDevice: widget.engine.currentDevice,
              isExclusiveMode: widget.engine.isExclusiveMode,
              capabilities: widget.engine.capabilities,
            );

            return GlassSurface(
              density: GlassDensity.regular,
              borderRadius: AppSpacing.r22,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Text(
                        context.t('signalPath.title'),
                        style: AppTypography.title,
                      ),
                      const SizedBox(height: 14),

                      // Stage 1: Source
                      _buildStageCard(
                        context,
                        stageNumber: 1,
                        title: context.t('signalPath.stageSource'),
                        badgeText: switch (model.sourceBadge) {
                          AudioLosslessBadge.lossless =>
                            context.t('signalPath.lossless'),
                          AudioLosslessBadge.lossy =>
                            context.t('signalPath.lossy'),
                          AudioLosslessBadge.unknown =>
                            context.t('signalPath.unknown'),
                        },
                        badgeColor:
                            model.sourceBadge == AudioLosslessBadge.lossless
                                ? AppColors.success
                                : AppColors.textSecondary,
                        explanation: context.t('signalPath.explainSource'),
                        rows: model.isPlaying
                            ? [
                                _StageRow(
                                  label: context.t('signalPath.codec'),
                                  value: model.sourceCodec,
                                ),
                                _StageRow(
                                  label: context.t('signalPath.container'),
                                  value: model.sourceContainer,
                                ),
                                _StageRow(
                                  label: context.t('signalPath.sampleRate'),
                                  value: model.sourceSampleRate,
                                ),
                                _StageRow(
                                  label: context.t('signalPath.bitDepth'),
                                  value: model.sourceBitDepth,
                                ),
                                _StageRow(
                                  label: context.t('signalPath.channels'),
                                  value: model.sourceChannels,
                                ),
                                _StageRow(
                                  label: context.t('signalPath.bitrate'),
                                  value: model.sourceBitrate,
                                ),
                              ]
                            : [
                                _StageRow(
                                  label: '',
                                  value: context.t('signalPath.nothingPlaying'),
                                ),
                              ],
                      ),
                      const SizedBox(height: 10),

                      // Stage 2: Decoder
                      _buildStageCard(
                        context,
                        stageNumber: 2,
                        title: context.t('signalPath.stageDecoder'),
                        badgeText: model.decoderEngine,
                        badgeColor: AppColors.accent,
                        explanation: context.t('signalPath.explainDecoder'),
                        rows: [
                          _StageRow(
                            label: context.t('signalPath.engine'),
                            value: model.decoderEngine,
                          ),
                          _StageRow(
                            label: context.t('signalPath.codec'),
                            value: model.decoderCodec,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Stage 3: Processing
                      _buildStageCard(
                        context,
                        stageNumber: 3,
                        title: context.t('signalPath.stageProcessing'),
                        badgeText: model.hasProcessing
                            ? context.t('signalPath.changesSound')
                            : context.t('signalPath.off'),
                        badgeColor: model.hasProcessing
                            ? AppColors.accent
                            : AppColors.textMuted,
                        explanation: context.t('signalPath.explainProcessing'),
                        rows: [
                          _StageRow(
                            label: context.t('signalPath.equalizer'),
                            value: model.eqStatus,
                          ),
                          _StageRow(
                            label: context.t('signalPath.replayGain'),
                            value: model.replayGainStatus,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Stage 4: Output
                      _buildStageCard(
                        context,
                        stageNumber: 4,
                        title: context.t('signalPath.stageOutput'),
                        badgeText: model.outputMode,
                        badgeColor: model.outputMode == 'Exclusive'
                            ? AppColors.success
                            : AppColors.textSecondary,
                        explanation: context.t('signalPath.explainOutput'),
                        rows: [
                          _StageRow(
                            label: context.t('signalPath.device'),
                            value: model.outputDevice == 'System default'
                                ? context.t('signalPath.systemDefault')
                                : model.outputDevice,
                          ),
                          _StageRow(
                            label: context.t('signalPath.mode'),
                            value: model.outputMode == 'Exclusive'
                                ? context.t('signalPath.modeExclusive')
                                : context.t('signalPath.modeShared'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Engine note
                      Text(
                        context.t('signalPath.engineNote'),
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 14),

                      // Verdict Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.fillControl,
                          borderRadius: BorderRadius.circular(AppSpacing.r12),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Text(
                          !model.hasProcessing
                              ? context.t('signalPath.verdictClean')
                              : context.t('signalPath.verdictProcessing',
                                  args: {
                                      'items': model
                                          .activeProcessingItems
                                          .join(', ')
                                    }),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.text,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Action Buttons
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          GlassPillButton(
                            label: context.t('signalPath.copyDetails'),
                            onPressed: () async {
                              final msg = context.t('signalPath.copied');
                              await Clipboard.setData(
                                  ClipboardData(text: model.toPlainText()));
                              if (!mounted) return;
                              _showFeedback(msg);
                            },
                          ),
                          GlassPillButton(
                            label:
                                context.t('signalPath.turnOffProcessing'),
                            onPressed: () async {
                              final msg =
                                  context.t('signalPath.processingDisabled');
                              if (eq != null) {
                                await eq.setEnabled(false);
                              }
                              await applier
                                  .setReplayGainMode(ReplayGainMode.off);
                              await applier.setReplayGainPreamp(0.0);
                              if (!mounted) return;
                              _showFeedback(msg);
                            },
                          ),
                        ],
                      ),
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

  Widget _buildStageCard(
    BuildContext context, {
    required int stageNumber,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required String explanation,
    required List<_StageRow> rows,
  }) {
    final isExpanded = _expandedStages.contains(stageNumber);

    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.r12),
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedStages.remove(stageNumber);
          } else {
            _expandedStages.add(stageNumber);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.fillControl,
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '$stageNumber. ',
                  style: AppTypography.bodyStrong
                      .copyWith(color: AppColors.accent),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodyStrong,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(35),
                    borderRadius: BorderRadius.circular(AppSpacing.pill),
                    border: Border.all(color: badgeColor.withAlpha(120)),
                  ),
                  child: Text(
                    badgeText,
                    style: AppTypography.caption.copyWith(
                      color: badgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 6),
              Text(
                explanation,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
            const Divider(color: AppColors.borderSubtle, height: 16),
            for (final row in rows) ...[
              if (row.label.isEmpty)
                Text(row.value, style: AppTypography.caption)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        row.label,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      Text(
                        row.value,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.text),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StageRow {
  final String label;
  final String value;

  const _StageRow({required this.label, required this.value});
}
