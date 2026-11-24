import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../audio/audio_engine.dart';
import '../../../audio/audio_models.dart';
import '../../glass/glass_button.dart';
import '../../glass/glass_surface.dart';
import '../../l10n/app_strings.dart';
import '../../settings/audio_settings_applier.dart';
import '../../settings/settings_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../eq_controller.dart';
import '../signal_path_model.dart';

/// Signal Path card showing Source, Decoder, Processing, Output, and actions.
class SignalPathPanelCard extends StatefulWidget {
  /// Underlying audio engine.
  final AudioEngine engine;

  /// Active equalizer controller, if available.
  final EqController? eq;

  /// Optional audio settings applier.
  final AudioSettingsApplier? audioSettingsApplier;

  /// Persistent settings store.
  final SettingsStore settingsStore;

  /// Callback displaying transient feedback messages.
  final ValueChanged<String> onShowFeedback;

  /// Creates a [SignalPathPanelCard].
  const SignalPathPanelCard({
    super.key,
    required this.engine,
    required this.eq,
    required this.audioSettingsApplier,
    required this.settingsStore,
    required this.onShowFeedback,
  });

  @override
  State<SignalPathPanelCard> createState() => _SignalPathPanelCardState();
}

class _SignalPathPanelCardState extends State<SignalPathPanelCard> {
  final Set<int> _expandedStages = {};

  @override
  Widget build(BuildContext context) {
    final eq = widget.eq;

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
                                SignalPathStageRow(
                                  label: context.t('signalPath.codec'),
                                  value: model.sourceCodec,
                                ),
                                SignalPathStageRow(
                                  label: context.t('signalPath.container'),
                                  value: model.sourceContainer,
                                ),
                                SignalPathStageRow(
                                  label: context.t('signalPath.sampleRate'),
                                  value: model.sourceSampleRate,
                                ),
                                SignalPathStageRow(
                                  label: context.t('signalPath.bitDepth'),
                                  value: model.sourceBitDepth,
                                ),
                                SignalPathStageRow(
                                  label: context.t('signalPath.channels'),
                                  value: model.sourceChannels,
                                ),
                                SignalPathStageRow(
                                  label: context.t('signalPath.bitrate'),
                                  value: model.sourceBitrate,
                                ),
                              ]
                            : [
                                SignalPathStageRow(
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
                          SignalPathStageRow(
                            label: context.t('signalPath.engine'),
                            value: model.decoderEngine,
                          ),
                          SignalPathStageRow(
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
                          SignalPathStageRow(
                            label: context.t('signalPath.equalizer'),
                            value: model.eqStatus,
                          ),
                          SignalPathStageRow(
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
                          SignalPathStageRow(
                            label: context.t('signalPath.device'),
                            value: model.outputDevice == 'System default'
                                ? context.t('signalPath.systemDefault')
                                : model.outputDevice,
                          ),
                          SignalPathStageRow(
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
                                    'items':
                                        model.activeProcessingItems.join(', ')
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
                              widget.onShowFeedback(msg);
                            },
                          ),
                          GlassPillButton(
                            label: context.t('signalPath.turnOffProcessing'),
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
                              widget.onShowFeedback(msg);
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
    required List<SignalPathStageRow> rows,
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

/// Key/value metadata row displayed inside a [SignalPathPanelCard] stage card.
class SignalPathStageRow {
  /// Row label (or empty string for full-width status text).
  final String label;

  /// Row value text.
  final String value;

  /// Creates a [SignalPathStageRow].
  const SignalPathStageRow({required this.label, required this.value});
}
