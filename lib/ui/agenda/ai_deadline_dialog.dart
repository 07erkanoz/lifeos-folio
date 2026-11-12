import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_deadlines.dart';
import '../../services/legal/deadlines/mahkeme_kategori.dart';
import '../ai/ai_dialogs.dart';
import 'agenda_page.dart' show AgendaColors;

/// What the lawyer approved of an AI program's suggestions, and which
/// program and model made them ("Claude · haiku").
typedef AiDeadlinesApproved = ({
  List<AiDeadlineSuggestion> chosen,
  String model,
});

/// A notice's times and tasks drawn out by the lawyer's AI program at the
/// light tier, shown with the article and the sentence each rests on and
/// the last day Folio's engine reckons; none is kept until the lawyer
/// ticks it and approves. Asked only when the lawyer presses the button.
Future<AiDeadlinesApproved?> askAiDeadlines(
  BuildContext context, {
  required String text,
  required DateTime served,
  required MahkemeKategorisi court,
  String unit = '',
  String subject = '',
  String side = '',
  List<String> known = const [],
  Set<String> knownRules = const {},
}) async {
  if (!await askAiConsent(context)) return null;
  final settings = await AiSettings.load();
  final found = await AiAssistant.statuses();
  var provider = settings.provider;
  if (provider == null ||
      !found.any((s) => s.provider == provider && s.usable)) {
    provider = found.where((s) => s.usable).map((s) => s.provider).firstOrNull;
  }
  if (!context.mounted) return null;
  if (provider == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Kullanılabilir bir yapay zekâ programı yok. Ayarlar › Yapay '
          'zekâ’dan bir program bağlayın.',
        ),
      ),
    );
    return null;
  }
  return showDialog<AiDeadlinesApproved>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AiDeadlinesDialog(
      provider: provider!,
      model: '${provider.label} · ${settings.modelFor(provider, AiTier.light)}',
      text: text,
      served: served,
      court: court,
      unit: unit,
      subject: subject,
      side: side,
      known: known,
      knownRules: knownRules,
    ),
  );
}

class _AiDeadlinesDialog extends StatefulWidget {
  const _AiDeadlinesDialog({
    required this.provider,
    required this.model,
    required this.text,
    required this.served,
    required this.court,
    required this.unit,
    required this.subject,
    required this.side,
    required this.known,
    required this.knownRules,
  });

  final AiProvider provider;
  final String model, text, unit, subject, side;
  final List<String> known;
  final Set<String> knownRules;
  final DateTime served;
  final MahkemeKategorisi court;

  @override
  State<_AiDeadlinesDialog> createState() => _AiDeadlinesDialogState();
}

class _AiDeadlinesDialogState extends State<_AiDeadlinesDialog> {
  final _cancel = Completer<void>();
  final _began = DateTime.now();
  List<AiDeadlineSuggestion>? _found;
  final _chosen = <int>{};
  String? _failed;
  String _step = '';
  int? _seconds;

  @override
  void initState() {
    super.initState();
    unawaited(_ask());
  }

  @override
  void dispose() {
    if (!_cancel.isCompleted) _cancel.complete();
    super.dispose();
  }

  Future<void> _ask() async {
    try {
      final got = await AiDeadlines.ask(
        widget.provider,
        text: widget.text,
        served: widget.served,
        unit: widget.unit,
        subject: widget.subject,
        side: widget.side,
        known: widget.known,
        knownRules: widget.knownRules,
        court: widget.court,
        cancel: _cancel.future,
        onEvent: (e) {
          if (e is AiStep && mounted) setState(() => _step = e.label);
        },
      );
      if (!mounted) return;
      setState(() {
        _found = got;
        _seconds = DateTime.now().difference(_began).inSeconds;
      });
    } on AiFailure catch (e) {
      if (mounted) setState(() => _failed = e.message);
    }
  }

  static String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Widget _suggestion(int i, AiDeadlineSuggestion s) {
    final day = s.lastDay(widget.served, widget.court);
    final muted = TextStyle(fontSize: 12, color: AgendaColors.muted);
    return CheckboxListTile(
      key: ValueKey('ai-deadline-$i'),
      value: _chosen.contains(i),
      onChanged: (v) =>
          setState(() => v == true ? _chosen.add(i) : _chosen.remove(i)),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(
        [
          s.what,
          if (!s.isTask)
            '${s.rule.sureMetni}${s.article.isEmpty ? '' : ' · ${s.article}'}',
          if (s.isTask) 'süre yazmıyor',
        ].join(' · '),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.quote.isNotEmpty)
            Text(
              '“${s.quote}”',
              style: muted.copyWith(fontStyle: FontStyle.italic),
            ),
          if (day != null)
            Text(
              'Son gün ${_day(day.etkiliSonGun)} · başlangıç '
              '${s.startEvent == 'teblig' ? 'tebliğ' : s.startEvent} '
              '${_day(day.baslangicTarihi)} · son günü Folio hesapladı'
              '${day.tatilBelirsiz ? ' · adli tatile denk geliyor, denetleyin' : ''}',
              style: muted,
            ),
          if (s.until != null)
            Text(
              'Son gün ${_day(s.until!)} (tebligatta yazan tarih)',
              style: muted,
            ),
          if (s.warning.isNotEmpty)
            Text(
              s.warning,
              style: muted.copyWith(color: const Color(0xFFB45309)),
            ),
          if (s.others)
            Text(
              s.whose == 'karsi'
                  ? 'Karşı tarafın işi; müvekkilinizi ilgilendirmiyorsa eklemeyin.'
                  : 'Mahkemenin işi.',
              style: muted,
            )
          else if (s.whose == 'belirsiz')
            Text('Kimin işi olduğu belli değil; denetleyin.', style: muted),
          if (s.isTask) Text('Ajandaya görev olarak eklenir.', style: muted),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return AlertDialog(
      title: Text(
        found == null
            ? 'Yapay zekâ tebligatı okuyor'
            : 'Yapay zekânın önerdikleri · ${widget.model}'
                  '${_seconds == null ? '' : ' · $_seconds sn'}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 560,
        child: _failed != null
            ? Text(_failed!)
            : found == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(
                    _step.isEmpty ? '${widget.model} çalışıyor…' : _step,
                    style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tebligatın metni ve ekleri ${widget.provider.company} '
                      'şirketine gönderildi. Seçmediğiniz hiçbir öneri ajandaya '
                      'girmez.',
                      style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                    ),
                    const SizedBox(height: 8),
                    if (found.isEmpty)
                      const Text(
                        'Yapay zekâ bu tebligatta süre ya da iş bulmadı.',
                      )
                    else
                      for (final (i, s) in found.indexed) _suggestion(i, s),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(found == null && _failed == null ? 'Durdur' : 'Vazgeç'),
        ),
        if (found != null && found.isNotEmpty)
          FilledButton(
            key: const ValueKey('ai-deadlines-add'),
            onPressed: _chosen.isEmpty
                ? null
                : () => Navigator.pop<AiDeadlinesApproved>(context, (
                    chosen: [
                      for (final i in _chosen.toList()..sort()) found[i],
                    ],
                    model: widget.model,
                  )),
            child: const Text('Seçilenleri ajandaya ekle'),
          ),
      ],
    );
  }
}
