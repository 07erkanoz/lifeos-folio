import 'package:flutter/material.dart';

import 'agenda_page.dart' show AgendaColors;

/// UETS Tebligatlarım until the UETS connection comes (UYGULAMAPLANI §12,
/// T10): where the notifications will be, and that they are not yet.
class UetsPlaceholderPage extends StatelessWidget {
  const UetsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? scheme.surface
          : AgendaColors.page,
      child: Center(
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                size: 36,
                color: AgendaColors.hearing,
              ),
              SizedBox(height: 12),
              Text(
                'UETS Tebligatlarım',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'UETS bağlantısı geldiğinde tebligatlarınız burada listelenecek, '
                'dosyalarınızla eşleştirilecek ve süreleri ajandaya düşecek.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
