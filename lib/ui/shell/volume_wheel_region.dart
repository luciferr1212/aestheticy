import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_engine.dart';
import '../settings/settings_scope.dart';
import '../settings/settings_store.dart';
import 'volume_hud.dart';

/// Shared widget providing mouse-wheel and trackpad volume adjustments across all volume surfaces.
///
/// Listens to [PointerScrollEvent]s, registers with [pointerSignalResolver] to consume
/// the scroll event so underlying content does not scroll, and dispatches to [adjustVolumeByStep].
///
/// Trackpads accumulate [scrollDelta.dy] and step once per 40 logical pixels (clamped),
/// while discrete mouse wheel notches trigger +/-0.05 per notch.
class VolumeWheelRegion extends StatefulWidget {
  /// The interactive child widget wrapped by this region.
  final Widget child;

  /// The audio engine instance (can be null if engine is unavailable).
  final AudioEngine? engine;

  /// Optional settings store for volume persistence (defaults to ambient [SettingsScope]).
  final SettingsStore? settingsStore;

  /// Optional volume HUD controller (defaults to ambient [VolumeHudScope]).
  final VolumeHudController? hudController;

  /// Hit test behavior for the listener.
  final HitTestBehavior behavior;

  /// Creates a [VolumeWheelRegion].
  const VolumeWheelRegion({
    super.key,
    required this.child,
    required this.engine,
    this.settingsStore,
    this.hudController,
    this.behavior = HitTestBehavior.deferToChild,
  });

  @override
  State<VolumeWheelRegion> createState() => _VolumeWheelRegionState();
}

class _VolumeWheelRegionState extends State<VolumeWheelRegion> {
  static const double _kAccumulatorThreshold = 40.0;
  static const Duration _kResetPauseDuration = Duration(milliseconds: 300);

  double _accumulatedDy = 0.0;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    _resetTimer = null;
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (widget.engine == null) return;
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (!mounted) return;
      final engine = widget.engine;
      if (engine == null) return;

      final scroll = resolved as PointerScrollEvent;
      final deltaDy = scroll.scrollDelta.dy;
      if (deltaDy == 0) return;

      // Reset accumulator if scrolling direction flips
      if ((_accumulatedDy > 0 && deltaDy < 0) ||
          (_accumulatedDy < 0 && deltaDy > 0)) {
        _accumulatedDy = 0.0;
      }

      // Schedule pause reset timer
      _resetTimer?.cancel();
      _resetTimer = Timer(_kResetPauseDuration, () {
        _accumulatedDy = 0.0;
      });

      _accumulatedDy += deltaDy;

      if (_accumulatedDy.abs() >= _kAccumulatorThreshold) {
        final stepDelta = _accumulatedDy < 0 ? 0.05 : -0.05;
        _accumulatedDy = 0.0;

        final settings =
            widget.settingsStore ?? SettingsScope.maybeOf(context);
        final hud = widget.hudController ??
            (context.mounted ? VolumeHudScope.maybeOf(context) : null);
        final currentVol =
            settings?.settings.volume ?? engine.currentVolume;

        adjustVolumeByStep(
          engine: engine,
          currentVolume: currentVol,
          delta: stepDelta,
          settingsStore: settings,
          hudController: hud,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior,
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}
