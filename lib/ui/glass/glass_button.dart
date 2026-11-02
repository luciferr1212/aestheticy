import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'glass_quality.dart';
import 'glass_scope.dart';

/// Styling variants for glass buttons.
enum GlassButtonVariant {
  /// Standard translucent control button.
  normal,

  /// Translucent accent button reserved strictly for Play/Pause transport.
  primary,

  /// Toggled-on state with accent fill and accent icon (e.g. active shuffle/repeat).
  selected,
}

/// Size presets for glass buttons.
enum GlassButtonSize {
  /// 32.0 dp height/diameter with 16.0 dp icon.
  small(32.0, 16.0),

  /// 40.0 dp height/diameter with 20.0 dp icon.
  medium(40.0, 20.0),

  /// 56.0 dp height/diameter with 28.0 dp icon.
  large(56.0, 28.0);

  /// Height or circular diameter in dp.
  final double dimension;

  /// Icon size in dp.
  final double iconSize;

  const GlassButtonSize(this.dimension, this.iconSize);
}

/// Circular translucent glass icon button with keyboard and gesture states.
class GlassIconButton extends StatefulWidget {
  /// The icon symbol to display.
  final IconData icon;

  /// Tooltip message displayed on hover/focus.
  final String tooltip;

  /// Accessibility semantic label.
  final String semanticLabel;

  /// Callback when pressed. If null, button renders disabled.
  final VoidCallback? onPressed;

  /// Button styling variant.
  final GlassButtonVariant variant;

  /// Button size preset.
  final GlassButtonSize size;

  /// Creates a [GlassIconButton].
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    this.onPressed,
    this.variant = GlassButtonVariant.normal,
    this.size = GlassButtonSize.medium,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  bool get _isEnabled => widget.onPressed != null;

  Color _resolveFillColor(GlassQuality quality) {
    if (quality == GlassQuality.off) {
      // Solid subtle fill (surface lightened by 6%) with no transparency
      return const Color(0xFF282733);
    }

    switch (widget.variant) {
      case GlassButtonVariant.primary:
      case GlassButtonVariant.selected:
        if (_isPressed) {
          // -2% alpha: 24% alpha -> 0x3D
          return const Color(0x3DD3C9EA);
        }
        if (_isHovered) {
          // +4% alpha: 30% alpha -> 0x4D
          return const Color(0x4DD3C9EA);
        }
        return AppColors.accentFill; // 26% alpha -> 0x42
      case GlassButtonVariant.normal:
        if (_isPressed) {
          // -2% alpha: 5% alpha -> 0x0D
          return const Color(0x0DFFFFFF);
        }
        if (_isHovered) {
          // +4% alpha: 11% alpha -> 0x1C
          return const Color(0x1CFFFFFF);
        }
        return AppColors.fillControl; // 7% alpha -> 0x12
    }
  }

  Border _resolveBorder() {
    if (_isFocused) {
      return Border.all(color: AppColors.accent, width: 2.0);
    }
    if (widget.variant == GlassButtonVariant.primary) {
      // Accent at 45% alpha (0x73)
      return Border.all(color: const Color(0x73D3C9EA), width: 1.0);
    }
    return Border.all(color: AppColors.border, width: 1.0);
  }

  Color _resolveIconColor() {
    switch (widget.variant) {
      case GlassButtonVariant.primary:
        return AppColors.text;
      case GlassButtonVariant.selected:
        return AppColors.accent;
      case GlassButtonVariant.normal:
        return AppColors.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final quality = GlassScope.qualityOf(context);
    final isEnabled = _isEnabled;
    final fill = _resolveFillColor(quality);
    final border = _resolveBorder();
    final iconColor = _resolveIconColor();

    Widget button = FocusableActionDetector(
      enabled: isEnabled,
      onShowHoverHighlight: (v) {
        if (isEnabled && _isHovered != v) {
          setState(() => _isHovered = v);
        }
      },
      onShowFocusHighlight: (v) {
        if (isEnabled && _isFocused != v) {
          setState(() => _isFocused = v);
        }
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPressed?.call(),
        ),
      },
      mouseCursor:
          isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel:
            isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.size.dimension,
          height: widget.size.dimension,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: border,
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: widget.size.iconSize,
            color: iconColor,
          ),
        ),
      ),
    );

    if (!isEnabled) {
      button = Opacity(opacity: 0.40, child: button);
    }

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: isEnabled,
      child: Tooltip(
        message: widget.tooltip,
        child: button,
      ),
    );
  }
}

/// Translucent glass pill button with text label and optional leading icon.
class GlassPillButton extends StatefulWidget {
  /// The text label displayed inside the pill.
  final String label;

  /// Optional leading icon preceding the label.
  final IconData? leadingIcon;

  /// Callback when pressed. If null, button renders disabled.
  final VoidCallback? onPressed;

  /// Button styling variant.
  final GlassButtonVariant variant;

  /// Button size preset.
  final GlassButtonSize size;

  /// Optional tooltip message.
  final String? tooltip;

  /// Optional accessibility semantic label (defaults to [label]).
  final String? semanticLabel;

  /// Creates a [GlassPillButton].
  const GlassPillButton({
    super.key,
    required this.label,
    this.leadingIcon,
    this.onPressed,
    this.variant = GlassButtonVariant.normal,
    this.size = GlassButtonSize.medium,
    this.tooltip,
    this.semanticLabel,
  });

  @override
  State<GlassPillButton> createState() => _GlassPillButtonState();
}

class _GlassPillButtonState extends State<GlassPillButton> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  bool get _isEnabled => widget.onPressed != null;

  Color _resolveFillColor(GlassQuality quality) {
    if (quality == GlassQuality.off) {
      return const Color(0xFF282733);
    }

    switch (widget.variant) {
      case GlassButtonVariant.primary:
      case GlassButtonVariant.selected:
        if (_isPressed) {
          return const Color(0x3DD3C9EA);
        }
        if (_isHovered) {
          return const Color(0x4DD3C9EA);
        }
        return AppColors.accentFill;
      case GlassButtonVariant.normal:
        if (_isPressed) {
          return const Color(0x0DFFFFFF);
        }
        if (_isHovered) {
          return const Color(0x1CFFFFFF);
        }
        return AppColors.fillControl;
    }
  }

  Border _resolveBorder() {
    if (_isFocused) {
      return Border.all(color: AppColors.accent, width: 2.0);
    }
    if (widget.variant == GlassButtonVariant.primary) {
      return Border.all(color: const Color(0x73D3C9EA), width: 1.0);
    }
    return Border.all(color: AppColors.border, width: 1.0);
  }

  Color _resolveContentColor() {
    switch (widget.variant) {
      case GlassButtonVariant.primary:
        return AppColors.text;
      case GlassButtonVariant.selected:
        return AppColors.accent;
      case GlassButtonVariant.normal:
        return AppColors.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final quality = GlassScope.qualityOf(context);
    final isEnabled = _isEnabled;
    final fill = _resolveFillColor(quality);
    final border = _resolveBorder();
    final contentColor = _resolveContentColor();

    final horizontalPadding = switch (widget.size) {
      GlassButtonSize.small => AppSpacing.s12,
      GlassButtonSize.medium => AppSpacing.s16,
      GlassButtonSize.large => AppSpacing.s24,
    };

    final textStyle = switch (widget.size) {
      GlassButtonSize.small => AppTypography.caption.copyWith(color: contentColor),
      GlassButtonSize.medium => AppTypography.body.copyWith(
          color: contentColor,
          fontWeight: FontWeight.w500,
        ),
      GlassButtonSize.large => AppTypography.bodyStrong.copyWith(color: contentColor),
    };

    Widget button = FocusableActionDetector(
      enabled: isEnabled,
      onShowHoverHighlight: (v) {
        if (isEnabled && _isHovered != v) {
          setState(() => _isHovered = v);
        }
      },
      onShowFocusHighlight: (v) {
        if (isEnabled && _isFocused != v) {
          setState(() => _isFocused = v);
        }
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPressed?.call(),
        ),
      },
      mouseCursor:
          isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel:
            isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: widget.size.dimension,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.pill),
            color: fill,
            border: border,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.leadingIcon != null) ...[
                Icon(
                  widget.leadingIcon,
                  size: widget.size.iconSize,
                  color: contentColor,
                ),
                const SizedBox(width: AppSpacing.s8),
              ],
              Text(widget.label, style: textStyle),
            ],
          ),
        ),
      ),
    );

    if (!isEnabled) {
      button = Opacity(opacity: 0.40, child: button);
    }

    final semanticText = widget.semanticLabel ?? widget.label;
    button = Semantics(
      label: semanticText,
      button: true,
      enabled: isEnabled,
      child: button,
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}
