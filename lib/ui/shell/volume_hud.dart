import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
  bool _isHovered = false;
  double? _mutedRestoreVolume;
  Timer? _hideTimer;
  bool _disposed = false;

  /// Latest displayed normalized volume (`0.0..1.0`).
  double get volume => _volume;

  /// Integer percentage (`0..100`) rounded from [volume].
  int get percent => (_volume * 100).round().clamp(0, 100);

  /// Whether the HUD is currently active before fading out.
  bool get isVisible => _visible;

  /// Whether the pointer is currently hovering the HUD.
  bool get isHovered => _isHovered;

  /// In-memory pre-mute volume backup, or `null` if not currently muted via toggle.
  double? get mutedRestoreVolume => _mutedRestoreVolume;

  /// Clears any stored pre-mute restore volume when volume is changed externally.
  void clearMuteBackup() {
    _mutedRestoreVolume = null;
  }

  /// Stores [value] as the pre-mute volume backup in memory.
  void setMuteBackup(double? value) {
    _mutedRestoreVolume = value;
  }

  /// Shows the HUD for [volume] and hides it cleanly after [holdDuration] once not hovered.
  void show(
    double volume, {
    Duration holdDuration = const Duration(seconds: 1),
  }) {
    if (_disposed) return;
    _volume = volume.clamp(0.0, 1.0);
    _visible = true;
    _hideTimer?.cancel();
    _hideTimer = _isHovered ? null : Timer(holdDuration, _onHideTimer);
    notifyListeners();
  }

  /// Updates pointer hover state; holds visibility while hovered and starts 1s hide on exit.
  void setHovered(
    bool hovered, {
    Duration holdDuration = const Duration(seconds: 1),
  }) {
    if (_disposed || _isHovered == hovered) return;
    _isHovered = hovered;
    if (hovered) {
      _hideTimer?.cancel();
      _hideTimer = null;
    } else if (_visible) {
      _hideTimer?.cancel();
      _hideTimer = Timer(holdDuration, _onHideTimer);
    }
    notifyListeners();
  }

  void _onHideTimer() {
    _hideTimer = null;
    if (_disposed || _isHovered) return;
    _visible = false;
    notifyListeners();
  }

  /// Hides the HUD immediately and cancels any pending fade timer.
  void hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _isHovered = false;
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

/// Applies a clamped, rounded volume step, persists it, unmutes, and flashes [hudController].
double adjustVolumeByStep({
  required AudioEngine engine,
  required double currentVolume,
  required double delta,
  SettingsStore? settingsStore,
  VolumeHudController? hudController,
}) {
  hudController?.clearMuteBackup();
  final clamped = (currentVolume + delta).clamp(0.0, 1.0);
  final rounded = (clamped * 100).round() / 100.0;
  engine.setVolume(rounded);
  settingsStore?.update((s) => s.copyWith(volume: rounded));
  hudController?.show(rounded);
  return rounded;
}

/// Sets a normalized direct [volume], persists it, unmutes, and updates [hudController].
double setVolumeDirect({
  required AudioEngine engine,
  required double volume,
  SettingsStore? settingsStore,
  VolumeHudController? hudController,
}) {
  hudController?.clearMuteBackup();
  final clamped = volume.clamp(0.0, 1.0);
  final rounded = (clamped * 100).round() / 100.0;
  engine.setVolume(rounded);
  settingsStore?.update((s) => s.copyWith(volume: rounded));
  hudController?.show(rounded);
  return rounded;
}

/// Toggles mute in memory using [hudController] backup, restoring previous non-zero or `0.5`.
double toggleVolumeMute({
  required AudioEngine engine,
  required double currentVolume,
  SettingsStore? settingsStore,
  required VolumeHudController hudController,
}) {
  final current = currentVolume.clamp(0.0, 1.0);
  final double target;
  if (current > 0.0) {
    hudController.setMuteBackup(current);
    target = 0.0;
  } else {
    final backup = hudController.mutedRestoreVolume;
    target = (backup != null && backup > 0.0) ? backup : 0.5;
    hudController.setMuteBackup(null);
  }
  engine.setVolume(target);
  settingsStore?.update((s) => s.copyWith(volume: target));
  hudController.show(target);
  return target;
}

/// Floating interactive transient volume indicator overlay mounted at the app root.
class VolumeHudOverlay extends StatefulWidget {
  /// Volume HUD controller driving visibility and value.
  final VolumeHudController controller;

  /// Optional audio engine for direct mouse/touch interactions on the HUD.
  final AudioEngine? engine;

  /// Optional persistent settings store; falls back to [SettingsScope.maybeOf].
  final SettingsStore? settingsStore;

  /// Content beneath the floating HUD.
  final Widget child;

  /// Creates a [VolumeHudOverlay].
  const VolumeHudOverlay({
    super.key,
    required this.controller,
    this.engine,
    this.settingsStore,
    required this.child,
  });

  @override
  State<VolumeHudOverlay> createState() => _VolumeHudOverlayState();
}

class _VolumeHudOverlayState extends State<VolumeHudOverlay> {
  static const Duration _kDragThrottle = Duration(milliseconds: 60);
  static const double _kBarWidth = 84.0;

  Timer? _dragThrottleTimer;
  double? _pendingDragVolume;

  @override
  void dispose() {
    _dragThrottleTimer?.cancel();
    _dragThrottleTimer = null;
    _pendingDragVolume = null;
    super.dispose();
  }

  SettingsStore? _resolveSettingsStore(BuildContext context) =>
      widget.settingsStore ?? SettingsScope.maybeOf(context);

  double _resolveCurrentVolume(BuildContext context) =>
      _resolveSettingsStore(context)?.settings.volume ??
      widget.engine?.currentVolume ??
      widget.controller.volume;

  void _stepVolume(BuildContext context, double delta) {
    final eng = widget.engine;
    if (eng == null) return;
    adjustVolumeByStep(
      engine: eng,
      currentVolume: _resolveCurrentVolume(context),
      delta: delta,
      settingsStore: _resolveSettingsStore(context),
      hudController: widget.controller,
    );
  }

  void _applyDirectVolume(BuildContext context, double volume) {
    final eng = widget.engine;
    if (eng == null) return;
    setVolumeDirect(
      engine: eng,
      volume: volume,
      settingsStore: _resolveSettingsStore(context),
      hudController: widget.controller,
    );
  }

  void _toggleMute(BuildContext context) {
    final eng = widget.engine;
    if (eng == null) return;
    toggleVolumeMute(
      engine: eng,
      currentVolume: _resolveCurrentVolume(context),
      settingsStore: _resolveSettingsStore(context),
      hudController: widget.controller,
    );
  }

  double _fractionForDx(double dx, double width, bool isRtl) {
    if (width <= 0) return 0.0;
    final raw = (dx / width).clamp(0.0, 1.0);
    return isRtl ? (1.0 - raw) : raw;
  }

  void _scheduleThrottledDrag(BuildContext context, double volume) {
    final eng = widget.engine;
    if (eng == null) return;
    if (_dragThrottleTimer == null) {
      _applyDirectVolume(context, volume);
      _dragThrottleTimer = Timer(_kDragThrottle, () {
        _dragThrottleTimer = null;
        if (!mounted) {
          _pendingDragVolume = null;
          return;
        }
        final pending = _pendingDragVolume;
        _pendingDragVolume = null;
        if (pending != null) {
          _applyDirectVolume(this.context, pending);
        }
      });
    } else {
      _pendingDragVolume = volume;
      widget.controller.show(volume);
    }
  }

  void _finishDrag(BuildContext context, {required bool commit}) {
    _dragThrottleTimer?.cancel();
    _dragThrottleTimer = null;
    final pending = _pendingDragVolume;
    _pendingDragVolume = null;
    if (commit && pending != null) {
      _applyDirectVolume(context, pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 16,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final reduceMotion =
                      _resolveSettingsStore(context)?.settings.reduceMotion ??
                          false;
                  final fadeDuration = reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220);
                  final visible = widget.controller.isVisible;
                  final pct = widget.controller.percent;
                  final pctText = context.localizeDigitsText('$pct%');
                  final isZero = pct == 0;
                  final iconData = isZero
                      ? Icons.volume_off
                      : (pct < 50 ? Icons.volume_down : Icons.volume_up);
                  final isRtl = Directionality.of(context) == TextDirection.rtl;
                  final nextUpPct = math.min(100, pct + 5);
                  final nextDownPct = math.max(0, pct - 5);

                  return IgnorePointer(
                    ignoring: !visible,
                    child: AnimatedOpacity(
                      opacity: visible ? 1.0 : 0.0,
                      duration: fadeDuration,
                      curve: Curves.easeOutCubic,
                      child: Material(
                        type: MaterialType.transparency,
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(
                            decoration: TextDecoration.none,
                          ),
                          child: MouseRegion(
                            onEnter: (_) => widget.controller.setHovered(true),
                            onExit: (_) => widget.controller.setHovered(false),
                            child: Listener(
                              key: const Key('volume_hud_wheel_listener'),
                              onPointerSignal: (event) {
                                if (widget.engine == null) return;
                                if (event is PointerScrollEvent &&
                                    event.scrollDelta.dy != 0) {
                                  GestureBinding.instance.pointerSignalResolver
                                      .register(
                                    event,
                                    (resolved) {
                                      final scroll =
                                          resolved as PointerScrollEvent;
                                      final delta = scroll.scrollDelta.dy < 0
                                          ? 0.05
                                          : -0.05;
                                      if (mounted) {
                                        _stepVolume(context, delta);
                                      }
                                    },
                                  );
                                }
                              },
                              child: Container(
                                key: const Key('volume_hud'),
                                constraints: const BoxConstraints(maxWidth: 232),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface
                                      .withValues(alpha: 0.94),
                                  borderRadius:
                                      BorderRadius.circular(AppSpacing.r12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Semantics(
                                      button: true,
                                      label: isZero
                                          ? context.t('volume.unmute')
                                          : context.t('volume.mute'),
                                      onTap: widget.engine != null
                                          ? () => _toggleMute(context)
                                          : null,
                                      child: MouseRegion(
                                        cursor: widget.engine != null
                                            ? SystemMouseCursors.click
                                            : MouseCursor.defer,
                                        child: GestureDetector(
                                          key: const Key(
                                            'volume_hud_mute_button',
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _toggleMute(context),
                                          child: Padding(
                                            padding: const EdgeInsets.all(2),
                                            child: Icon(
                                              iconData,
                                              size: 18,
                                              color: AppColors.accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Semantics(
                                        slider: true,
                                        label: context.t('volume.hudLabel'),
                                        value: pctText,
                                        increasedValue: context
                                            .localizeDigitsText('$nextUpPct%'),
                                        decreasedValue: context
                                            .localizeDigitsText(
                                                '$nextDownPct%'),
                                        onIncrease: widget.engine != null
                                            ? () => _stepVolume(context, 0.05)
                                            : null,
                                        onDecrease: widget.engine != null
                                            ? () => _stepVolume(context, -0.05)
                                            : null,
                                        child: MouseRegion(
                                          cursor: widget.engine != null
                                              ? SystemMouseCursors.click
                                              : MouseCursor.defer,
                                          child: GestureDetector(
                                            key: const Key('volume_hud_bar'),
                                            behavior: HitTestBehavior.opaque,
                                            onTapUp: (details) {
                                              final frac = _fractionForDx(
                                                details.localPosition.dx,
                                                _kBarWidth,
                                                isRtl,
                                              );
                                              _applyDirectVolume(context, frac);
                                            },
                                            onHorizontalDragStart: (details) {
                                              final frac = _fractionForDx(
                                                details.localPosition.dx,
                                                _kBarWidth,
                                                isRtl,
                                              );
                                              _scheduleThrottledDrag(
                                                context,
                                                frac,
                                              );
                                            },
                                            onHorizontalDragUpdate: (details) {
                                              final frac = _fractionForDx(
                                                details.localPosition.dx,
                                                _kBarWidth,
                                                isRtl,
                                              );
                                              _scheduleThrottledDrag(
                                                context,
                                                frac,
                                              );
                                            },
                                            onHorizontalDragEnd: (_) =>
                                                _finishDrag(
                                              context,
                                              commit: true,
                                            ),
                                            onHorizontalDragCancel: () =>
                                                _finishDrag(
                                              context,
                                              commit: false,
                                            ),
                                            child: SizedBox(
                                              width: _kBarWidth,
                                              height: 20,
                                              child: Center(
                                                child: SizedBox(
                                                  width: _kBarWidth,
                                                  height: 4,
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(2),
                                                    child: ColoredBox(
                                                      color: AppColors.border,
                                                      child:
                                                          FractionallySizedBox(
                                                        alignment:
                                                            AlignmentDirectional
                                                                .centerStart,
                                                        widthFactor: widget
                                                            .controller.volume
                                                            .clamp(0.0, 1.0),
                                                        child: const ColoredBox(
                                                          color:
                                                              AppColors.accent,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      pctText,
                                      key: const Key('volume_hud_percent'),
                                      style: AppTypography.micro.copyWith(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
