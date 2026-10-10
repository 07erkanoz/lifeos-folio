import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../../services/office/office_chat.dart';
import '../../services/platform/app_directories.dart';
import '../../services/platform/document_intents.dart';
import '../../services/office/office_network.dart';
import '../../services/platform/file_actions.dart';
import '../../services/platform/phone_document_save.dart';
import '../../services/speech/speech_session.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../widgets/drop_zone.dart';
import '../portfolio/portfolio_rows.dart' show clockText, dayText;
import 'office_offer_dialog.dart' show sizeText;

/// Mesajlar (docs/buro.md, Mesajlaşma): the office's private and group
/// talks and its announcements, sealed between members; words, files,
/// pictures and voice.
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key, this.network});
  final OfficeNetwork? network;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;
  String? _open;

  Future<void> _new() async {
    final me = _net.me;
    final manager = _net.ledger.isManager(me);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('chat-new-private'),
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Özel mesaj'),
              onTap: () => Navigator.pop(context, 'ozel'),
            ),
            ListTile(
              key: const ValueKey('chat-new-group'),
              leading: const Icon(Icons.group_outlined),
              title: const Text('Grup'),
              onTap: () => Navigator.pop(context, 'grup'),
            ),
            if (manager)
              ListTile(
                key: const ValueKey('chat-new-broadcast'),
                leading: const Icon(Icons.campaign_outlined),
                title: const Text('Büroya duyuru'),
                subtitle: const Text('Bütün üyelere; yalnız yöneticiler yazar'),
                onTap: () => Navigator.pop(context, 'duyuru'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    Chat? chat;
    if (choice == 'duyuru') {
      chat = await _net.broadcastChat();
    } else {
      final picked = await _pickMembers(group: choice == 'grup');
      if (picked == null) return;
      chat = choice == 'grup'
          ? await _net.groupChat(picked.$1, picked.$2)
          : await _net.privateChat(picked.$2.single);
    }
    if (chat != null) _show(chat);
  }

  Future<(String, List<String>)?> _pickMembers({required bool group}) {
    final me = _net.me;
    final members = [
      for (final m in _net.ledger.people)
        if (m.deviceId != me) m,
    ];
    final chosen = <String>{};
    final name = TextEditingController();
    return showDialog<(String, List<String>)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(group ? 'Yeni grup' : 'Kime yazacaksınız?'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (group)
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Grubun adı'),
                  ),
                if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Büroda başka üye yok.'),
                  ),
                // Many members scroll; the dialog stays on the screen.
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in members)
                        group
                            ? CheckboxListTile(
                                value: chosen.contains(m.deviceId),
                                title: Text(m.name),
                                subtitle: Text(m.role.label),
                                onChanged: (v) => set(
                                  () => v == true
                                      ? chosen.add(m.deviceId)
                                      : chosen.remove(m.deviceId),
                                ),
                              )
                            : ListTile(
                                key: ValueKey('chat-to-${m.deviceId}'),
                                title: Text(m.name),
                                subtitle: Text(m.role.label),
                                onTap: () =>
                                    Navigator.pop(context, ('', [m.deviceId])),
                              ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            if (group)
              FilledButton(
                onPressed: chosen.isEmpty
                    ? null
                    : () =>
                          Navigator.pop(context, (name.text, chosen.toList())),
                child: const Text('Grubu kur'),
              ),
          ],
        ),
      ),
    );
  }

  void _show(Chat chat) {
    unawaited(_net.markRead(chat));
    if (MediaQuery.sizeOf(context).width < 900) {
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(chat.titleFor(_net.me))),
              body: ChatThread(network: _net, chatId: chat.id),
            ),
          ),
        ),
      );
    }
    setState(() => _open = chat.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Material, not a coloured box: the talks' rows paint on it.
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? scheme.surface
          : AgendaColors.page,
      child: ListenableBuilder(
        listenable: _net,
        builder: (context, _) {
          final me = _net.me;
          final chats = _net.chats.all;
          return LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 900;
              final list = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                    child: Row(
                      children: [
                        if (!wide &&
                            (Scaffold.maybeOf(context)?.hasDrawer ?? false))
                          IconButton(
                            tooltip: 'Menü',
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            icon: const Icon(Icons.menu_rounded),
                          ),
                        const Expanded(
                          child: Text(
                            'Mesajlar',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_net.ledger.exists)
                          FilledButton.icon(
                            key: const ValueKey('chat-new'),
                            onPressed: () => unawaited(_new()),
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: const Text('Yeni'),
                          ),
                      ],
                    ),
                  ),
                  if (!_net.ledger.exists)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Mesajlar büroyla gelir. Büro ağı sayfasında bir büro '
                        'kurun ya da büronuzun yöneticisinin sizi eklemesini '
                        'bekleyin.',
                        style: TextStyle(color: AgendaColors.muted),
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final c in chats)
                          ListTile(
                            key: ValueKey('chat-${c.id}'),
                            selected: wide && _open == c.id,
                            leading: CircleAvatar(
                              backgroundColor: AgendaColors.hearingFill,
                              child: Icon(
                                switch (c.kind) {
                                  ChatKind.private =>
                                    Icons.person_outline_rounded,
                                  ChatKind.group => Icons.group_outlined,
                                  ChatKind.broadcast => Icons.campaign_outlined,
                                },
                                color: AgendaColors.hearing,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              c.titleFor(me),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _preview(c.last),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _net.chats.unread(c, me) == 0
                                ? null
                                : Badge(
                                    label: Text('${_net.chats.unread(c, me)}'),
                                  ),
                            onTap: () => _show(c),
                          ),
                      ],
                    ),
                  ),
                ],
              );
              if (!wide) return list;
              return Row(
                children: [
                  SizedBox(width: 340, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _open == null || _net.chats.of(_open!) == null
                        ? const Center(
                            child: Text(
                              'Soldan bir konuşma seçin ya da yenisini başlatın.',
                              style: TextStyle(color: AgendaColors.muted),
                            ),
                          )
                        : ChatThread(
                            key: ValueKey(_open),
                            network: _net,
                            chatId: _open!,
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static String _preview(ChatMessage? m) {
    if (m == null) return 'Henüz mesaj yok';
    if (m.deleted) return '${m.byName}: mesaj silindi';
    if (m.text.isNotEmpty) return '${m.byName}: ${m.text}';
    final a = m.attachments.firstOrNull;
    return switch (a?.kind) {
      AttachmentKind.voice => '${m.byName}: sesli mesaj',
      AttachmentKind.image => '${m.byName}: resim',
      _ => '${m.byName}: ${a?.name ?? ''}',
    };
  }
}

/// One talk: its messages and the box to write in, attach to and speak.
class ChatThread extends StatefulWidget {
  const ChatThread({super.key, required this.network, required this.chatId});
  final OfficeNetwork network;
  final String chatId;

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final _text = TextEditingController();
  RecorderMicrophone? _mic;
  StreamSubscription<Float32List>? _heard;
  final _samples = <Float32List>[];
  DateTime? _since;

  /// The voice message playing, one at a time: another stops it.
  AudioSource? _source;
  SoundHandle? _handle;
  String? _playing;
  bool _starting = false;

  OfficeNetwork get _net => widget.network;

  @override
  void dispose() {
    _text.dispose();
    unawaited(_heard?.cancel());
    unawaited(_mic?.close());
    unawaited(_stopPlaying());
    super.dispose();
  }

  Future<void> _say(Future<String?> action) async {
    final error = await action;
    if (error != null && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _attach({bool image = false}) async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: image ? FileType.image : FileType.any,
    );
    final paths = [
      for (final f in picked?.files ?? const <PlatformFile>[])
        if (f.path != null) f.path!,
    ];
    final chat = _net.chats.of(widget.chatId);
    if (paths.isEmpty || chat == null) return;
    await _say(_net.post(chat, text: _text.text, files: paths));
    _text.clear();
  }

  Future<void> _voice() async {
    if (_mic != null) return _stopVoice();
    // A second tap while the microphone opens opens no second one.
    if (_starting) return;
    _starting = true;
    try {
      await _startVoice();
    } finally {
      _starting = false;
    }
  }

  Future<void> _startVoice() async {
    if (!await DocumentIntents.microphone()) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Mikrofon izni verilmedi. Telefonun ayarlarından Folio’ya '
              'mikrofon izni verip yeniden deneyin.',
            ),
          ),
        );
      }
      return;
    }
    final mic = RecorderMicrophone();
    try {
      final stream = await mic.open(16000);
      if (!mounted) {
        await mic.close();
        return;
      }
      _samples.clear();
      _heard = stream.listen(_samples.add);
      setState(() {
        _mic = mic;
        _since = DateTime.now();
      });
    } catch (e) {
      await mic.close();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Mikrofon açılamadı: $e')));
      }
    }
  }

  Future<void> _stopVoice() async {
    final mic = _mic, since = _since;
    await _heard?.cancel();
    await mic?.close();
    setState(() => _mic = null);
    final length = _samples.fold<int>(0, (n, s) => n + s.length);
    if (length < 16000 ~/ 2 || since == null) return;
    final all = Float32List(length);
    var at = 0;
    for (final s in _samples) {
      all.setAll(at, s);
      at += s.length;
    }
    // Kept, each in a folder of its own: the message plays from it, and
    // sends it to a device that was away, long after a temporary folder
    // would have been emptied; two in one minute write over neither.
    final now = DateTime.now();
    final dir = await Directory(
      p.join((await folioSupportDirectory()).path, 'sesli-mesajlar'),
    ).create(recursive: true);
    final own = await dir.createTemp('ses-');
    final seconds = now.second.toString().padLeft(2, '0');
    final file = File(
      p.join(
        own.path,
        'Sesli mesaj ${dayText(now)} '
        '${clockText(now).replaceAll(':', '.')}.$seconds.wav',
      ),
    );
    await file.writeAsBytes(wav(all, 16000), flush: true);
    final chat = _net.chats.of(widget.chatId);
    if (chat != null) {
      await _say(
        _net.post(
          chat,
          files: [file.path],
          voiceSeconds: (length / 16000).round(),
        ),
      );
    }
  }

  void _send() {
    final chat = _net.chats.of(widget.chatId);
    if (chat == null || _text.text.trim().isEmpty) return;
    final text = _text.text;
    _text.clear();
    unawaited(_say(_net.post(chat, text: text)));
  }

  /// Files dropped on the talk: sent in it, with the words being written.
  Future<void> _dropped(List<String> paths) async {
    final chat = _net.chats.of(widget.chatId);
    final (:files, :more) = droppedFiles(paths);
    if (chat == null || files.isEmpty || !_net.mayWrite(chat)) return;
    if (more) _tooMany(files.length);
    final error = await _net.post(chat, text: _text.text, files: files);
    if (!mounted) return;
    // The words written stay when they did not go.
    if (error == null) {
      _text.clear();
    } else {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _tooMany(int sent) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Klasörde $sent dosyadan fazlası var; ilk $sent dosya gönderiliyor.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DropZoneOverlay(
    title: 'Göndermek için bırakın',
    subtitle: 'Dosyalar bu konuşmaya gider',
    onFilesDropped: (paths) => unawaited(_dropped(paths)),
    child: _thread(context),
  );

  Widget _thread(BuildContext context) => ListenableBuilder(
    listenable: _net,
    builder: (context, _) {
      final chat = _net.chats.of(widget.chatId);
      if (chat == null) return const SizedBox.shrink();
      final me = _net.me;
      final messages = chat.ordered.reversed.toList();
      final writes = _net.mayWrite(chat);
      final scheme = Theme.of(context).colorScheme;
      return Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(14),
              itemCount: messages.length,
              itemBuilder: (context, i) =>
                  _bubble(context, chat, messages[i], me),
            ),
          ),
          if (!writes)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Bu konuşmaya yalnız büronun yöneticileri yazar.',
                style: TextStyle(color: AgendaColors.muted),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('chat-attach'),
                      tooltip: 'Dosya ekle',
                      onPressed: () => unawaited(_attach()),
                      icon: const Icon(Icons.attach_file_rounded),
                    ),
                    IconButton(
                      key: const ValueKey('chat-image'),
                      tooltip: 'Resim ekle',
                      onPressed: () => unawaited(_attach(image: true)),
                      icon: const Icon(Icons.image_outlined),
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('chat-text'),
                        controller: _text,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: _mic != null
                              ? 'Kaydediliyor… bitirmek için mikrofona basın'
                              : 'Mesaj yazın',
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('chat-voice'),
                      tooltip: _mic == null
                          ? 'Sesli mesaj'
                          : 'Kaydı bitir ve gönder',
                      onPressed: () => unawaited(_voice()),
                      icon: Icon(
                        _mic == null
                            ? Icons.mic_none_rounded
                            : Icons.stop_circle_rounded,
                        color: _mic == null ? null : AgendaColors.deadline,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('chat-send'),
                      tooltip: 'Gönder',
                      onPressed: _send,
                      icon: Icon(Icons.send_rounded, color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _bubble(BuildContext context, Chat chat, ChatMessage m, String me) {
    final mine = m.by == me;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('chat-message-${m.id}'),
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
        decoration: BoxDecoration(
          color: mine ? AgendaColors.hearingFill : scheme.surface,
          border: mine ? null : Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '${mine ? 'Siz' : m.byName} · ${dayText(m.at)} '
                    '${clockText(m.at)}'
                    '${!m.deleted && chat.edited(m.id) ? ' · düzenlendi' : ''}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AgendaColors.muted,
                    ),
                  ),
                ),
                // One's own words: corrected or taken back, for all.
                if (mine && !m.deleted)
                  SizedBox(
                    width: 26,
                    height: 20,
                    child: PopupMenuButton<String>(
                      key: ValueKey('chat-message-menu-${m.id}'),
                      tooltip: 'Mesaj',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: AgendaColors.muted,
                      ),
                      onSelected: (v) => unawaited(
                        v == 'sil' ? _delete(chat, m) : _edit(chat, m),
                      ),
                      itemBuilder: (_) => [
                        if (m.text.isNotEmpty)
                          const PopupMenuItem(
                            value: 'duzelt',
                            child: Text('Düzelt'),
                          ),
                        const PopupMenuItem(value: 'sil', child: Text('Sil')),
                      ],
                    ),
                  ),
              ],
            ),
            if (m.deleted)
              const Text(
                'Bu mesaj silindi',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AgendaColors.muted,
                ),
              )
            else if (m.text.isNotEmpty)
              Text(m.text),
            for (final a in m.attachments) _attachment(context, m, a),
          ],
        ),
      ),
    );
  }

  /// The writer's own message, its words corrected for everyone in the talk.
  Future<void> _edit(Chat chat, ChatMessage m) async {
    final field = TextEditingController(text: m.text);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mesajı düzelt'),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('chat-edit-field'),
            controller: field,
            autofocus: true,
            minLines: 1,
            maxLines: 6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('chat-edit-save'),
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    field.dispose();
    if (text == null || text.trim() == m.text.trim()) return;
    final error = await _net.correct(chat, m, text: text);
    if (error != null && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// The writer's own message taken back, for everyone in the talk.
  Future<void> _delete(Chat chat, ChatMessage m) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mesaj silinsin mi?'),
        content: const Text(
          'Mesaj konuşmadaki herkesten silinir; yerinde “Bu mesaj silindi” '
          'yazar. Önceden gönderilmiş dosyalar alanların cihazında kalır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('chat-delete-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final error = await _net.correct(chat, m, delete: true);
    if (error != null && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Widget _attachment(BuildContext context, ChatMessage m, ChatAttachment a) {
    final path = _net.chats.fileOf(m.id, a.name);
    final here = path != null && File(path).existsSync();
    Widget actions() => Wrap(
      spacing: 2,
      children: [
        TextButton(
          onPressed: () => unawaited(FileActions.invoke('openDefault', path!)),
          child: const Text('Aç'),
        ),
        TextButton(
          onPressed: () => unawaited(FileActions.invoke('showFolder', path!)),
          child: const Text('Klasörde göster'),
        ),
        TextButton(
          onPressed: () => unawaited(_saveCopy(path!)),
          child: const Text('Kaydet'),
        ),
      ],
    );
    if (!here) {
      // Where it is, rather than a "coming" that may never come: on its
      // way, or waiting for the writer's device to be on the network.
      final coming = _net.transfers
          .where((t) => !t.outgoing && !t.finished && t.meta['mesaj'] == m.id)
          .firstOrNull;
      final state = coming != null
          ? 'aktarılıyor${coming.total > 0 ? ' %${(coming.moved * 100 ~/ coming.total)}' : ''}'
          : m.by == _net.me
          ? 'bu cihaza, yazıldığı cihazdan gelecek'
          : 'gönderenin cihazı ağda görününce gelecek';
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${a.name} · ${sizeText(a.size)} · $state',
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
      );
    }
    final waiting = m.device == _net.self?.deviceId
        ? _net.chats.pending[m.id]?.length ?? 0
        : 0;
    final pending = waiting == 0
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              waiting == 1
                  ? 'Bir cihaza henüz ulaşmadı; ağda görününce gönderilecek.'
                  : '$waiting cihaza henüz ulaşmadı; ağda görününce '
                        'gönderilecek.',
              style: const TextStyle(fontSize: 11, color: AgendaColors.muted),
            ),
          );
    final shown = switch (a.kind) {
      AttachmentKind.image => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(path), width: 260, fit: BoxFit.cover),
            ),
            actions(),
          ],
        ),
      ),
      AttachmentKind.voice => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Dinle',
            onPressed: () => unawaited(_play(path)),
            icon: Icon(
              _playing == path
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline_rounded,
            ),
          ),
          Text('Sesli mesaj · ${a.seconds ?? 0} sn'),
          IconButton(
            tooltip: 'Kaydet',
            onPressed: () => unawaited(_saveCopy(path)),
            icon: const Icon(Icons.download_rounded, size: 18),
          ),
        ],
      ),
      AttachmentKind.file => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description_outlined, size: 17),
                const SizedBox(width: 6),
                Flexible(child: Text('${a.name} · ${sizeText(a.size)}')),
              ],
            ),
            actions(),
          ],
        ),
      ),
    };
    return waiting == 0
        ? shown
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [shown, pending],
          );
  }

  /// A copy of a message's file where the lawyer chooses: on a phone
  /// through its own save screen, which a chosen folder is not.
  Future<void> _saveCopy(String path) async {
    if (PhoneDocumentSave.here) {
      await PhoneDocumentSave.save(
        fileName: p.basename(path),
        bytes: await File(path).readAsBytes(),
      );
      return;
    }
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Nereye kaydedilsin?',
    );
    if (dir != null) await FileActions.copyToDirectory(path, dir);
  }

  /// Plays [path], stopping what played before; the same one again stops.
  Future<void> _play(String path) async {
    final again = _playing == path;
    await _stopPlaying();
    if (again) return;
    try {
      await DocumentIntents.readyToPlay();
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) await soloud.init(channels: Channels.mono);
      final source = _source = await soloud.loadFile(path);
      _handle = soloud.play(source);
      if (mounted) setState(() => _playing = path);
      // Done playing: let go of it.
      unawaited(
        source.allInstancesFinished.first.then((_) {
          if (identical(_source, source)) unawaited(_stopPlaying());
        }),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Ses çalınamadı: $e')));
      }
    }
  }

  Future<void> _stopPlaying() async {
    final source = _source, handle = _handle;
    _source = null;
    _handle = null;
    if (_playing != null) {
      if (mounted) {
        setState(() => _playing = null);
      } else {
        _playing = null;
      }
    }
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) return;
    try {
      if (handle != null) await soloud.stop(handle);
      if (source != null) await soloud.disposeSource(source);
    } catch (_) {}
  }
}
