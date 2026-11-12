import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/audio_engine.dart';
import '../l10n/app_strings.dart';
import '../l10n/number_format.dart';
import '../settings/settings_scope.dart';
import '../settings/settings_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Shared state controller for the transient on-screen volume HUD.
class VolumeHudController extends ChangeNotifier {
  double _volume = 1.0;
  bool _visible = false;
  Timer? _hideTimer;
  bool _disposed = false;

  /// Latest displayed normalized volume (`0.0..1.0`).
  double get volume => _volume;

  /// Integer percentage (`0..100`) rounded from [volume].
  int get percent => (_volume * 100).round().clamp(0, 100);

  /// Whether the HUD is currently active before fading out.
  bool get isVisible => _visible;

  /// Shows the HUD for [volume] and hides it cleanly after [holdDuration].
  void show(
    double volume, {
    Duration holdDuration = const Duration(seconds: 1),
  }) {
    if (_disposed) return;
    _volume = volume.clamp(0.0, 1.0);
    _visible = true;
    _hideTimer?.cancel();
    _hideTimer = Timer(holdDuration, () {
      if (_disposed) return;
      _visible = false;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Hides the HUD immediately and cancels any pending fade timer.
  void hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_disposed || !_visible) return;
    _visible = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hideTimer?.cancel();
    _hideTimer = null;
    super.dispose();
  }
}

/// Provides a [VolumeHudController] to descendant widgets without extra constructor plumbing.
class VolumeHudScope extends InheritedNotifier<VolumeHudController> {
  /// Creates a [VolumeHudScope].
  const VolumeHudScope({
    super.key,
    required VolumeHudController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Returns the nearest [VolumeHudController], or `null` if none is mounted.
  static VolumeHudController? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<VolumeHudScope>()
        ?.notifier;
  }
}

/// Applies a clamped, rounded volume step, persists it, and flashes [hudController].
double adjustVolumeByStep({
  required AudioEngine engine,
  required double currentVolume,
  required double delta,
  SettingsStore? settingsStore,
  VolumeHudController? hudController,
}) {
  final clamped = (currentVolume + delta).clamp(0.0, 1.0);
  final rounded = (clamped * 100).round() / 100.0;
  engine.setVolume(rounded);
  settingsStore?.update((s) => s.copyWith(volume: rounded));
  hudController?.show(rounded);
  return rounded;
}

/// Floating transient volume indicator overlay mounted at the app root.
class VolumeHudOverlay extends StatelessWidget {
  /// Volume HUD controller driving visibility and value.
  final VolumeHudController controller;

  /// Content beneath the floating HUD.
  final Widget child;

  /// Creates a [VolumeHudOverlay].
  const VolumeHudOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 16,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final reduceMotion =
                      SettingsScope.maybeOf(context)?.settings.reduceMotion ??
                          false;
                  final fadeDuration = reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220);
                  final pctText =
                      context.localizeDigitsText('${controller.percent}%');
                  final iconData = controller.percent == 0
                      ? Icons.volume_off
                      : (controller.percent < 50
                          ? Icons.volume_down
                          : Icons.volume_up);

                  return IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: controller.isVisible ? 1.0 : 0.0,
                      duration: fadeDuration,
                      curve: Curves.easeOutCubic,
                      child: Semantics(
                        label: context.t('volume.hudLabel'),
                        value: pctText,
                        child: Container(
                          key: const Key('volume_hud'),
                          constraints: const BoxConstraints(maxWidth: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(AppSpacing.r12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                iconData,
                                size: 18,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: SizedBox(
                                  width: 84,
                                  height: 4,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: ColoredBox(
                                      color: AppColors.border,
                                      child: FractionallySizedBox(
                                        alignment: AlignmentDirectional.centerStart,
                                        widthFactor:
                                            controller.volume.clamp(0.0, 1.0),
                                        child: const ColoredBox(
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                pctText,
                                style: AppTypography.micro.copyWith(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
