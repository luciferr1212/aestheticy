import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_colors.dart';

/// Scrollbar wrapper that detects manual user scroll/drag gestures and auto-hides.
class LyricsUserScrollbar extends StatefulWidget {
  /// Scroll controller shared with the scrollable child.
  final ScrollController controller;

  /// Whether animations should be reduced to zero duration.
  final bool reduceMotion;

  /// Invoked when the user manually scrolls or drags.
  final VoidCallback onUserScroll;

  /// Scrollable subtree.
  final Widget child;

  /// Creates a [LyricsUserScrollbar].
  const LyricsUserScrollbar({
    super.key,
    required this.controller,
    required this.reduceMotion,
    required this.onUserScroll,
    required this.child,
  });

  @override
  State<LyricsUserScrollbar> createState() => _LyricsUserScrollbarState();
}

class _LyricsUserScrollbarState extends State<LyricsUserScrollbar> {
  Timer? _scrollbarHideTimer;
  bool _userScrollbarVisible = false;
  bool _isPointerDown = false;

  void _activateUserScrollbar() {
    _scrollbarHideTimer?.cancel();
    _scrollbarHideTimer = Timer(const Duration(seconds: 1), () {
      _scrollbarHideTimer = null;
      if (!mounted) return;
      setState(() {
        _userScrollbarVisible = false;
      });
    });
    if (!_userScrollbarVisible) {
      setState(() {
        _userScrollbarVisible = true;
      });
    }
  }

  @override
  void dispose() {
    _scrollbarHideTimer?.cancel();
    _scrollbarHideTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fadeDuration = widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _isPointerDown = true;
      },
      onPointerUp: (_) {
        _isPointerDown = false;
      },
      onPointerCancel: (_) {
        _isPointerDown = false;
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          widget.onUserScroll();
          _activateUserScrollbar();
        }
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: RawScrollbar(
          key: const Key('lyrics_user_scrollbar'),
          controller: widget.controller,
          thumbVisibility: _userScrollbarVisible,
          trackVisibility: false,
          thickness: 4.0,
          radius: const Radius.circular(2.0),
          thumbColor: AppColors.textMuted.withValues(alpha: 0.45),
          crossAxisMargin: 2.0,
          mainAxisMargin: 4.0,
          fadeDuration: fadeDuration,
          timeToFade: Duration.zero,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              final isDragScroll =
                  (notification is ScrollStartNotification &&
                          notification.dragDetails != null) ||
                      (notification is ScrollUpdateNotification &&
                          (notification.dragDetails != null ||
                              _isPointerDown)) ||
                      (notification is OverscrollNotification &&
                          (notification.dragDetails != null ||
                              _isPointerDown)) ||
                      (notification is UserScrollNotification &&
                          notification.direction != ScrollDirection.idle);

              if (isDragScroll) {
                widget.onUserScroll();
                _activateUserScrollbar();
                return false;
              }

              return !_userScrollbarVisible;
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
