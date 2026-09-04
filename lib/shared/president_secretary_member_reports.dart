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
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF111827)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'UPDATED SA MEMBERS REPORTS',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
          ),
          _reportRow('Members added', addedMembers.toString()),
          _reportRow('Members removed', removedMembers.toString()),
          _reportRow('Members who died', deceasedMembers.toString()),
          _reportRow(
            'Beneficiaries who died',
            deceasedBeneficiaries.toString(),
          ),
          Container(
            color: const Color(0xFFFFFF00),
            padding: const EdgeInsets.all(8),
            child: const Text(
              'NOTES: SEPARATE ANG MAG CREATE UG ACCOUNT SA APP UG MAG APPLY UG MEMBERSHIP SA DAYUNG. SA PAG APPLY SA DAYUNG, DAPAT MALAGAY ANG LISTAHAN SA BENEFICIARY BAGO I-ACCEPT.',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ),
        Container(
          width: 72,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFF111827))),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ],
    );
  }
}
