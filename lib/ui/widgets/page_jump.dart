import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The page counter, which is also the way to a page by its number.
///
/// Walking to page thirty of a scan a page at a time is a long walk, and on a
/// phone there is nothing else to walk with: no keyboard, and a scrollbar too
/// short to aim with.
class PageJump extends StatelessWidget {
  const PageJump({
    super.key,
    required this.label,
    required this.current,
    required this.count,
    required this.onGo,
    this.width = 82,
    this.fontSize = 12,
  });

  /// What the counter reads, in the viewer's own wording.
  final String label;

  /// The page shown now and how many there are, as the reader counts them:
  /// from one.
  final int current, count;

  /// Called with a page number counted from one.
  final ValueChanged<int> onGo;

  final double width;
  final double fontSize;

  Future<void> _ask(BuildContext context) async {
    if (count < 2) return;
    final page = await showDialog<int>(
      context: context,
      builder: (context) => _PageJumpDialog(current: current, count: count),
    );
    if (page != null) onGo(page);
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: count < 2 ? label : 'Sayfaya git',
    child: InkWell(
      onTap: count < 2 ? null : () => _ask(context),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: 32,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            semanticsLabel: 'Sayfa $current / $count',
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  );
}

class _PageJumpDialog extends StatefulWidget {
  const _PageJumpDialog({required this.current, required this.count});
  final int current, count;

  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final _field = TextEditingController(text: '${widget.current}');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _go() {
    final page = int.tryParse(_field.text.trim());
    if (page == null || page < 1 || page > widget.count) return;
    Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sayfaya git'),
    content: TextField(
      controller: _field,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => _go(),
      decoration: InputDecoration(
        labelText: 'Sayfa numarası',
        helperText: '1 – ${widget.count}',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      FilledButton(onPressed: _go, child: const Text('Git')),
    ],
  );
}
