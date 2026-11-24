import 'dart:async';

import 'package:flutter/material.dart';

import '../../../features/lyrics/lyrics_controller.dart';
import '../../../features/lyrics/lyrics_offset_store.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/number_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Pill control allowing users to adjust and reset per-track lyrics timing offset.
class LyricsSyncControl extends StatelessWidget {
  /// The lyrics controller managing the offset.
  final LyricsController controller;

  /// Creates a [LyricsSyncControl].
  const LyricsSyncControl({super.key, required this.controller});

  String _formatOffsetValue(BuildContext context, int offsetMs) {
    final String valueStr;
    if (offsetMs == 0) {
      valueStr = context.localizeDigitsText('0');
    } else {
      final sign = offsetMs > 0 ? '+' : '-';
      final formatted = (offsetMs.abs() / 1000.0).toStringAsFixed(1);
      valueStr = context.localizeDigitsText('$sign$formatted');
    }
    return context.t('lyrics.sync.secondsFormat', args: {'value': valueStr});
  }

  void _step(int deltaMs) {
    controller.setOffset(controller.offsetMs + deltaMs);
  }

  @override
  Widget build(BuildContext context) {
    final offsetMs = controller.offsetMs;
    final canDecrease = offsetMs > kMinLyricsOffsetMs;
    final canIncrease = offsetMs < kMaxLyricsOffsetMs;
    final formattedValue = _formatOffsetValue(context, offsetMs);

    return Container(
      key: const Key('lyrics_sync_control'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.fillControl,
        borderRadius: BorderRadius.circular(AppSpacing.pill),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: [
          Text(
            context.t('lyrics.sync.label'),
            style: AppTypography.micro.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          HoldRepeatStepButton(
            key: const Key('lyrics_sync_minus'),
            icon: Icons.remove,
            tooltip: context.t('lyrics.sync.earlierTooltip'),
            enabled: canDecrease,
            onStep: () => _step(-kLyricsOffsetStepMs),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              formattedValue,
              key: const Key('lyrics_sync_value'),
              style: AppTypography.micro.copyWith(
                color: offsetMs == 0 ? AppColors.textMuted : AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          HoldRepeatStepButton(
            key: const Key('lyrics_sync_plus'),
            icon: Icons.add,
            tooltip: context.t('lyrics.sync.laterTooltip'),
            enabled: canIncrease,
            onStep: () => _step(kLyricsOffsetStepMs),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: const Key('lyrics_sync_reset'),
            onPressed: offsetMs != 0 ? () => controller.resetOffset() : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 24),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppColors.text,
              disabledForegroundColor: AppColors.textMuted.withValues(alpha: 0.4),
            ),
            child: Text(
              context.t('lyrics.sync.reset'),
              style: AppTypography.micro.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon button that fires once on tap and repeats while held down.
class HoldRepeatStepButton extends StatefulWidget {
  /// Icon rendered inside the button.
  final IconData icon;

  /// Tooltip and semantic label.
  final String tooltip;

  /// Whether the button accepts pointer and semantic taps.
  final bool enabled;

  /// Callback invoked on tap and each repeat tick.
  final VoidCallback onStep;

  /// Creates a [HoldRepeatStepButton].
  const HoldRepeatStepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onStep,
  });

  @override
  State<HoldRepeatStepButton> createState() => _HoldRepeatStepButtonState();
}

class _HoldRepeatStepButtonState extends State<HoldRepeatStepButton> {
  Timer? _holdDelayTimer;
  Timer? _repeatTimer;
  bool _didRepeat = false;

  void _cancelTimers() {
    _holdDelayTimer?.cancel();
    _holdDelayTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _startHold() {
    _cancelTimers();
    _didRepeat = false;
    if (!widget.enabled) return;
    _holdDelayTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || !widget.enabled) return;
      _didRepeat = true;
      widget.onStep();
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (!mounted || !widget.enabled) {
          _cancelTimers();
          return;
        }
        widget.onStep();
      });
    });
  }

  void _endHold({required bool handleTap}) {
    final wasRepeat = _didRepeat;
    _cancelTimers();
    _didRepeat = false;
    if (handleTap && !wasRepeat && widget.enabled) {
      widget.onStep();
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? AppColors.text
        : AppColors.textMuted.withValues(alpha: 0.4);

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.tooltip,
        onTap: widget.enabled ? widget.onStep : null,
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: widget.enabled ? (_) => _startHold() : null,
            onPointerUp:
                widget.enabled ? (_) => _endHold(handleTap: true) : null,
            onPointerCancel: (_) => _endHold(handleTap: false),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Icon(widget.icon, size: 15, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
