import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// GTK can report the Turkish İ/ı symbol instead of the Latin shortcut key.
/// Preserve logical keys for all other layouts, including non-QWERTY layouts.
class EditorShortcut implements ShortcutActivator {
  const EditorShortcut(
    LogicalKeyboardKey key, {
    required this.control,
    required this.meta,
    required this.shift,
  }) : _key = key;
  final LogicalKeyboardKey _key;
  final bool control, meta, shift;
  SingleActivator get _binding => SingleActivator(
    _key,
    control: control,
    meta: meta,
    shift: shift,
    includeRepeats: false,
  );
  @override
  Iterable<LogicalKeyboardKey> get triggers => [
    _key,
    if (_key == LogicalKeyboardKey.keyI) ...[
      const LogicalKeyboardKey(0x130),
      const LogicalKeyboardKey(0x131),
    ],
  ];
  @override
  String debugDescribeKeys() => _binding.debugDescribeKeys();
  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (_binding.accepts(event, state)) return true;
    if (event is! KeyDownEvent ||
        _key != LogicalKeyboardKey.keyI ||
        ![0x130, 0x131].contains(event.logicalKey.keyId)) {
      return false;
    }
    return _binding.accepts(
      KeyDownEvent(
        physicalKey: event.physicalKey,
        logicalKey: _key,
        timeStamp: event.timeStamp,
      ),
      state,
    );
  }
}
