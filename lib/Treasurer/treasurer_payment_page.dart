import 'package:capstone_app/pages/official_payment_page.dart';
import 'package:flutter/material.dart';

class TreasurerPaymentPage extends StatefulWidget {
  final int dayungUnitId;

  const TreasurerPaymentPage({super.key, required this.dayungUnitId});

  @override
  State<TreasurerPaymentPage> createState() => _TreasurerPaymentPageState();
}

class _TreasurerPaymentPageState extends State<TreasurerPaymentPage> {
  @override
  Widget build(BuildContext context) {
    return OfficialPaymentPage(
      dayungUnitId: widget.dayungUnitId,
      roleTitle: 'Treasurer Payment',
      roleSubtitle: 'Review and settle your own pending contribution records.',
    );
  }
} 