import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../library/artist_splitter.dart';
import '../../library/models.dart';
import '../../library/text_normalizer.dart';
import '../artist_names/artist_name_scope.dart';
import '../l10n/app_strings.dart';
import '../settings/app_shortcuts.dart';
import '../shell/app_navigator.dart';
import '../theme/app_colors.dart';

/// Interactive link for track metadata (artist, album) with subtle underline on hover,
/// pointer cursor, keyboard focus, and accessibility semantics.
class MetadataLink extends StatefulWidget {
  /// The displayed text string.
  final String text;

  /// Base text style.
  final TextStyle style;

  /// Action when tapped or activated. If null, renders as non-interactive plain text.
  final VoidCallback? onTap;

  /// Accessibility semantic label.
  final String? semanticLabel;

  /// Optional text direction (defaults to detected direction).
  final TextDirection? textDirection;

  /// Text alignment.
  final TextAlign textAlign;

  /// Text overflow handling.
  final TextOverflow overflow;

  /// Maximum line count.
  final int maxLines;

  /// Whether reduce motion is enabled (skips underline fade duration).
  final bool reduceMotion;

  /// Creates a [MetadataLink].
  const MetadataLink({
    super.key,
    required this.text,
    required this.style,
    this.onTap,
    this.semanticLabel,
    this.textDirection,
    this.textAlign = TextAlign.start,
    this.overflow = TextOverflow.ellipsis,
    this.maxLines = 1,
    this.reduceMotion = false,
  });

  @override
  State<MetadataLink> createState() => _MetadataLinkState();
}

class _MetadataLinkState extends State<MetadataLink> {
  bool _isHovered = false;
  bool _isFocused = false;

  void _handleTap() {
    widget.onTap?.call();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onTap == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent && (isEnterKey(event) || isSpaceKey(event))) {
      _handleTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDir = widget.textDirection ?? textDirectionFor(widget.text);

    if (widget.onTap == null) {
      return Text(
        widget.text,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
        textDirection: effectiveDir,
        style: widget.style,
      );
    }

    final active = _isHovered || _isFocused;
    final underlineColor = active
        ? (widget.style.color?.withValues(alpha: 0.6) ??
            AppColors.textSecondary.withValues(alpha: 0.6))
        : Colors.transparent;

    final linkStyle = widget.style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: underlineColor,
    );

    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: _handleKeyEvent,
      child: Semantics(
        button: true,
        label: widget.semanticLabel ?? widget.text,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: AnimatedDefaultTextStyle(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              style: linkStyle,
              child: Text(
                widget.text,
                maxLines: widget.maxLines,
                overflow: widget.overflow,
                textAlign: widget.textAlign,
                textDirection: effectiveDir,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper functions for navigating to artist and album pages from metadata links.
abstract final class MetadataNavHelper {
  /// Opens album detail from track metadata.
  static void openAlbum({
    required AppNavigator navigator,
    required String albumTitle,
    bool leaveFullScreenFirst = false,
  }) {
    final trimmed = albumTitle.trim();
    if (trimmed.isEmpty) return;
    if (leaveFullScreenFirst) {
      navigator.goBack();
    }
    navigator.openAlbumDetail(trimmed);
  }

  /// Opens artist detail or displays multi-artist choice menu.
  static Future<void> openArtist({
    required BuildContext context,
    required AppNavigator navigator,
    required String rawArtist,
    bool leaveFullScreenFirst = false,
  }) async {
    final trimmed = rawArtist.trim();
    if (trimmed.isEmpty) return;

    final splits = ArtistSplitter.split(trimmed);
    if (splits.isEmpty) {
      final key = TextNormalizer.normalize(trimmed);
      if (leaveFullScreenFirst) {
        navigator.goBack();
      }
      navigator.openArtistDetail(
        key,
        artist: ArtistSummary(key: key, name: trimmed, albumCount: 0, trackCount: 0),
      );
      return;
    }

    if (splits.length == 1) {
      final single = splits.first;
      if (leaveFullScreenFirst) {
        navigator.goBack();
      }
      navigator.openArtistDetail(
        single.key,
        artist: ArtistSummary(
          key: single.key,
          name: single.name,
          albumCount: 0,
          trackCount: 0,
        ),
      );
      return;
    }

    // Multi-artist collaboration: show picker menu
    final renderBox = context.findRenderObject() as RenderBox?;
    final rect = renderBox != null
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : Rect.zero;

    final selected = await showMenu<SplitArtist>(
      context: context,
      position: RelativeRect.fromRect(
        rect,
        Offset.zero & MediaQuery.sizeOf(context),
      ),
      items: splits.map((sa) {
        final displayName = context.displayArtist(sa.name);
        return PopupMenuItem<SplitArtist>(
          value: sa,
          child: Text(
            displayName,
            textDirection: textDirectionFor(displayName),
          ),
        );
      }).toList(),
    );

    if (selected != null) {
      if (leaveFullScreenFirst) {
        navigator.goBack();
      }
      navigator.openArtistDetail(
        selected.key,
        artist: ArtistSummary(
          key: selected.key,
          name: selected.name,
          albumCount: 0,
          trackCount: 0,
        ),
      );
    }
  }
}
