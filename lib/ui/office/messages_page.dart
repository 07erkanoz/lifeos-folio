import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../services/office/office_chat.dart';
import '../../services/office/office_network.dart';
import '../../services/platform/file_actions.dart';
import '../../services/speech/speech_session.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
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
    final me = _net.self?.deviceId ?? '';
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
    final me = _net.self?.deviceId ?? '';
    final members = [
      for (final m in _net.ledger.members)
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
    unawaited(_net.chats.markRead(chat));
    if (MediaQuery.sizeOf(context).width < 900) {
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: Text(chat.titleFor(_net.self?.deviceId ?? '')),
              ),
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
          final me = _net.self?.deviceId ?? '';
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

  OfficeNetwork get _net => widget.network;

  @override
  void dispose() {
    _text.dispose();
    unawaited(_heard?.cancel());
    unawaited(_mic?.close());
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
    final mic = RecorderMicrophone();
    try {
      final stream = await mic.open(16000);
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
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final file = File(
      p.join(
        dir.path,
        'Sesli mesaj ${dayText(now)} ${clockText(now).replaceAll(':', '.')}.wav',
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _net,
    builder: (context, _) {
      final chat = _net.chats.of(widget.chatId);
      if (chat == null) return const SizedBox.shrink();
      final me = _net.self?.deviceId ?? '';
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
            Text(
              '${mine ? 'Siz' : m.byName} · ${dayText(m.at)} ${clockText(m.at)}',
              style: const TextStyle(fontSize: 10.5, color: AgendaColors.muted),
            ),
            if (m.text.isNotEmpty) Text(m.text),
            for (final a in m.attachments) _attachment(context, m, a),
          ],
        ),
      ),
    );
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
          onPressed: () async {
            final dir = await FilePicker.getDirectoryPath(
              dialogTitle: 'Nereye kaydedilsin?',
            );
            if (dir != null) await FileActions.copyToDirectory(path!, dir);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
    if (!here) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${a.name} · ${sizeText(a.size)} · geliyor…',
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
      );
    }
    return switch (a.kind) {
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
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
          Text('Sesli mesaj · ${a.seconds ?? 0} sn'),
          IconButton(
            tooltip: 'Kaydet',
            onPressed: () async {
              final dir = await FilePicker.getDirectoryPath(
                dialogTitle: 'Nereye kaydedilsin?',
              );
              if (dir != null) await FileActions.copyToDirectory(path, dir);
            },
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
  }

  Future<void> _play(String path) async {
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) await soloud.init(channels: Channels.mono);
      final source = await soloud.loadFile(path);
      soloud.play(source);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Ses çalınamadı: $e')));
      }
    }
  }
}
