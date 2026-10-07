import 'dart:async';

import '../platform/system_notices.dart';
import '../security/app_lock.dart';
import 'office_chat.dart';
import 'office_network.dart';
import 'office_task.dart';

/// The office's words as the system's notifications (docs/buro.md,
/// Bildirimler): a message, a task's step, a device asking to be known and
/// files offered. While Folio is locked they say only that something
/// came, not what. A tap opens the page it is about.
void tellOffice(OfficeNetwork net, {SystemNotices? notices, AppLock? lock}) {
  final system = notices ?? SystemNotices.instance;
  bool locked() => (lock ?? AppLock.instance).locked;

  void show(
    String key,
    String title,
    String body,
    String payload,
    String hidden,
  ) => unawaited(
    system
        .show(
          id: key.hashCode & 0x7fffffff,
          title: locked() ? 'LifeOS Folio' : title,
          body: locked() ? hidden : body,
          payload: payload,
          ask: false,
        )
        .catchError((Object _) {}),
  );

  net.onMessage = (Chat chat, ChatMessage m) {
    final what = m.text.isNotEmpty
        ? m.text
        : switch (m.attachments.firstOrNull?.kind) {
            AttachmentKind.voice => 'Sesli mesaj',
            AttachmentKind.image => 'Resim gönderdi',
            AttachmentKind.file =>
              'Dosya gönderdi: ${m.attachments.first.name}',
            null => '',
          };
    final where = chat.kind == ChatKind.private
        ? m.byName
        : '${m.byName} · ${chat.titleFor(net.self?.deviceId ?? '')}';
    show('m${m.id}', where, what, 'mesaj:${chat.id}', 'Yeni mesaj');
  };

  net.onTaskEvent = (OfficeTask t, TaskEvent e) {
    final (title, body) = switch (e.kind) {
      TaskEventKind.given => ('Yeni görev', '${e.byName}: ${t.title}'),
      TaskEventKind.accepted => (
        'Görev kabul edildi',
        '${e.byName}: ${t.title}',
      ),
      TaskEventKind.delivered => (
        'Görev teslim edildi',
        '${e.byName}: ${t.title}',
      ),
      TaskEventKind.approved => ('Görev onaylandı', t.title),
      TaskEventKind.returned => (
        'Görev geri gönderildi',
        '${t.title}: ${e.text}',
      ),
      TaskEventKind.cancelled => (
        'Görev iptal edildi',
        '${t.title}: ${e.text}',
      ),
      TaskEventKind.message => ('${e.byName} · ${t.title}', e.text),
      TaskEventKind.progress => (
        'Görevde ilerleme',
        '${t.title}: %${e.percent ?? t.percent}',
      ),
      _ => ('', ''),
    };
    if (title.isEmpty) return;
    show('g${e.id}', title, body, 'gorev:${t.id}', 'Görevde yeni bir hareket');
  };

  net.incoming.addListener(() {
    final p = net.incoming.value;
    if (p == null) return;
    show(
      'p${p.hashCode}',
      'Bir cihaz sizi tanımak istiyor',
      p.other?.name ?? 'Büro ağında yeni bir cihaz',
      'buro:',
      'Büro ağında yeni bir istek',
    );
  });

  net.incomingOffer.addListener(() {
    final t = net.incomingOffer.value;
    if (t == null) return;
    show(
      'o${t.id}',
      '${t.peer.name.isEmpty ? t.peer.device : t.peer.name} dosya gönderiyor',
      t.files.length == 1 ? t.files.single.name : '${t.files.length} dosya',
      'buro:',
      'Size dosya gönderiliyor',
    );
  });
}
