import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../services/clients/client.dart';
import '../../services/clients/client_accounts.dart';
import '../../services/clients/client_messages.dart';
import '../../services/clients/client_statement_pdf.dart';
import '../../services/clients/fee_reminders.dart';
import '../../services/platform/app_directories.dart';
import '../../services/platform/file_actions.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_hearing.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart' show titleName;
import '../widgets/notice.dart';

/// What the day asks to be told to clients who wish it: a hearing within
/// three days, an instalment within three days or late; none told before.
List<DueMessage> dueMessages(
  PortalDatabase db,
  DateTime now,
  List<ClientEntry> entries,
) {
  final today = DateTime(now.year, now.month, now.day);
  final told = {
    for (final r in db.allClientRecords())
      if (r.kind == ClientRecordKind.message && !r.removed) r.text('konu'),
  };
  final out = <DueMessage>[];
  final asked = <String, Client>{};
  for (final e in entries) {
    final c = e.client;
    if (c == null || !c.messages || c.removed) continue;
    if (phoneDigits(c.phone).isEmpty && c.email.trim().isEmpty) continue;
    for (final id in {...e.ids, c.id}) {
      asked[id] = c;
    }
    for (final x in e.cases) {
      for (final h in db.hearings(
        caseKey: x.caseKey,
        from: now,
        to: today.add(const Duration(days: 4)),
      )) {
        final about = 'durusma:${h.key}';
        if (told.contains(about)) continue;
        out.add(
          DueMessage(
            client: c,
            kind: MessageKind.hearing,
            at: h.at,
            about: about,
            caseKey: h.caseKey,
            court: h.court,
            daysLeft: DateTime(
              h.at.year,
              h.at.month,
              h.at.day,
            ).difference(today).inDays,
          ),
        );
      }
    }
  }
  for (final t in FeeReminders.open(db, now)) {
    final c = asked[t.client.id];
    if (c == null || t.daysLeft > 3) continue;
    final about =
        'taksit:${t.caseKey}:${t.due.toIso8601String().substring(0, 10)}';
    if (told.contains(about)) continue;
    out.add(
      DueMessage(
        client: c,
        kind: MessageKind.instalment,
        at: t.due,
        about: about,
        caseKey: t.caseKey,
        amount: t.amount,
        daysLeft: t.daysLeft,
      ),
    );
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}

/// A message to a client written, read over and opened in the lawyer's
/// own WhatsApp, SMS or e-mail program; the record of it returned once
/// opened, null when backed out.
class ClientMessageDialog extends StatefulWidget {
  const ClientMessageDialog({
    super.key,
    required this.client,
    required this.cases,
    required this.database,
    required this.lawyer,
    this.person = '',
    this.ids = const [],
    this.seesMoney = true,
    this.due,
  });

  final Client client;

  /// The client's cases and the other cards of theirs.
  final List<({String caseKey, String role})> cases;
  final List<String> ids;
  final PortalDatabase database;
  final String lawyer, person;
  final bool seesMoney;

  /// The day's message this was opened for, when it was.
  final DueMessage? due;

  @override
  State<ClientMessageDialog> createState() => _ClientMessageDialogState();
}

class _ClientMessageDialogState extends State<ClientMessageDialog> {
  late MessageChannel _channel = !_hasPhone && _hasEmail
      ? MessageChannel.email
      : MessageChannel.whatsapp;
  late MessageKind _kind = widget.due?.kind ?? MessageKind.hearing;
  late String _case =
      widget.due?.caseKey ??
      (widget.cases.isEmpty ? '' : widget.cases.first.caseKey);
  final _text = TextEditingController();
  String _subject = '';
  bool _statement = false;
  bool _busy = false;

  PortalDatabase get _db => widget.database;
  bool get _hasPhone => phoneDigits(widget.client.phone).isNotEmpty;
  bool get _hasEmail => widget.client.email.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.due == null) _firstChoice();
    _write();
  }

  /// Opened by the lawyer, not for a message due: the case with the
  /// nearest hearing, and a hearing's reminder for it; with none to come,
  /// a message of their own.
  void _firstChoice() {
    final now = DateTime.now();
    final next = [
      for (final c in widget.cases)
        ..._db.hearings(
          caseKey: c.caseKey,
          from: now,
          to: now.add(const Duration(days: 400)),
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final first = next.firstOrNull;
    if (first == null) {
      _kind = MessageKind.free;
      return;
    }
    _case = first.caseKey;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<ClientRecord> get _money => [
    for (final r in _db.clientRecords(widget.client.id, also: widget.ids))
      if (r.kind.money) r,
  ];

  /// The words for the kind and case chosen, from what is kept.
  void _write() {
    final now = DateTime.now();
    final kase = _db.caseOf(_case);
    var court = kase?.court ?? '';
    DateTime? at;
    var amount = 0;
    var result = '';
    switch (_kind) {
      case MessageKind.hearing:
        final next = widget.due?.kind == MessageKind.hearing
            ? null
            : _db
                  .hearings(
                    caseKey: _case,
                    from: now,
                    to: now.add(const Duration(days: 400)),
                  )
                  .firstOrNull;
        at = widget.due?.kind == MessageKind.hearing
            ? widget.due!.at
            : next?.at;
        if (widget.due?.court.isNotEmpty ?? false) court = widget.due!.court;
      case MessageKind.result:
        final List<PortalHearing> past = _db.hearings(
          caseKey: _case,
          from: DateTime(2000),
          to: now,
        )..sort((a, b) => b.at.compareTo(a.at));
        at = past.firstOrNull?.at;
        result = past.firstOrNull?.result?.value ?? '';
      case MessageKind.instalment:
        final due = widget.due;
        if (due != null && due.kind == MessageKind.instalment) {
          at = due.at;
          amount = due.amount;
        } else {
          final plan = caseAccounts(_money)[_case]?.instalments(now) ?? [];
          final next = plan.where((t) => !t.paid).firstOrNull;
          at = next?.due;
          amount = next?.amount ?? 0;
        }
      case MessageKind.receipt:
        final paid = [
          for (final r in _money)
            if (r.kind == ClientRecordKind.movement &&
                r.movement == MovementKind.feePaid &&
                (_case.isEmpty || r.text('dosya') == _case))
              r,
        ]..sort((a, b) => b.at.compareTo(a.at));
        at = paid.firstOrNull?.at;
        amount = paid.firstOrNull?.amount ?? 0;
      case MessageKind.free:
        break;
    }
    final m = messageText(
      _kind,
      client: titleName(widget.client.name),
      lawyer: widget.lawyer,
      court: court,
      at: at,
      amount: amount,
      result: result,
    );
    _subject = m.subject;
    _text.text = m.body;
  }

  Future<bool> _open() async {
    final links = messageLinks(
      _channel,
      phone: widget.client.phone,
      email: widget.client.email,
      subject: _subject,
      text: _text.text,
    );
    for (final (i, uri) in links.indexed) {
      try {
        // The computer's own WhatsApp only where one takes the link.
        if (i < links.length - 1 && !await canLaunchUrl(uri)) continue;
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// The client's statement written out, and given to the system's share
  /// sheet (a phone, Windows, a Mac) or shown in its folder (Linux), to
  /// go with the message by the lawyer's hand.
  Future<void> _shareStatement() async {
    final bytes = await clientStatementPdf(
      client: widget.client,
      records: _money,
      cases: {
        for (final c in widget.cases)
          c.caseKey:
              '${_db.caseOf(c.caseKey)?.number ?? c.caseKey} · '
              '${_db.caseOf(c.caseKey)?.court ?? ''}',
      },
      lawyer: widget.lawyer,
    );
    final dir = Directory(
      p.join((await folioSupportDirectory()).path, 'paylasim'),
    );
    await dir.create(recursive: true);
    final file = File(
      p.join(dir.path, 'Hesap dökümü ${titleName(widget.client.name)}.pdf'),
    );
    await file.writeAsBytes(bytes, flush: true);
    await FileActions.invoke(
      Platform.isLinux ? 'showFolder' : 'share',
      file.path,
    );
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final opened = await _open();
    if (!mounted) return;
    if (!opened) {
      setState(() => _busy = false);
      showNotice(
        context,
        '${_channel.label} açılamadı.',
        detail: 'Metni kopyalayıp kendiniz yapıştırabilirsiniz.',
        kind: NoticeKind.error,
      );
      return;
    }
    if (_statement) {
      try {
        await _shareStatement();
      } catch (e) {
        if (mounted) {
          showNotice(
            context,
            'Hesap dökümü paylaşılamadı: $e',
            kind: NoticeKind.error,
          );
        }
      }
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      messageRecord(
        clientId: widget.client.id,
        channel: _channel,
        kind: _kind,
        text: _text.text,
        lawyer: widget.lawyer,
        caseKey: _case,
        about: widget.due?.about ?? '',
        person: widget.person,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsCase = _kind != MessageKind.free && widget.cases.length > 1;
    final verb = switch (_channel) {
      MessageChannel.whatsapp => 'WhatsApp\'ta aç',
      MessageChannel.sms => 'SMS\'te aç',
      MessageChannel.email => 'E-postada aç',
    };
    return AlertDialog(
      title: Text('Mesaj · ${titleName(widget.client.name)}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<MessageChannel>(
                key: const ValueKey('message-channel'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: MessageChannel.whatsapp,
                    label: const Text('WhatsApp'),
                  ),
                  ButtonSegment(
                    value: MessageChannel.sms,
                    label: const Text('SMS'),
                  ),
                  ButtonSegment(
                    value: MessageChannel.email,
                    label: const Text('E-posta'),
                  ),
                ],
                selected: {_channel},
                onSelectionChanged: (v) => setState(() => _channel = v.first),
              ),
              if (_channel == MessageChannel.email ? !_hasEmail : !_hasPhone)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _channel == MessageChannel.email
                        ? 'Kartta e-posta adresi yok: alıcıyı e-posta '
                              'programında siz yazarsınız.'
                        : 'Kartta telefon yok: kişiyi '
                              '${_channel == MessageChannel.sms ? 'mesajlar uygulamasında' : 'WhatsApp\'ta'} '
                              'siz seçersiniz.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AgendaColors.muted,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in MessageKind.values)
                    if (widget.seesMoney ||
                        (k != MessageKind.instalment &&
                            k != MessageKind.receipt))
                      ChoiceChip(
                        key: ValueKey('message-kind-${k.name}'),
                        label: Text(k.label),
                        selected: _kind == k,
                        onSelected: (_) => setState(() {
                          _kind = k;
                          _write();
                        }),
                      ),
                ],
              ),
              if (needsCase) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: widget.cases.any((c) => c.caseKey == _case)
                      ? _case
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Dosya',
                    isDense: true,
                  ),
                  items: [
                    for (final c in widget.cases)
                      DropdownMenuItem(
                        value: c.caseKey,
                        child: Text(
                          '${_db.caseOf(c.caseKey)?.number ?? c.caseKey} · '
                          '${_db.caseOf(c.caseKey)?.court ?? ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _case = v ?? _case;
                    _write();
                  }),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('message-text'),
                controller: _text,
                minLines: 5,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText:
                      _channel == MessageChannel.email && _subject.isNotEmpty
                      ? 'Konu: $_subject'
                      : 'Mesaj',
                  alignLabelWithHint: true,
                ),
              ),
              if (widget.seesMoney)
                CheckboxListTile(
                  key: const ValueKey('message-statement'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _statement,
                  onChanged: (v) => setState(() => _statement = v ?? false),
                  title: const Text('Hesap dökümünü de gönder'),
                  subtitle: Text(
                    Platform.isLinux
                        ? 'PDF klasörde açılır; sohbete sürüklersiniz.'
                        : 'PDF paylaşma menüsüyle gönderilir.',
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Mesaj ${_channel.label} programınızda yazılmış olarak açılır; '
                'gönder düğmesine siz basarsınız. Dosya numarası ve karşı '
                'taraf yazılmaz.',
                style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          key: const ValueKey('message-copy'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _text.text));
            if (context.mounted) showNotice(context, 'Metin kopyalandı.');
          },
          child: const Text('Metni kopyala'),
        ),
        FilledButton(
          key: const ValueKey('message-send'),
          style: _channel == MessageChannel.whatsapp
              ? FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855))
              : null,
          onPressed: _busy ? null : _send,
          child: Text(verb),
        ),
      ],
    );
  }
}
