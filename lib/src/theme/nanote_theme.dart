import 'package:flutter/material.dart';

/// Nanote v1.9.1 design tokens.
///
/// Ink & paper identity: calm, clean, professional — thin lines, very soft
/// shadows, moderate corner radii. The ONLY allowed blue is Nanote Blue
/// `#1E6FF2` (light) / `#6BA6FF` (dark). No indigo, no other blue shade.
class NanoteTokens {
  // ------------------------------------------------------------------ light
  static const Color lightBackground = Color(0xFFF7F9FC);
  static const Color lightForeground = Color(0xFF16233A);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightPrimary = Color(0xFF1E6FF2); // Nanote Blue
  static const Color lightPrimaryFg = Color(0xFFFFFFFF);
  static const Color lightSecondary = Color(0xFFEEF2F8);
  static const Color lightSecondaryFg = Color(0xFF0A3A8F);
  static const Color lightMutedFg = Color(0xFF5A6B85);
  static const Color lightAccent = Color(0xFFE8F0FE);
  static const Color lightAccentFg = Color(0xFF0A3A8F);
  static const Color lightDestructive = Color(0xFFE5484D);
  static const Color lightBorder = Color(0xFFE2E8F1);
  static const Color lightRing = Color(0xFF1E6FF2);
  static const Color lightSuccess = Color(0xFF22A06B);
  static const Color lightWarning = Color(0xFFFF9F1C);
  static const Color lightSurfaceVariant = Color(0xFFEEF2F8);

  /// Nanote Blue hero gradient (cover `nanote-blue`): #2B7BFF → #1E6FF2 →
  /// #0D47C4. Used for the FAB and hero elements ONLY.
  static const List<Color> lightBrandGradient = [
    Color(0xFF2B7BFF),
    Color(0xFF1E6FF2),
    Color(0xFF0D47C4),
  ];

  // ------------------------------------------------------------------- dark
  static const Color darkBackground = Color(0xFF0E1622);
  static const Color darkForeground = Color(0xFFE8EEF7);
  static const Color darkCard = Color(0xFF16202E);
  static const Color darkPrimary = Color(0xFF6BA6FF); // Nanote Blue (dark)
  static const Color darkPrimaryFg = Color(0xFF0A2050);
  static const Color darkSecondary = Color(0xFF1C2838);
  static const Color darkSecondaryFg = Color(0xFFC9D6EA);
  static const Color darkMutedFg = Color(0xFF94A6C0);
  static const Color darkAccent = Color(0xFF1B2A44);
  static const Color darkAccentFg = Color(0xFFBAD4FF);
  static const Color darkDestructive = Color(0xFFFF6B6B);
  static const Color darkBorder = Color(0xFF24324A);
  static const Color darkRing = Color(0xFF6BA6FF);
  static const Color darkSuccess = Color(0xFF3ECF8E);
  static const Color darkWarning = Color(0xFFFFB84D);
  static const Color darkSurfaceVariant = Color(0xFF1C2838);

  static const List<Color> darkBrandGradient = [
    Color(0xFF6BA6FF),
    Color(0xFF3E86F0),
    Color(0xFF1D5AC8),
  ];
}

/// Extra named colors exposed via ThemeExtension.
@immutable
class NanoteColors extends ThemeExtension<NanoteColors> {
  /// Background of the ACTIVE item (list rows, chips).
  final Color accent;

  /// Text/icon color on [accent].
  final Color accentFg;

  /// Text on secondary surfaces.
  final Color secondaryFg;

  /// Secondary text color.
  final Color mutedFg;

  final Color success;
  final Color warning;

  /// Nanote Blue gradient for hero elements (FAB, active state wash).
  final List<Color> brandGradient;

  /// Elevated secondary surface (segmented tracks, table headers).
  final Color surfaceVariant;

  /// Focus ring color (primary).
  final Color ring;

  /// ink-1: the light soft shadow (cards, tiles).
  final List<BoxShadow> inkShadow1;

  /// ink-2: the floating shadow (popovers, rails, sheets).
  final List<BoxShadow> inkShadow2;

  const NanoteColors({
    required this.accent,
    required this.accentFg,
    required this.secondaryFg,
    required this.mutedFg,
    required this.success,
    required this.warning,
    required this.brandGradient,
    required this.surfaceVariant,
    required this.ring,
    required this.inkShadow1,
    required this.inkShadow2,
  });

  @override
  NanoteColors copyWith({
    Color? accent,
    Color? accentFg,
    Color? secondaryFg,
    Color? mutedFg,
    Color? success,
    Color? warning,
    List<Color>? brandGradient,
    Color? surfaceVariant,
    Color? ring,
    List<BoxShadow>? inkShadow1,
    List<BoxShadow>? inkShadow2,
  }) =>
      NanoteColors(
        accent: accent ?? this.accent,
        accentFg: accentFg ?? this.accentFg,
        secondaryFg: secondaryFg ?? this.secondaryFg,
        mutedFg: mutedFg ?? this.mutedFg,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        brandGradient: brandGradient ?? this.brandGradient,
        surfaceVariant: surfaceVariant ?? this.surfaceVariant,
        ring: ring ?? this.ring,
        inkShadow1: inkShadow1 ?? this.inkShadow1,
        inkShadow2: inkShadow2 ?? this.inkShadow2,
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
      brandGradient: [
        for (var i = 0; i < brandGradient.length; i++)
          Color.lerp(
            brandGradient[i],
            i < other.brandGradient.length ? other.brandGradient[i] : null,
            t,
          )!,
      ],
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
      inkShadow1:
          BoxShadow.lerpList(inkShadow1, other.inkShadow1, t) ?? inkShadow1,
      inkShadow2:
          BoxShadow.lerpList(inkShadow2, other.inkShadow2, t) ?? inkShadow2,
    );
  }
}

// ---------------------------------------------------------------------------
// Radius scale (8 / 10 / 12 / 16 — pills are fully rounded)
// ---------------------------------------------------------------------------

const double NANOTE_RADIUS_SM = 8.0;
const double NANOTE_RADIUS_MD = 10.0;

/// Base corner radius (cards, popovers, panels).
const double NANOTE_RADIUS = 12.0;

const double NANOTE_RADIUS_LG = 16.0;

// ---------------------------------------------------------------------------
// Typography helpers
// ---------------------------------------------------------------------------

/// Latin: **Inter** (with cv11 + ss01). Arabic glyphs fall through to
/// **Noto Sans Arabic**. Numbers are always tabular (equal width digits).
const String kNanoteFontFamily = 'Inter';
const List<String> kNanoteFontFallback = ['NotoSansArabic'];

const List<FontFeature> kNanoteFontFeatures = [
  FontFeature('cv11'), // single-story a
  FontFeature('ss01'), // open digits
  FontFeature.tabularFigures(),
];

/// Applies the Nanote font stack + features to [style] (identity-safe).
TextStyle nanoteText(TextStyle style) => style.copyWith(
      fontFamily: kNanoteFontFamily,
      fontFamilyFallback: kNanoteFontFallback,
      fontFeatures: kNanoteFontFeatures,
    );

TextTheme _nanoteTextTheme(TextTheme t) => t.copyWith(
      displayLarge: nanoteText(t.displayLarge!),
      displayMedium: nanoteText(t.displayMedium!),
      displaySmall: nanoteText(t.displaySmall!),
      headlineLarge: nanoteText(t.headlineLarge!),
      headlineMedium: nanoteText(t.headlineMedium!),
      headlineSmall: nanoteText(t.headlineSmall!),
      titleLarge: nanoteText(t.titleLarge!),
      titleMedium: nanoteText(t.titleMedium!),
      titleSmall: nanoteText(t.titleSmall!),
      bodyLarge: nanoteText(t.bodyLarge!),
      bodyMedium: nanoteText(t.bodyMedium!),
      bodySmall: nanoteText(t.bodySmall!),
      labelLarge: nanoteText(t.labelLarge!),
      labelMedium: nanoteText(t.labelMedium!),
      labelSmall: nanoteText(t.labelSmall!),
    );

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

class NanoteTheme {
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
        ring: NanoteTokens.lightRing,
        success: NanoteTokens.lightSuccess,
        warning: NanoteTokens.lightWarning,
        surfaceVariant: NanoteTokens.lightSurfaceVariant,
        brandGradient: NanoteTokens.lightBrandGradient,
        ink1: const [
          BoxShadow(
              offset: Offset(0, 1),
              blurRadius: 2,
              color: Color(0x14233A58)), // rgba(22,35,58,.08)
          BoxShadow(
              offset: Offset(0, 2),
              blurRadius: 8,
              color: Color(0x0F233A58)), // rgba(22,35,58,.06)
        ],
        ink2: const [
          BoxShadow(
              offset: Offset(0, 4),
              blurRadius: 12,
              color: Color(0x1A233A58)), // rgba(22,35,58,.10)
          BoxShadow(
              offset: Offset(0, 12),
              blurRadius: 32,
              color: Color(0x1A233A58)), // rgba(22,35,58,.10)
        ],
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
        ring: NanoteTokens.darkRing,
        success: NanoteTokens.darkSuccess,
        warning: NanoteTokens.darkWarning,
        surfaceVariant: NanoteTokens.darkSurfaceVariant,
        brandGradient: NanoteTokens.darkBrandGradient,
        ink1: const [
          BoxShadow(
              offset: Offset(0, 1),
              blurRadius: 2,
              color: Color(0x66000000)), // rgba(0,0,0,.4)
          BoxShadow(
              offset: Offset(0, 2),
              blurRadius: 8,
              color: Color(0x73000000)),
        ],
        ink2: const [
          BoxShadow(
              offset: Offset(0, 4),
              blurRadius: 12,
              color: Color(0x80000000)), // rgba(0,0,0,.5)
          BoxShadow(
              offset: Offset(0, 12),
              blurRadius: 32,
              color: Color(0x80000000)),
        ],
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
    required Color ring,
    required Color success,
    required Color warning,
    required Color surfaceVariant,
    required List<Color> brandGradient,
    required List<BoxShadow> ink1,
    required List<BoxShadow> ink2,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: primaryFg,
      secondary: secondary,
      onSecondary: secondaryFg,
      error: destructive,
      onError: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF2B0A0A),
      surface: card,
      onSurface: foreground,
      surfaceContainerHighest: surfaceVariant,
      outline: border,
      outlineVariant: border,
    );

    final radius = BorderRadius.circular(NANOTE_RADIUS);
    final radiusLg = BorderRadius.circular(NANOTE_RADIUS_LG);
    final pill = BorderRadius.circular(999);

    final baseText = _nanoteTextTheme(
      (brightness == Brightness.light
              ? Typography.material2021().black
              : Typography.material2021().white)
          .apply(bodyColor: foreground, displayColor: foreground),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: kNanoteFontFamily,
      fontFamilyFallback: kNanoteFontFallback,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseText,
      extensions: [
        NanoteColors(
          accent: accent,
          accentFg: accentFg,
          secondaryFg: secondaryFg,
          mutedFg: mutedFg,
          success: success,
          warning: warning,
          brandGradient: brandGradient,
          surfaceVariant: surfaceVariant,
          ring: ring,
          inkShadow1: ink1,
          inkShadow2: ink2,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: nanoteText(TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: foreground,
        )),
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
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: card,
        modalBackgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
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
        fillColor: surfaceVariant,
        hintStyle: TextStyle(color: mutedFg),
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
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          // CTA = full pill capsule.
          shape: RoundedRectangleBorder(borderRadius: pill),
          textStyle: nanoteText(
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: pill),
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
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD))),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: primaryFg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // Small dark capsule that auto-dismisses.
        backgroundColor: brightness == Brightness.light
            ? const Color(0xE6162033)
            : const Color(0xF20B111C),
        contentTextStyle: nanoteText(TextStyle(
          color: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFFE8EEF7),
          fontSize: 13.5,
        )),
        shape: RoundedRectangleBorder(borderRadius: pill),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: pill),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: mutedFg,
        dividerColor: border,
      ),
      sliderTheme: const SliderThemeData(
        // Thin ink-line track; colors come from the scheme.
        trackHeight: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: card,
        indicatorColor: accent,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(
          nanoteText(const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Convenience accessor for the NanoteColors extension.
NanoteColors nanoteColors(BuildContext context) =>
    Theme.of(context).extension<NanoteColors>()!;

// ---------------------------------------------------------------------------
// Shared micro-interactions
// ---------------------------------------------------------------------------

/// Press-scale: on touch the child shrinks to 96% for 120ms (v1.9.1 motion
/// spec). Wrap any tappable card/button.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: () => setState(() => _down = false),
      onTap: enabled ? widget.onTap : null,
      onLongPress: enabled ? widget.onLongPress : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
