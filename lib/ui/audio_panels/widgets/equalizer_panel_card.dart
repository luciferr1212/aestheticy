import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../audio/audio_engine.dart';
import '../../glass/glass_button.dart';
import '../../glass/glass_surface.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../settings/app_shortcuts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../eq_controller.dart';
import '../eq_store.dart';

/// 10-band equalizer panel with built-in/custom presets and keyboard slider control.
class EqualizerPanelCard extends StatefulWidget {
  /// Underlying audio engine for capability checks.
  final AudioEngine engine;

  /// Active equalizer controller, if available.
  final EqController? eq;

  /// Creates an [EqualizerPanelCard].
  const EqualizerPanelCard({
    super.key,
    required this.engine,
    required this.eq,
  });

  @override
  State<EqualizerPanelCard> createState() => _EqualizerPanelCardState();
}

class _EqualizerPanelCardState extends State<EqualizerPanelCard> {
  bool _isSavingPreset = false;
  final TextEditingController _presetNameController = TextEditingController();
  String? _presetErrorKey;

  @override
  void dispose() {
    _presetNameController.dispose();
    super.dispose();
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

  String _formatFrequency(int freq) {
    return freq >= 1000 ? '${freq ~/ 1000}k' : '$freq';
  }

  @override
  Widget build(BuildContext context) {
    final eq = widget.eq;
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
              padding: const EdgeInsetsDirectional.only(end: 8),
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
              padding: const EdgeInsetsDirectional.only(end: 8),
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

  Widget _buildPresetChip(
    BuildContext context, {
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      hoverColor: const Color(0x14FFFFFF),
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
                mouseCursor: SystemMouseCursors.click,
                hoverColor: const Color(0x14FFFFFF),
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
}
