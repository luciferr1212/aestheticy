import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/audio_engine.dart';
import '../glass/glass_button.dart';
import '../l10n/app_strings.dart';
import '../settings/app_shortcuts.dart';
import '../settings/audio_settings_applier.dart';
import '../settings/settings_store.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'eq_controller.dart';
import 'eq_scope.dart';
import 'widgets/equalizer_panel_card.dart';
import 'widgets/signal_path_panel_card.dart';

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
  String? _actionFeedback;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _focusNode.dispose();
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
                padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 16),
                child: Row(
                  children: [
                    GlassIconButton(
                      key: const Key('audio_panels_back_button'),
                      icon: Icons.arrow_back,
                      matchTextDirection: true,
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
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 640,
                              child: EqualizerPanelCard(
                                engine: widget.engine,
                                eq: eq,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 552,
                              child: SignalPathPanelCard(
                                engine: widget.engine,
                                eq: eq,
                                audioSettingsApplier:
                                    widget.audioSettingsApplier,
                                settingsStore: widget.settingsStore,
                                onShowFeedback: _showFeedback,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 520,
                            child: EqualizerPanelCard(
                              engine: widget.engine,
                              eq: eq,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SignalPathPanelCard(
                            engine: widget.engine,
                            eq: eq,
                            audioSettingsApplier: widget.audioSettingsApplier,
                            settingsStore: widget.settingsStore,
                            onShowFeedback: _showFeedback,
                          ),
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
}
