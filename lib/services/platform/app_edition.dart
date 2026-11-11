import 'dart:io';

/// Which product this run is (approved mockup, 27 Ekim 2026): Folio, the
/// lawyer's, or LifeOS Ofis, the same documents and editor for anyone, without
/// UYAP, the office, clients, cash or the agenda. One app, built once: the
/// launcher says which (`--ofis`, lib/ofis_app.dart), and what is a lawyer's
/// alone asks [AppEdition.isOfis] before it shows.
enum AppEdition {
  folio('LifeOS Folio', 'assets/branding/lifeos_folio.png'),
  ofis('LifeOS Ofis', 'assets/branding/lifeos_ofis.png');

  const AppEdition(this.title, this.icon);
  final String title, icon;

  /// This run's: set once at start, before the first frame.
  static AppEdition current = AppEdition.folio;

  /// Whether this run is LifeOS Ofis.
  static bool get isOfis => current == AppEdition.ofis;

  /// Whether this program is LifeOS Ofis by how it was built or packaged,
  /// where no launcher says so with `--ofis`: an Android app built as Ofis
  /// (`--dart-define=LIFEOS_OFIS=true`), or the Mac app `LifeOS Ofis.app`,
  /// which carries a mark in its Resources (it is Folio's build under its
  /// own name and identity; .github/workflows/macos.yml).
  static bool get packagedAsOfis {
    if (const bool.fromEnvironment('LIFEOS_OFIS')) return true;
    if (!Platform.isMacOS) return false;
    try {
      final contents = File(Platform.resolvedExecutable).parent.parent;
      return File('${contents.path}/Resources/lifeos-ofis').existsSync();
    } catch (_) {
      return false;
    }
  }
}
