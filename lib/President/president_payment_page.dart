import 'package:capstone_app/pages/official_payment_page.dart';
import 'package:flutter/material.dart';

class PresidentPaymentPage extends StatelessWidget {
  final int dayungUnitId;

  const PresidentPaymentPage({super.key, required this.dayungUnitId});

  @override
  Widget build(BuildContext context) {
    return OfficialPaymentPage(
      dayungUnitId: dayungUnitId,
      roleTitle: 'President Payment',
      roleSubtitle: 'Review and settle your own pending contribution records.',
    );
  }
}
