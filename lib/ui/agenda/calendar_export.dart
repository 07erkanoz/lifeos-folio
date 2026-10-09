import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/platform/app_directories.dart';
import '../../services/platform/file_actions.dart';
import '../../services/portal/agenda_ics.dart';
import '../../services/portal/portal_database.dart';
import '../widgets/notice.dart';
import 'agenda_page.dart' show AgendaColors;

/// [ics] handed to the device's calendar: a phone's calendar app takes it
/// at once, a computer's default calendar program opens it.
Future<void> openInCalendar(
  BuildContext context,
  String ics,
  String name,
) async {
  try {
    final dir = Directory(
      p.join((await folioSupportDirectory()).path, 'paylasim'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '$name.ics'));
    await file.writeAsString(ics, flush: true);
    await FileActions.invoke('openDefault', file.path);
  } catch (e) {
    if (context.mounted) {
      showNotice(
        context,
        'Takvim açılamadı: $e',
        detail:
            'Ajandadaki "Takvime aktar" ile dosyayı kaydedip '
            'takviminize içe aktarabilirsiniz.',
        kind: NoticeKind.error,
      );
    }
  }
}

/// The agenda written out for Google, Outlook or Apple's calendar: what,
/// how far ahead, with which alarms, and whether the clients are named.
class CalendarExportDialog extends StatefulWidget {
  const CalendarExportDialog({super.key, required this.database, this.lawyer});
  final PortalDatabase database;
  final String? lawyer;

  @override
  State<CalendarExportDialog> createState() => _CalendarExportDialogState();
}

class _CalendarExportDialogState extends State<CalendarExportDialog> {
  bool _hearings = true, _deadlines = true, _tasks = false;
  bool _names = false;
  int _months = 6;
  final _alarms = <int>{1440, 120};
  bool _busy = false;

  List<CalendarEvent> _events({bool? hearings, bool? deadlines, bool? tasks}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return agendaEvents(
      widget.database,
      from: today,
      to: DateTime(today.year, today.month + _months, today.day),
      hearings: hearings ?? _hearings,
      deadlines: deadlines ?? _deadlines,
      tasks: tasks ?? _tasks,
      names: _names,
      lawyer: widget.lawyer,
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final events = _events();
    final ics = calendarFile(events, alarms: _alarms.toList()..sort());
    const name = 'Folio ajanda';
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await openInCalendar(context, ics, name);
      } else {
        final bytes = Uint8List.fromList(utf8.encode(ics));
        final path = await FilePicker.saveFile(
          fileName: '$name.ics',
          type: FileType.custom,
          allowedExtensions: const ['ics'],
          bytes: bytes,
        );
        if (path == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        await File(path).writeAsBytes(bytes, flush: true);
        if (mounted) {
          showNotice(
            context,
            '${events.length} kayıt takvim dosyasına yazıldı.',
            detail: path,
          );
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showNotice(
          context,
          'Takvim dosyası yazılamadı: $e',
          kind: NoticeKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int count({bool h = false, bool d = false, bool t = false}) =>
        _events(hearings: h, deadlines: d, tasks: t).length;
    Widget toggle(String label, int n, bool value, ValueChanged<bool> on) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('$label · $n'),
          value: value,
          onChanged: (v) => setState(() => on(v)),
        );
    return AlertDialog(
      title: const Text('Takvime aktar'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Google, Outlook ve Apple takvimine',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
              toggle(
                'Duruşmalar',
                count(h: true),
                _hearings,
                (v) => _hearings = v,
              ),
              toggle(
                'Süreler',
                count(d: true),
                _deadlines,
                (v) => _deadlines = v,
              ),
              toggle(
                'Görevler ve notlar',
                count(t: true),
                _tasks,
                (v) => _tasks = v,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: _months,
                decoration: const InputDecoration(
                  labelText: 'Aralık',
                  isDense: true,
                ),
                items: [
                  for (final m in const [1, 3, 6, 12])
                    DropdownMenuItem(
                      value: m,
                      child: Text('Bugünden itibaren $m ay'),
                    ),
                ],
                onChanged: (v) => setState(() => _months = v ?? _months),
              ),
              const SizedBox(height: 10),
              const Text(
                'Hatırlatma (takvim uygulaması çalar)',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final (m, label) in const [
                    (1440, '1 gün önce'),
                    (120, '2 saat önce'),
                    (30, '30 dakika önce'),
                  ])
                    FilterChip(
                      label: Text(label),
                      selected: _alarms.contains(m),
                      onSelected: (on) => setState(
                        () => on ? _alarms.add(m) : _alarms.remove(m),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('calendar-names'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Müvekkil adlarını da yaz'),
                subtitle: const Text(
                  'Kapalıyken takvimde yalnız dosya numarası ve mahkeme '
                  'görünür; takvim başka bir şirketin sunucusundadır (KVKK).',
                ),
                value: _names,
                onChanged: (v) => setState(() => _names = v),
              ),
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AgendaColors.taskFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  Platform.isAndroid || Platform.isIOS
                      ? 'Dosya takvim uygulamanızda açılır; eklemeyi onaylayın. '
                            'Yeniden aktarmak kayıtları çoğaltmaz, günceller.'
                      : 'Google Takvim: Ayarlar → İçe ve dışa aktar → İçe aktar. '
                            'Outlook: Dosya → Aç ve Dışa Aktar → İçe Aktar. '
                            'Yeniden aktarmak kayıtları çoğaltmaz, günceller.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgendaColors.taskText,
                  ),
                ),
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
        FilledButton(
          key: const ValueKey('calendar-save'),
          onPressed: _busy || (!_hearings && !_deadlines && !_tasks)
              ? null
              : _save,
          child: Text(
            Platform.isAndroid || Platform.isIOS
                ? 'Takvimde aç'
                : 'Takvim dosyasını kaydet',
          ),
        ),
      ],
    );
  }
}
