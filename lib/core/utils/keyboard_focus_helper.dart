import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Returns true when the current primary focus is inside an editable text field.
bool isEditableTextFocused() {
  final primaryFocus = FocusManager.instance.primaryFocus;
  final ctx = primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Handles `LogicalKeyboardKey.numpadAdd` when no text field is focused.
KeyEventResult handleNumpadAddShortcut(
  KeyEvent event,
  VoidCallback onAdd,
) {
  if (event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.numpadAdd &&
      !HardwareKeyboard.instance.isControlPressed &&
      !HardwareKeyboard.instance.isAltPressed &&
      !isEditableTextFocused()) {
    onAdd();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

