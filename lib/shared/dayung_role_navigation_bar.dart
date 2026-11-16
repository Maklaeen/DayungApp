import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';

class DayungRoleNavigationBar extends StatelessWidget {
  const DayungRoleNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = [
    (icon: Icons.dashboard_rounded, label: 'Dashboard'),
    (icon: Icons.trending_up_rounded, label: 'Contributions'),
    (icon: Icons.assignment_rounded, label: 'Claims'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Main navigation',
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: dayungSurface(context),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: dayungBorder(context)),
          boxShadow: [dayungElevatedShadow(context)],
        ),
        child: Row(
          children: [
            for (var index = 0; index < _destinations.length; index++)
              Expanded(
                child: _NavigationDestination(
                  icon: _destinations[index].icon,
                  label: _destinations[index].label,
                  selected: selectedIndex == index,
                  selectedColor: colors.primary,
                  unselectedColor: colors.onSurfaceVariant,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? selectedColor.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? Border.all(color: selectedColor.withValues(alpha: 0.28))
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: color),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
