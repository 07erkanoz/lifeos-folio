import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppColors {
  /// The cobalt of the app's icon, as lively as it is there. The grey-blue
  /// used before made every button, link and mark look faded.
  static const primary = Color(0xFF2B5EA8);
  static const primaryHover = Color(0xFF214B8A);
  static const primaryDark = Color(0xFF8FB8F2);
  static const secondary = Color(0xFF71717A);

  /// The mint of the icon's orbit.
  static const accent = Color(0xFF4DB59C);

  /// A document that carries an electronic signature: the red-orange of a
  /// wax seal, which a reader sees at once and takes for a stamp, not for
  /// an error — errors are a plain red. It says a signature is there, never
  /// that it is valid, which the app does not check.
  static const signature = Color(0xFFC2410C);
  static const signatureDark = Color(0xFFFF8A5B);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const darkBg = Color(0xFF000000);
  static const darkSurface = Color(0xFF101010);
  static const darkPanel = Color(0xFF191919);
  static const darkBorder = Color(0xFF292929);
  static const darkText = Color(0xFFF5F5F5);
  static const darkTextMuted = Color(0xFFA1A1AA);
  static const lightBg = Color(0xFFF7F8FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightPanel = Color(0xFFF0F2F5);
  static const lightBorder = Color(0xFFE5E7EB);
  static const lightText = Color(0xFF18181B);
  static const lightTextMuted = Color(0xFF71717A);
}

class AppTheme {
  static ThemeData get darkTheme => _build(true);
  static ThemeData get lightTheme => _build(false);
  static bool get _desktop => const {
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  }.contains(defaultTargetPlatform);
  static ThemeData _build(bool dark) {
    final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final text = dark ? AppColors.darkText : AppColors.lightText;
    final muted = dark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
          primary: dark ? AppColors.primaryDark : AppColors.primary,
          onPrimary: dark ? const Color(0xFF0E2340) : Colors.white,
          secondary: AppColors.accent,
          surface: surface,
          onSurface: text,
          surfaceContainerHighest: dark
              ? AppColors.darkPanel
              : AppColors.lightPanel,
          surfaceContainerLow: dark ? AppColors.darkBg : AppColors.lightBg,
          outline: border,
          outlineVariant: border,
          onSurfaceVariant: muted,
          error: AppColors.error,
          // What a chosen segment, a selected tab or toggle, a tonal button
          // and a raised sheet are painted with: left to the defaults they
          // were Material's lilac, beside the cobalt of everything else.
          primaryContainer: dark
              ? const Color(0xFF1C3354)
              : const Color(0xFFEAF0F9),
          onPrimaryContainer: dark
              ? const Color(0xFFD6E4F7)
              : const Color(0xFF173B6E),
          secondaryContainer: dark
              ? const Color(0xFF1C3354)
              : const Color(0xFFEAF0F9),
          onSecondaryContainer: dark
              ? const Color(0xFFD6E4F7)
              : const Color(0xFF173B6E),
          tertiary: AppColors.accent,
          tertiaryContainer: dark
              ? const Color(0xFF123B31)
              : const Color(0xFFE3F5EF),
          onTertiaryContainer: dark
              ? const Color(0xFFBFEBDD)
              : const Color(0xFF0F5240),
          inversePrimary: dark ? AppColors.primary : AppColors.primaryDark,
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: dark ? AppColors.darkBg : Colors.white,
          surfaceContainer: dark
              ? const Color(0xFF141414)
              : const Color(0xFFF3F4F6),
          surfaceContainerHigh: dark
              ? const Color(0xFF171717)
              : const Color(0xFFEDEFF2),
          surfaceDim: dark ? AppColors.darkBg : const Color(0xFFE4E6EA),
          surfaceBright: dark ? AppColors.darkPanel : Colors.white,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      fontFamily: 'LiberationSans',
      scaffoldBackgroundColor: dark ? AppColors.darkBg : AppColors.lightBg,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        // A field the height of a button beside it, its label the size of
        // the text it names.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        labelStyle: TextStyle(color: muted, fontSize: 13.5),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.error)
                ? AppColors.error
                : states.contains(WidgetState.focused)
                ? scheme.primary
                : muted,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: border),
          foregroundColor: text,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selectedColor: scheme.primary.withValues(alpha: 0.12),
        // A chip's label style replaces the theme's text rather than
        // extending it, so the family has to be named here too.
        labelStyle: TextStyle(
          fontFamily: 'LiberationSans',
          fontSize: 12,
          color: text,
        ),
      ),
      // A dialog is a card over a dimmed page: a heading, its text at the
      // size of the page's text, its buttons at the bottom right with room
      // around them.
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shadowColor: const Color(0x55000000),
        barrierColor: dark ? const Color(0x99000000) : const Color(0x5C0F1520),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'LiberationSans',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -.2,
          color: text,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'LiberationSans',
          fontSize: 14,
          height: 1.45,
          color: text,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 4, 20, 18),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: const Color(0x40000000),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        textStyle: TextStyle(
          fontFamily: 'LiberationSans',
          fontSize: 13.5,
          color: text,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      // The lists that open from a field or a button (FolioSelect, the
      // menus): a card under it, not a slab over it.
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(10),
          shadowColor: const WidgetStatePropertyAll(Color(0x40000000)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: MenuItemButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(
            fontFamily: 'LiberationSans',
            fontSize: 13.5,
          ),
          foregroundColor: text,
          shape: const RoundedRectangleBorder(),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF333333) : const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      // A small card floating above the bottom edge, not a strip along it.
      // On a desktop it keeps a reading width instead of spanning a wide
      // window; on a phone it keeps a margin from the screen's edges.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF23272B)
            : const Color(0xFF1D2227),
        contentTextStyle: const TextStyle(
          fontSize: 13.5,
          height: 1.3,
          color: Color(0xFFF1F3F5),
        ),
        actionTextColor: AppColors.primaryDark,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: dark ? const Color(0xFF363B40) : Colors.transparent,
          ),
        ),
        width: _desktop ? 440 : null,
        insetPadding: _desktop
            ? null
            : const EdgeInsets.fromLTRB(12, 0, 12, 14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: border,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(5),
      ),
    );
  }
}
