import 'package:flutter/material.dart';

import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../help/help_button.dart';
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
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return ColoredBox(
      color: dark ? scheme.surface : AgendaColors.page,
      child: Padding(
        padding: narrow
            ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
            : const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Yapay zekâ',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                HelpButton(Help.ai),
              ],
            ),
            const SizedBox(height: 10),
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
