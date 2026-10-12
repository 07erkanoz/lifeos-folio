import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppColors {
  /// A clear, lively blue: the one every button, link, chosen tab and
  /// focused field is painted with. The cobalt before it was dull enough
  /// that a chosen thing hardly looked chosen.
  static const primary = Color(0xFF2563EB);
  static const primaryHover = Color(0xFF1D4ED8);
  static const primaryDark = Color(0xFF7AA7FF);
  static const secondary = Color(0xFF6B7280);

  /// The mint of the icon's orbit.
  static const accent = Color(0xFF14B8A6);

  /// A document that carries an electronic signature: the red-orange of a
  /// wax seal, which a reader sees at once and takes for a stamp, not for
  /// an error — errors are a plain red. It says a signature is there, never
  /// that it is valid, which the app does not check.
  static const signature = Color(0xFFC2410C);
  static const signatureDark = Color(0xFFFF8A5B);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFE5484D);
  static const darkBg = Color(0xFF000000);
  static const darkSurface = Color(0xFF15171B);
  static const darkPanel = Color(0xFF1D2025);
  static const darkBorder = Color(0xFF2B2F36);
  static const darkText = Color(0xFFF3F4F6);
  static const darkTextMuted = Color(0xFF9CA3AF);
  static const lightBg = Color(0xFFF5F6F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightPanel = Color(0xFFF0F2F5);
  static const lightBorder = Color(0xFFE4E7EC);
  static const lightText = Color(0xFF111827);
  static const lightTextMuted = Color(0xFF6B7280);
}

class AppTheme {
  /// Folio's own words: Inter, drawn for screens, with every Turkish letter.
  /// Documents keep their own fonts (Liberation and the ones they name).
  static const uiFont = 'Inter';

  static ThemeData get darkTheme => _build(true);
  static ThemeData get lightTheme => _build(false);
  static bool get _desktop => const {
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  }.contains(defaultTargetPlatform);

  /// The sizes of Folio's words. Material's are made for a phone held at
  /// arm's length — a field's text at sixteen points, a dialog's title at
  /// twenty-four — and on a computer every screen looked shouted. A computer
  /// reads at thirteen, a phone a point larger.
  static TextTheme _text(Color text, Color muted) {
    final d = _desktop ? 0.0 : 1.0;
    TextStyle style(
      double size,
      FontWeight weight, {
      double spacing = 0,
      double? height,
      Color? color,
    }) => TextStyle(
      fontFamily: uiFont,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
      color: color ?? text,
    );
    return TextTheme(
      displayLarge: style(40 + d, FontWeight.w700, spacing: -1),
      displayMedium: style(32 + d, FontWeight.w700, spacing: -.8),
      displaySmall: style(26 + d, FontWeight.w700, spacing: -.6),
      headlineLarge: style(24 + d, FontWeight.w700, spacing: -.5),
      headlineMedium: style(21 + d, FontWeight.w700, spacing: -.4),
      headlineSmall: style(18 + d, FontWeight.w700, spacing: -.3),
      titleLarge: style(16.5 + d, FontWeight.w700, spacing: -.2),
      titleMedium: style(14 + d, FontWeight.w600, spacing: -.1),
      titleSmall: style(13 + d, FontWeight.w600),
      bodyLarge: style(14 + d, FontWeight.w400, height: 1.45),
      bodyMedium: style(13 + d, FontWeight.w400, height: 1.45),
      bodySmall: style(12 + d * .5, FontWeight.w400, height: 1.4, color: muted),
      labelLarge: style(13 + d * .5, FontWeight.w600),
      labelMedium: style(12, FontWeight.w500),
      labelSmall: style(11, FontWeight.w500, spacing: .2),
    );
  }

  static ThemeData _build(bool dark) {
    final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final text = dark ? AppColors.darkText : AppColors.lightText;
    final muted = dark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final panel = dark ? AppColors.darkPanel : AppColors.lightPanel;
    final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
          primary: dark ? AppColors.primaryDark : AppColors.primary,
          onPrimary: dark ? const Color(0xFF0B1B3A) : Colors.white,
          secondary: AppColors.accent,
          surface: surface,
          onSurface: text,
          surfaceContainerHighest: panel,
          surfaceContainerLow: dark ? AppColors.darkBg : AppColors.lightBg,
          outline: border,
          outlineVariant: border,
          onSurfaceVariant: muted,
          error: AppColors.error,
          // What a chosen segment, a selected tab or toggle, a tonal button
          // and a raised sheet are painted with: left to the defaults they
          // were Material's lilac, beside the blue of everything else.
          primaryContainer: dark
              ? const Color(0xFF172B4D)
              : const Color(0xFFEAF1FF),
          onPrimaryContainer: dark
              ? const Color(0xFFD3E2FF)
              : const Color(0xFF1E40AF),
          secondaryContainer: dark
              ? const Color(0xFF172B4D)
              : const Color(0xFFEAF1FF),
          onSecondaryContainer: dark
              ? const Color(0xFFD3E2FF)
              : const Color(0xFF1E40AF),
          tertiary: AppColors.accent,
          tertiaryContainer: dark
              ? const Color(0xFF0F3B36)
              : const Color(0xFFE0F7F4),
          onTertiaryContainer: dark
              ? const Color(0xFFB7EFE7)
              : const Color(0xFF0F5249),
          errorContainer: dark
              ? const Color(0xFF3B1517)
              : const Color(0xFFFFEEEE),
          onErrorContainer: dark
              ? const Color(0xFFFFC9CA)
              : const Color(0xFFA51D23),
          inversePrimary: dark ? AppColors.primary : AppColors.primaryDark,
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: dark ? AppColors.darkBg : Colors.white,
          surfaceContainer: dark
              ? const Color(0xFF181A1F)
              : const Color(0xFFF3F4F6),
          surfaceContainerHigh: dark
              ? const Color(0xFF1B1E23)
              : const Color(0xFFEEF0F3),
          surfaceDim: dark ? AppColors.darkBg : const Color(0xFFE5E7EB),
          surfaceBright: dark ? AppColors.darkPanel : Colors.white,
          shadow: Colors.black,
        );
    final textTheme = _text(text, muted);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      fontFamily: uiFont,
      textTheme: textTheme,
      scaffoldBackgroundColor: dark ? AppColors.darkBg : AppColors.lightBg,
    );
    // The radii, from a tag to a dialog: rounder as the thing grows.
    const field = 10.0;
    const button = 10.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(button),
    );
    final buttonText = TextStyle(
      fontFamily: uiFont,
      fontSize: _desktop ? 13 : 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    final buttonPadding = EdgeInsets.symmetric(
      horizontal: _desktop ? 16 : 18,
      vertical: _desktop ? 12 : 14,
    );
    return base.copyWith(
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(color: muted),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        // A field the height of a button beside it, its label the size of
        // the text it names.
        // Smaller on a computer, where a mouse needs no finger's room.
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: _desktop ? 12 : 14,
        ),
        hintStyle: TextStyle(
          fontFamily: uiFont,
          color: muted.withValues(alpha: .8),
          fontSize: 13.5,
        ),
        labelStyle: TextStyle(fontFamily: uiFont, color: muted, fontSize: 13),
        helperStyle: TextStyle(
          fontFamily: uiFont,
          color: muted,
          fontSize: 11.5,
        ),
        errorStyle: const TextStyle(
          fontFamily: uiFont,
          color: AppColors.error,
          fontSize: 11.5,
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontFamily: uiFont,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.error)
                ? AppColors.error
                : states.contains(WidgetState.focused)
                ? scheme.primary
                : muted,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(field),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(field),
          borderSide: BorderSide(color: border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(field),
          borderSide: BorderSide(color: border.withValues(alpha: .6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(field),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(field),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(field),
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: shape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: surface,
          foregroundColor: text,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(button),
            side: BorderSide(color: border),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: border),
          foregroundColor: text,
          backgroundColor: surface,
          padding: EdgeInsets.symmetric(
            horizontal: _desktop ? 14 : 16,
            vertical: _desktop ? 12 : 14,
          ),
          textStyle: buttonText,
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      // Chosen and not chosen side by side, as a pill on a grey track: the
      // chosen one white and blue, the rest quiet.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            buttonText.copyWith(fontSize: _desktop ? 12.5 : 13.5),
          ),
          visualDensity: VisualDensity.compact,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : panel,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? muted.withValues(alpha: .6)
                : states.contains(WidgetState.selected)
                ? scheme.primary
                : muted,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? scheme.primary : muted,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? scheme.primary.withValues(alpha: .45)
                  : border,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(button)),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            width: 1.5,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : muted.withValues(alpha: .6),
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? muted.withValues(alpha: .4)
              : states.contains(WidgetState.selected)
              ? scheme.primary
              : muted.withValues(alpha: .7),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? const Color(0xFF9CA3AF) : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : (dark ? const Color(0xFF374151) : const Color(0xFFD1D5DB)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: muted,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: border,
        labelStyle: buttonText,
        unselectedLabelStyle: buttonText.copyWith(fontWeight: FontWeight.w500),
      ),
      // A list's row at the page's text size on a computer, not Material's
      // sixteen points made for a finger.
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        iconColor: muted,
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: _desktop ? 13.5 : 15,
          fontWeight: FontWeight.w500,
          color: text,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: _desktop ? 12 : 13,
          height: 1.35,
          color: muted,
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: muted,
        collapsedIconColor: muted,
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selectedColor: scheme.primaryContainer,
        backgroundColor: surface,
        // A chip's label style replaces the theme's text rather than
        // extending it, so the family has to be named here too.
        labelStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: text,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
        textStyle: const TextStyle(
          fontFamily: uiFont,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      // A dialog is a card lifted over a dimmed page: no frame, a soft
      // shadow, a heading and its text at the size of the page's text, its
      // buttons at the bottom right with room around them.
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shadowColor: dark ? const Color(0xCC000000) : const Color(0x400F172A),
        barrierColor: dark ? const Color(0xA6000000) : const Color(0x6610172A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: dark ? BorderSide(color: border) : BorderSide.none,
        ),
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
          color: text,
        ),
        contentTextStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: 13.5,
          height: 1.5,
          color: text,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 6, 20, 18),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: const Color(0x330F172A),
        menuPadding: const EdgeInsets.all(6),
        textStyle: TextStyle(fontFamily: uiFont, fontSize: 13, color: text),
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
          elevation: const WidgetStatePropertyAll(12),
          shadowColor: const WidgetStatePropertyAll(Color(0x330F172A)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
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
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontFamily: uiFont, fontSize: 13),
          foregroundColor: text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: const TextStyle(
          fontFamily: uiFont,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2B2F36) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      // A small card floating above the bottom edge, not a strip along it.
      // On a desktop it keeps a reading width instead of spanning a wide
      // window; on a phone it keeps a margin from the screen's edges.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF23262C)
            : const Color(0xFF111827),
        contentTextStyle: const TextStyle(
          fontFamily: uiFont,
          fontSize: 13,
          height: 1.35,
          color: Color(0xFFF3F4F6),
        ),
        actionTextColor: AppColors.primaryDark,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: dark ? const Color(0xFF363B42) : Colors.transparent,
          ),
        ),
        width: _desktop ? 440 : null,
        insetPadding: _desktop
            ? null
            : const EdgeInsets.fromLTRB(12, 0, 12, 14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
        linearMinHeight: 3,
        borderRadius: BorderRadius.circular(3),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(5),
      ),
    );
  }
}
