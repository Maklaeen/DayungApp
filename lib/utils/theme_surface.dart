import 'package:flutter/material.dart';

bool dayungIsDark(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark;
}

Color dayungPageBackground(BuildContext context) {
  return Theme.of(context).scaffoldBackgroundColor;
}

Color dayungSurface(BuildContext context) {
  return dayungIsDark(context) ? const Color(0xFF162033) : Colors.white;
}

Color dayungSoftSurface(BuildContext context) {
  return dayungIsDark(context)
      ? const Color(0xFF1B2435)
      : const Color(0xFFF8FAFC);
}

Color dayungBorder(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return dayungIsDark(context)
      ? colorScheme.outline.withValues(alpha: 0.34)
      : const Color(0xFFE5E7EB);
}

Color dayungTextColor(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface;
}

Color dayungSubtextColor(BuildContext context) {
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

Color dayungAccentSurface(
  BuildContext context,
  Color accent, {
  double lightAlpha = 0.10,
  double darkAlpha = 0.18,
}) {
  final alpha = dayungIsDark(context) ? darkAlpha : lightAlpha;
  return Color.alphaBlend(
    accent.withValues(alpha: alpha),
    dayungSoftSurface(context),
  );
}

BoxShadow dayungElevatedShadow(BuildContext context) {
  return BoxShadow(
    color: Colors.black.withValues(alpha: dayungIsDark(context) ? 0.24 : 0.08),
    blurRadius: 20,
    offset: const Offset(0, 8),
  );
}

BoxShadow dayungTopShadow(BuildContext context) {
  return BoxShadow(
    color: Colors.black.withValues(alpha: dayungIsDark(context) ? 0.24 : 0.10),
    blurRadius: 20,
    offset: const Offset(0, -4),
  );
}

BoxDecoration dayungSectionCardDecoration(
  BuildContext context, {
  double radius = 20,
}) {
  return BoxDecoration(
    color: dayungSurface(context),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: dayungBorder(context)),
    boxShadow: [dayungElevatedShadow(context)],
  );
}

BoxDecoration dayungAccentCardDecoration(
  BuildContext context, {
  required Color accent,
  double radius = 16,
  double lightAlpha = 0.10,
  double darkAlpha = 0.18,
}) {
  return BoxDecoration(
    color: dayungAccentSurface(
      context,
      accent,
      lightAlpha: lightAlpha,
      darkAlpha: darkAlpha,
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: accent.withValues(alpha: dayungIsDark(context) ? 0.34 : 0.20),
    ),
  );
}

LinearGradient dayungDashboardGradient(BuildContext context) {
  final background = dayungPageBackground(context);
  if (dayungIsDark(context)) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [const Color(0xFF1D4ED8), const Color(0xFF0F172A), background],
      stops: const [0.0, 0.28, 0.48],
    );
  }

  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [const Color(0xFF1E40AF), const Color(0xFF3B82F6), background],
    stops: const [0.0, 0.3, 0.3],
  );
}
