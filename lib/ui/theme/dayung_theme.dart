import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';

ThemeData buildDayungTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final seededScheme = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: brightness,
  );
  const darkOnSurface = Color(0xFF0F172A);
  final colors = seededScheme.copyWith(
    primary: isDark ? const Color(0xFF90CAF9) : kPrimary,
    onPrimary: isDark ? darkOnSurface : Colors.white,
    secondary: isDark ? const Color(0xFF81C784) : kAccent,
    onSecondary: isDark ? darkOnSurface : Colors.white,
    tertiary: isDark ? const Color(0xFF90CAF9) : kInfo,
    onTertiary: isDark ? darkOnSurface : Colors.white,
    error: isDark ? const Color(0xFFFF8A80) : kDanger,
    onError: isDark ? darkOnSurface : Colors.white,
    surface: isDark ? kDarkSurface : kSurface,
    onSurface: isDark ? const Color(0xFFF8FAFC) : kNeutralText,
    onSurfaceVariant: isDark ? const Color(0xFFD1D5DB) : kSubtleText,
    outline: isDark ? kDarkBorder : kBorder,
    outlineVariant: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: isDark ? kDarkBackground : kBg,
    visualDensity: VisualDensity.standard,
  );
  final outlineColor = isDark ? kDarkBorder : kBorder;
  final textTheme = base.textTheme
      .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface)
      .copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        displayMedium: base.textTheme.displayMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 18,
          height: 1.5,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 16,
          height: 1.45,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 14,
          height: 1.4,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      );

  return base.copyWith(
    canvasColor: isDark ? kDarkBackground : kSurface,
    cardColor: isDark ? kDarkSurface : kSurface,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colors.onSurface,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 72,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.onSurface),
    ),
    cardTheme: CardThemeData(
      color: isDark ? kDarkSurface : kSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? kDarkSurface : kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? kDarkSurface : kSurface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? kDarkSurface : kSurface,
      surfaceTintColor: Colors.transparent,
      textStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outlineColor),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: isDark ? kDarkBackground : kSurface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? kDarkSoftSurface : kSurface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: TextStyle(color: colors.onSurfaceVariant),
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
      prefixIconColor: colors.primary,
      suffixIconColor: colors.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: outlineColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: outlineColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.primary, width: 1.8),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        side: BorderSide(color: outlineColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? kDarkBackground : kSurface,
      indicatorColor: colors.primary.withValues(alpha: isDark ? 0.28 : 0.14),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.selected)
            ? colors.primary
            : colors.onSurfaceVariant;
        return textTheme.labelMedium?.copyWith(color: color);
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.primary,
      textColor: colors.onSurface,
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      titleTextStyle: textTheme.bodyLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    checkboxTheme: const CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    radioTheme: const RadioThemeData(
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: isDark ? kDarkSoftSurface : const Color(0xFFEFF4FF),
      selectedColor: colors.primary.withValues(alpha: 0.16),
      labelStyle: TextStyle(color: colors.onSurface),
      side: BorderSide(color: outlineColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    dividerTheme: DividerThemeData(color: outlineColor, thickness: 1, space: 1),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(
        isDark ? colors.surfaceContainerHigh : colors.primaryContainer,
      ),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return colors.primary.withValues(alpha: 0.06);
        }
        return colors.surface;
      }),
      headingTextStyle: textTheme.labelLarge?.copyWith(
        color: isDark ? colors.onSurface : colors.onPrimaryContainer,
        fontWeight: FontWeight.w700,
      ),
      dataTextStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
      dividerThickness: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.surfaceContainerHighest,
      circularTrackColor: colors.surfaceContainerHighest,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF1E293B) : kDarkBackground,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(outlineColor),
    ),
  );
}
