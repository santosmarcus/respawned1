import 'package:flutter/material.dart';

/// App-wide: a tap outside the text field being typed in takes its focus
/// away (and hides the keyboard).
///
/// Without this, picking from a dropdown, a radio row or a chip left the
/// last text field focused; when the dropdown's menu closed, Flutter gave
/// focus back to that field, which reopened the keyboard and scrolled the
/// form up to it. A Listener sees every pointer down without taking part
/// in the gesture, so the tapped control still works as before.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  void _onPointerDown(PointerDownEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (focus == null || context == null) return;
    // Only text input: leave keyboard-free focus (buttons, lists) alone.
    if (context.findAncestorWidgetOfExactType<EditableText>() == null &&
        context.widget is! EditableText) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.contains(event.position)) focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(behavior: HitTestBehavior.translucent, onPointerDown: _onPointerDown, child: child);
  }
}
