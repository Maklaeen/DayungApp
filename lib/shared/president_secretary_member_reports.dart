import 'package:flutter/material.dart';

class PresidentSecretaryMemberReports extends StatelessWidget {
  final int addedMembers;
  final int removedMembers;
  final int deceasedMembers;
  final int deceasedBeneficiaries;

  const PresidentSecretaryMemberReports({
    super.key,
    required this.addedMembers,
    required this.removedMembers,
    required this.deceasedMembers,
    required this.deceasedBeneficiaries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, color: colors.primary),
              SizedBox(width: 10),
              Text(
                'Membership Activity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 4 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric(
                    width: width,
                    label: 'Members added',
                    value: addedMembers,
                    icon: Icons.person_add_alt_1_rounded,
                    color: const Color(0xFF059669),
                    labelColor: colors.onSurfaceVariant,
                  ),
                  _metric(
                    width: width,
                    label: 'Members removed',
                    value: removedMembers,
                    icon: Icons.person_remove_alt_1_rounded,
                    color: const Color(0xFFDC2626),
                    labelColor: colors.onSurfaceVariant,
                  ),
                  _metric(
                    width: width,
                    label: 'Members deceased',
                    value: deceasedMembers,
                    icon: Icons.person_off_rounded,
                    color: const Color(0xFF7C3AED),
                    labelColor: colors.onSurfaceVariant,
                  ),
                  _metric(
                    width: width,
                    label: 'Beneficiaries deceased',
                    value: deceasedBeneficiaries,
                    icon: Icons.family_restroom_rounded,
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFD97706),
                    labelColor: colors.onSurfaceVariant,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _metric({
    required double width,
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required Color labelColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Montserrat',
                  ),
                ),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'OpenSans',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
