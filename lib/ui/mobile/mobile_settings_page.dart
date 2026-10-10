import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/editor/editor_settings.dart';
import '../../services/platform/document_intents.dart';
import '../../services/search/library_controller.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../widgets/learned_phrases_dialog.dart';
import '../widgets/notice.dart';
import 'settings_parts.dart';

/// The archive's folders, on a page: each with its documents, rescanned or
/// left out; a folder added; all brought up to date.
class ArchiveFoldersPage extends StatefulWidget {
  const ArchiveFoldersPage({super.key, required this.library});
  final LibraryController library;

  @override
  State<ArchiveFoldersPage> createState() => _ArchiveFoldersPageState();
}

class _ArchiveFoldersPageState extends State<ArchiveFoldersPage> {
  bool _picking = false;

  Future<void> _add() async {
    setState(() => _picking = true);
    try {
      final path = DocumentIntents.picksFolders
          ? await DocumentIntents.pickFolder()
          : await FilePicker.getDirectoryPath(
              dialogTitle: 'İndekslenecek klasörü seçin',
            );
      if (path != null && mounted) {
        await widget.library.addPaths([path], recursive: true);
      }
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Klasör eklenemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.library, widget.library.progress]),
    builder: (context, _) {
      final library = widget.library;
      final folders = library.sources.where((s) => s.folder).toList();
      return Scaffold(
        backgroundColor: settingsPage(context),
        appBar: settingsBar(
          context,
          'Arşiv klasörleri',
          action: library.active
              ? TextButton(
                  onPressed: library.cancel,
                  child: const Text('Durdur'),
                )
              : folders.isEmpty
              ? null
              : TextButton(
                  onPressed: () => library.refresh(),
                  child: const Text('Güncelle'),
                ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            FilledButton.icon(
              key: const ValueKey('folders-add'),
              onPressed: _picking ? null : _add,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Klasör ekle'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (library.active) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: library.toProcess == 0
                    ? null
                    : library.processed / library.toProcess,
              ),
              const SizedBox(height: 6),
              Text(
                '${library.phase} · ${library.processed}/${library.toProcess}',
                style: const TextStyle(fontSize: 11, color: AgendaColors.muted),
              ),
            ],
            const SettingsSection('KLASÖRLER'),
            if (folders.isEmpty)
              const SettingsGroup(
                padding: EdgeInsets.all(18),
                children: [
                  Text(
                    'Henüz klasör eklenmedi. Eklediğiniz klasörlerdeki '
                    'belgeler aranabilir olur; belgeler yerinde kalır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
                  ),
                ],
              )
            else
              SettingsGroup(
                children: [
                  for (final f in folders)
                    SettingsRow(
                      icon: Icons.folder_outlined,
                      fill: const Color(0xFFFFF3E0),
                      tint: AgendaColors.task,
                      title: f.name,
                      subtitle: f.error ?? '${f.count} evrak · ${f.path}',
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => v == 'refresh'
                            ? library.refresh(ids: [f.id])
                            : library.removeSource(f.id),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'refresh',
                            child: Text('Yeniden tara'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Arşivden çıkar'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 12, 6, 0),
              child: Text(
                'Arşivden çıkarmak dosyaları silmez.',
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// What the suggestions learn from, and what they have learned.
class LearningPage extends StatefulWidget {
  const LearningPage({super.key});

  @override
  State<LearningPage> createState() => _LearningPageState();
}

class _LearningPageState extends State<LearningPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: settingsPage(context),
    appBar: settingsBar(context, 'Öğrenme'),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.save_outlined,
              title: 'Kaydettiğim belgelerden öğren',
              subtitle: 'Bir belge bir kez sayılır',
              trailing: settingsSwitch(EditorSettings.instance.learnSaved, (
                v,
              ) async {
                await EditorSettings.instance.setLearnSaved(v);
                if (mounted) setState(() {});
              }, key: const ValueKey('setting-learn-saved')),
            ),
            SettingsRow(
              icon: Icons.inventory_2_outlined,
              title: 'Arşivden öğren',
              subtitle: 'En az üç belgede geçen ifadeler, haftada bir',
              trailing: settingsSwitch(EditorSettings.instance.learnArchive, (
                v,
              ) async {
                await EditorSettings.instance.setLearnArchive(v);
                if (mounted) setState(() {});
              }, key: const ValueKey('setting-learn-archive')),
            ),
            SettingsRow(
              icon: Icons.auto_awesome_outlined,
              title: 'Öğrenilen ifadeler',
              subtitle: 'Görün, silin',
              onTap: () => LearnedPhrasesDialog.show(context),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 12, 6, 0),
          child: Text(
            'Kişisel bilgi içeren ifadeler öğrenilmez; hepsi bu cihazda kalır.',
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
        ),
      ],
    ),
  );
}
