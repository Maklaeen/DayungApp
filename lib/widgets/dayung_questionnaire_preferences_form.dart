import 'package:capstone_app/utils/dayung_service_tags.dart';
import 'package:flutter/material.dart';

class DayungQuestionnairePreferencesForm extends StatelessWidget {
  const DayungQuestionnairePreferencesForm({
    super.key,
    required this.meetingFrequency,
    required this.paymentMethod,
    required this.contributionAmount,
    required this.membershipPayment,
    required this.penaltyPayment,
    required this.serviceTags,
    required this.onMeetingFrequencyChanged,
    required this.onPaymentMethodChanged,
    required this.onContributionAmountChanged,
    required this.onMembershipPaymentChanged,
    required this.onPenaltyPaymentChanged,
    required this.onServiceTagChanged,
  });

  final String? meetingFrequency;
  final String? paymentMethod;
  final String? contributionAmount;
  final String? membershipPayment;
  final String? penaltyPayment;
  final Map<String, bool> serviceTags;
  final ValueChanged<String?> onMeetingFrequencyChanged;
  final ValueChanged<String?> onPaymentMethodChanged;
  final ValueChanged<String?> onContributionAmountChanged;
  final ValueChanged<String?> onMembershipPaymentChanged;
  final ValueChanged<String?> onPenaltyPaymentChanged;
  final void Function(String label, bool selected) onServiceTagChanged;

  static const _feeRanges = [
    '50-100',
    '100-150',
    '150-200',
    '200-250',
    '250-300',
    '300-350',
    '400 plus',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildDropdown(
          context: context,
          label: 'Meeting Frequency',
          items: const ['Weekly', 'Monthly', 'Needed'],
          value: meetingFrequency,
          onChanged: onMeetingFrequencyChanged,
        ),
        _buildDropdown(
          context: context,
          label: 'Payment Method',
          items: const ['Cash', 'GCash', 'Both'],
          value: paymentMethod,
          onChanged: onPaymentMethodChanged,
        ),
        _buildDropdown(
          context: context,
          label: 'Collection Fee',
          items: _feeRanges,
          value: contributionAmount,
          onChanged: onContributionAmountChanged,
        ),
        _buildDropdown(
          context: context,
          label: 'Membership Payment',
          items: _feeRanges,
          value: membershipPayment,
          onChanged: onMembershipPaymentChanged,
        ),
        _buildDropdown(
          context: context,
          label: 'Penalty Payment',
          items: _feeRanges,
          value: penaltyPayment,
          onChanged: onPenaltyPaymentChanged,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Preferred Support Services',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Select the support services you want.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: dayungServiceTagLabels.map((label) {
            return FilterChip(
              label: Text(label),
              selected: serviceTags[label] ?? false,
              onSelected: (selected) => onServiceTagChanged(label, selected),
              side: BorderSide(color: colors.outlineVariant),
              selectedColor: colors.primaryContainer,
              checkmarkColor: colors.primary,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required BuildContext context,
    required String label,
    required List<String> items,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        hint: Text('Select $label'),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Theme.of(context).inputDecorationTheme.fillColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
