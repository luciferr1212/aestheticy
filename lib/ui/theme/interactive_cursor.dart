import 'package:flutter/widgets.dart';

/// Central helpers and widgets for interactive hover cursors across Aestheticy.
abstract final class InteractiveCursor {
  /// Resolves the cursor for clickable controls: [SystemMouseCursors.click] when enabled,
  /// and [SystemMouseCursors.basic] when disabled.
  static MouseCursor clickable({bool enabled = true}) =>
      enabled ? SystemMouseCursors.click : SystemMouseCursors.basic;

  /// Resolves the cursor for drag handles: [SystemMouseCursors.grabbing] while active/dragging,
  /// [SystemMouseCursors.grab] when hovering, and [SystemMouseCursors.basic] when disabled.
  static MouseCursor dragHandle({bool isDragging = false, bool enabled = true}) {
    if (!enabled) return SystemMouseCursors.basic;
    return isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab;
  }
}

/// A wrapper widget for drag handles that shows [SystemMouseCursors.grab] on mouse hover
/// and [SystemMouseCursors.grabbing] while the pointer is held down / dragging.
class DragHandleCursor extends StatefulWidget {
  /// The draggable icon or handle content.
  final Widget child;

  /// Whether the drag handle is currently interactive.
  final bool enabled;

  /// Creates a [DragHandleCursor].
  const DragHandleCursor({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<DragHandleCursor> createState() => _DragHandleCursorState();
}

class _DragHandleCursorState extends State<DragHandleCursor> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final cursor = InteractiveCursor.dragHandle(
      isDragging: _isPressed,
      enabled: widget.enabled,
    );

    return MouseRegion(
      cursor: cursor,
      child: Listener(
        onPointerDown: widget.enabled ? (_) => setState(() => _isPressed = true) : null,
        onPointerUp: widget.enabled ? (_) => setState(() => _isPressed = false) : null,
        onPointerCancel: widget.enabled ? (_) => setState(() => _isPressed = false) : null,
        child: widget.child,
      ),
    );
  }
}
