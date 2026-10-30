import 'package:flutter/material.dart';

import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import 'case_ai_tab.dart';

/// Yapay zekâ: the lawyer's conversations with their own AI program, a page
/// of its own. Every conversation is listed with the case it is of; a new
/// one starts of no case, and the program finds the case the lawyer names
/// (or of [startCase], when opened from a case's page). [openChat] opens
/// one gone on with.
class AiPage extends StatelessWidget {
  const AiPage({super.key, this.openChat, this.startCase, this.onOpenPath});

  final String? openChat;
  final UyapCaseRecord? startCase;
  final ValueChanged<String>? onOpenPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? scheme.surface : AgendaColors.page,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Yapay zekâ',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Sorularınızı kendi yapay zekâ aboneliğinizle sorarsınız. Bir '
              'dosyayı adıyla, numarasıyla ya da bir tarafıyla anınca '
              'yapay zekâ dosyayı bulur; sohbet o dosyaya kaydedilir.',
              style: TextStyle(fontSize: 13, color: AgendaColors.muted),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CaseAiTab(
                  caseKey: null,
                  record: null,
                  database: PortalDatabase.shared,
                  onOpenPath: onOpenPath,
                  openChat: openChat,
                  startCase: startCase,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
