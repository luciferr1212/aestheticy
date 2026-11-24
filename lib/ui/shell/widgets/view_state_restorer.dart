import 'package:flutter/material.dart';

import '../app_navigator.dart';

/// Captures and restores vertical scroll offset across navigation stack entries.
class ViewStateRestorer extends StatefulWidget {
  /// Navigation history entry whose viewState holds `scrollOffset`.
  final NavEntry entry;

  /// Application navigation coordinator.
  final AppNavigator navigator;

  /// Destination view subtree.
  final Widget child;

  /// Creates a [ViewStateRestorer].
  const ViewStateRestorer({
    super.key,
    required this.entry,
    required this.navigator,
    required this.child,
  });

  @override
  State<ViewStateRestorer> createState() => _ViewStateRestorerState();
}

class _ViewStateRestorerState extends State<ViewStateRestorer> {
  late ScrollController _scrollController;
  bool _restored = false;

  bool get _isActive => widget.navigator.currentEntry.id == widget.entry.id;

  @override
  void initState() {
    super.initState();
    final savedOffset =
        (widget.entry.viewState['scrollOffset'] as num?)?.toDouble() ?? 0.0;
    _scrollController = ScrollController(initialScrollOffset: savedOffset);
    _restored = savedOffset == 0.0;
    if (_isActive) {
      widget.navigator.onCaptureViewState = _captureOffset;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isActive) {
        widget.navigator.onCaptureViewState = _captureOffset;
        _restoreScrollIfNeeded();
      }
    });
  }

  void _captureOffset(Map<String, Object?> state) {
    if (_isActive && _scrollController.hasClients) {
      state['scrollOffset'] = _scrollController.offset;
    }
  }

  void _restoreScrollIfNeeded() {
    if (_restored || !_isActive) return;
    final savedOffset =
        (widget.entry.viewState['scrollOffset'] as num?)?.toDouble() ?? 0.0;
    if (savedOffset > 0 && _scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        _scrollController.jumpTo(savedOffset.clamp(0.0, maxScroll));
        _restored = true;
      }
    } else if (savedOffset == 0.0) {
      _restored = true;
    }
  }

  @override
  void didUpdateWidget(ViewStateRestorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      final savedOffset =
          (widget.entry.viewState['scrollOffset'] as num?)?.toDouble() ?? 0.0;
      _restored = savedOffset == 0.0;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(savedOffset);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isActive) {
          widget.navigator.onCaptureViewState = _captureOffset;
          _restoreScrollIfNeeded();
        }
      });
    }
  }

  @override
  void dispose() {
    if (widget.navigator.onCaptureViewState == _captureOffset) {
      widget.navigator.onCaptureViewState = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _scrollController,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notif) {
          if (!_isActive) return false;
          if (notif.depth == 0) {
            if (!_restored && notif.metrics.maxScrollExtent > 0) {
              final savedOffset =
                  (widget.entry.viewState['scrollOffset'] as num?)?.toDouble() ??
                      0.0;
              if (savedOffset > 0 && _scrollController.hasClients) {
                _scrollController.jumpTo(
                  savedOffset.clamp(0.0, notif.metrics.maxScrollExtent),
                );
              }
              _restored = true;
            } else if (_restored) {
              widget.entry.viewState['scrollOffset'] = notif.metrics.pixels;
            }
          }
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
