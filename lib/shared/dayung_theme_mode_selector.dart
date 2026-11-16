import 'package:capstone_app/Providers/apptheme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DayungThemeModeSelector extends StatelessWidget {
  const DayungThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppTheme>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appearance',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose Light, Dark, or follow your device setting.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ThemeModeChoice(
              mode: ThemeMode.system,
              label: 'System',
              icon: Icons.brightness_auto_rounded,
              selected: appTheme.mode == ThemeMode.system,
            ),
            _ThemeModeChoice(
              mode: ThemeMode.light,
              label: 'Light',
              icon: Icons.light_mode_rounded,
              selected: appTheme.mode == ThemeMode.light,
            ),
            _ThemeModeChoice(
              mode: ThemeMode.dark,
              label: 'Dark',
              icon: Icons.dark_mode_rounded,
              selected: appTheme.mode == ThemeMode.dark,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Current mode: ${_modeLabel(appTheme.mode)}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _modeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
  }
}

class _ThemeModeChoice extends StatelessWidget {
  const _ThemeModeChoice({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
  });

  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 20),
      label: Text(label),
      selected: selected,
      onSelected: (_) => context.read<AppTheme>().set(mode),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }
}
