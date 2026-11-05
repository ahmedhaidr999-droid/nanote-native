import 'package:flutter/material.dart';

/// Exact v1.9.1 design tokens.
class NanoteTokens {
  // Light
  static const Color lightBackground = Color(0xFFF7F9FC);
  static const Color lightForeground = Color(0xFF16233A);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightPrimary = Color(0xFF1E6FF2);
  static const Color lightPrimaryFg = Color(0xFFFFFFFF);
  static const Color lightSecondary = Color(0xFFEEF2F8);
  static const Color lightSecondaryFg = Color(0xFF0A3A8F);
  static const Color lightMutedFg = Color(0xFF5A6B85);
  static const Color lightAccent = Color(0xFFE8F0FE);
  static const Color lightAccentFg = Color(0xFF0A3A8F);
  static const Color lightDestructive = Color(0xFFE5484D);
  static const Color lightBorder = Color(0xFFE2E8F1);
  static const Color lightSuccess = Color(0xFF22A06B);
  static const Color lightWarning = Color(0xFFFF9F1C);

  // Dark
  static const Color darkBackground = Color(0xFF0E1622);
  static const Color darkForeground = Color(0xFFE8EEF7);
  static const Color darkCard = Color(0xFF16202E);
  static const Color darkPrimary = Color(0xFF6BA6FF);
  static const Color darkPrimaryFg = Color(0xFF0A2050);
  static const Color darkSecondary = Color(0xFF1C2838);
  static const Color darkSecondaryFg = Color(0xFFC9D6EA);
  static const Color darkMutedFg = Color(0xFF94A6C0);
  static const Color darkAccent = Color(0xFF1B2A44);
  static const Color darkAccentFg = Color(0xFFBAD4FF);
  static const Color darkDestructive = Color(0xFFFF6B6B);
  static const Color darkBorder = Color(0xFF24324A);
  static const Color darkSuccess = Color(0xFF3ECF8E);
  static const Color darkWarning = Color(0xFFFFB84D);
}

/// Extra named colors exposed via ThemeExtension (accent, success, warning…).
@immutable
class NanoteColors extends ThemeExtension<NanoteColors> {
  final Color accent;
  final Color accentFg;
  final Color secondaryFg;
  final Color mutedFg;
  final Color success;
  final Color warning;

  const NanoteColors({
    required this.accent,
    required this.accentFg,
    required this.secondaryFg,
    required this.mutedFg,
    required this.success,
    required this.warning,
  });

  @override
  NanoteColors copyWith({
    Color? accent,
    Color? accentFg,
    Color? secondaryFg,
    Color? mutedFg,
    Color? success,
    Color? warning,
  }) =>
      NanoteColors(
        accent: accent ?? this.accent,
        accentFg: accentFg ?? this.accentFg,
        secondaryFg: secondaryFg ?? this.secondaryFg,
        mutedFg: mutedFg ?? this.mutedFg,
        success: success ?? this.success,
        warning: warning ?? this.warning,
      );

  @override
  NanoteColors lerp(NanoteColors? other, double t) {
    if (other is! NanoteColors) return this;
    return NanoteColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentFg: Color.lerp(accentFg, other.accentFg, t)!,
      secondaryFg: Color.lerp(secondaryFg, other.secondaryFg, t)!,
      mutedFg: Color.lerp(mutedFg, other.mutedFg, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

/// Corner radius used throughout the app.
const double NANOTE_RADIUS = 12.0;

class NanoteTheme {
  static const _fontFamily = null; // system default (Arabic-capable)

  static ThemeData light() => _theme(
        brightness: Brightness.light,
        background: NanoteTokens.lightBackground,
        foreground: NanoteTokens.lightForeground,
        card: NanoteTokens.lightCard,
        primary: NanoteTokens.lightPrimary,
        primaryFg: NanoteTokens.lightPrimaryFg,
        secondary: NanoteTokens.lightSecondary,
        secondaryFg: NanoteTokens.lightSecondaryFg,
        mutedFg: NanoteTokens.lightMutedFg,
        accent: NanoteTokens.lightAccent,
        accentFg: NanoteTokens.lightAccentFg,
        destructive: NanoteTokens.lightDestructive,
        border: NanoteTokens.lightBorder,
        success: NanoteTokens.lightSuccess,
        warning: NanoteTokens.lightWarning,
      );

  static ThemeData dark() => _theme(
        brightness: Brightness.dark,
        background: NanoteTokens.darkBackground,
        foreground: NanoteTokens.darkForeground,
        card: NanoteTokens.darkCard,
        primary: NanoteTokens.darkPrimary,
        primaryFg: NanoteTokens.darkPrimaryFg,
        secondary: NanoteTokens.darkSecondary,
        secondaryFg: NanoteTokens.darkSecondaryFg,
        mutedFg: NanoteTokens.darkMutedFg,
        accent: NanoteTokens.darkAccent,
        accentFg: NanoteTokens.darkAccentFg,
        destructive: NanoteTokens.darkDestructive,
        border: NanoteTokens.darkBorder,
        success: NanoteTokens.darkSuccess,
        warning: NanoteTokens.darkWarning,
      );

  static ThemeData _theme({
    required Brightness brightness,
    required Color background,
    required Color foreground,
    required Color card,
    required Color primary,
    required Color primaryFg,
    required Color secondary,
    required Color secondaryFg,
    required Color mutedFg,
    required Color accent,
    required Color accentFg,
    required Color destructive,
    required Color border,
    required Color success,
    required Color warning,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: primaryFg,
      secondary: secondary,
      onSecondary: secondaryFg,
      error: destructive,
      onError: brightness == Brightness.light ? Colors.white : const Color(0xFF2B0A0A),
      surface: card,
      onSurface: foreground,
      surfaceContainerHighest: secondary,
      outline: border,
      outlineVariant: border,
    );

    final radius = BorderRadius.circular(NANOTE_RADIUS);

    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      extensions: [
        NanoteColors(
          accent: accent,
          accentFg: accentFg,
          secondaryFg: secondaryFg,
          mutedFg: mutedFg,
          success: success,
          warning: warning,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: foreground,
          fontFamily: _fontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: card,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: card,
        modalBackgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: radius),
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: card,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondary,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: primaryFg,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: primaryFg,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: mutedFg,
        dividerColor: border,
      ),
    );
  }
}

/// Convenience accessor for the NanoteColors extension.
NanoteColors nanoteColors(BuildContext context) =>
    Theme.of(context).extension<NanoteColors>()!;
