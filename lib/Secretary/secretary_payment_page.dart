import 'package:capstone_app/pages/official_payment_page.dart';
import 'package:flutter/material.dart';

class SecretaryPaymentPage extends StatelessWidget {
  final int dayungUnitId;

  const SecretaryPaymentPage({super.key, required this.dayungUnitId});

  @override
  Widget build(BuildContext context) {
    return OfficialPaymentPage(
      dayungUnitId: dayungUnitId,
      roleTitle: 'Secretary Payment',
      roleSubtitle: 'Review and settle your own pending contribution records.',
    );
  }
}
