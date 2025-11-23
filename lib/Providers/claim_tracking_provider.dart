import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:capstone_app/ui/theme/branding.dart';

class ClaimTrackingData {
  final List<String> steps;
  final int currentIndex;
  final bool rejected;
  final String helperText;
  ClaimTrackingData({
    required this.steps,
    required this.currentIndex,
    required this.rejected,
    required this.helperText,
  });
}

final claimTrackingProvider = Provider.family<ClaimTrackingData, String>((
  ref,
  rawStatus,
) {
  final low = rawStatus.toLowerCase();
  const steps = ['Pending', 'Approved', 'Claimed'];

  if (low == 'rejected') {
    return ClaimTrackingData(
      steps: steps,
      currentIndex: -1,
      rejected: true,
      helperText: 'This claim was rejected.',
    );
  }

  final idx = switch (low) {
    'pending' => 0,
    'approved' => 1,
    'claimed' => 2,
    _ => 0,
  };

  final helper = switch (low) {
    'claimed' => 'Funds already claimed.',
    'approved' => 'Approved. Awaiting fund release / claiming.',
    'pending' => 'Under review.',
    _ => '',
  };

  return ClaimTrackingData(
    steps: steps,
    currentIndex: idx,
    rejected: false,
    helperText: helper,
  );
});

Color trackingStepColor(String status, int currentIndex, int i) {
  final low = status.toLowerCase();
  if (low == 'rejected') return kDanger;
  if (i < currentIndex) return kAccent;
  if (i == currentIndex) {
    return low == 'pending' ? kWarn : kAccent;
  }
  return Colors.grey.shade400;
}

IconData trackingStepIcon(String status, int currentIndex, int i) {
  final low = status.toLowerCase();
  if (low == 'rejected') return Icons.cancel;
  if (i < currentIndex) return Icons.check_circle;
  if (i == currentIndex) {
    return switch (low) {
      'pending' => Icons.hourglass_bottom,
      'approved' => Icons.check_circle,
      'claimed' => Icons.task_alt,
      _ => Icons.radio_button_unchecked,
    };
  }
  return Icons.radio_button_unchecked;
}
