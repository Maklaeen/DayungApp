import 'package:flutter/material.dart';

class DayungMapAttribution extends StatelessWidget {
  const DayungMapAttribution({
    super.key,
    this.alignment = Alignment.bottomRight,
  });

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.fromLTRB(6, 0, 6, 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '© OpenStreetMap contributors',
            style: TextStyle(
              color: Color(0xB34B5563),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
