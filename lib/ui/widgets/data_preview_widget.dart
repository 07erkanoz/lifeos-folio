import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class DataPreviewWidget extends StatefulWidget {
  final String filePath;
  const DataPreviewWidget({super.key, required this.filePath});
  @override
  State<DataPreviewWidget> createState() => _DataPreviewWidgetState();
}

class _DataPreviewWidgetState extends State<DataPreviewWidget> {
  late final Future<String> _content = _load();
  bool _wrap = false;
  Future<String> _load() async {
    final file = File(widget.filePath);
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('Metin önizlemesi en fazla 8 MB dosya açar.');
    }
    var text = await file.readAsString();
    if (widget.filePath.toLowerCase().endsWith('.json')) {
      try {
        text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
      } catch (_) {}
    }
    return text;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Metin önizlemesi', overflow: TextOverflow.ellipsis),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _wrap = !_wrap),
            icon: Icon(_wrap ? Icons.wrap_text : Icons.subject),
            label: Text(_wrap ? 'Satırları aç' : 'Satırları kaydır'),
          ),
        ],
      ),
      Expanded(
        child: FutureBuilder<String>(
          future: _content,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Dosya açılamadı: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final content = SelectableText(
              snapshot.data!,
              style: const TextStyle(
                fontFamily: 'LiberationMono',
                fontSize: 13,
              ),
            );
            return Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _wrap
                    ? content
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: content,
                      ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
