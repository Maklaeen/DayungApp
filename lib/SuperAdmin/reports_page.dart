import 'package:flutter/material.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);

class SuperAdminReportsPage extends StatelessWidget {
  const SuperAdminReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: themeBg,
      appBar: AppBar(
        title: const Text('System Reports'),
        backgroundColor: kPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Reports',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kPrimary,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: kCardBg,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            child: ListTile(
              leading: Container(
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.bar_chart, color: kPrimary),
              ),
              title: const Text(
                'User Growth',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'See how your user base is growing.',
                style: TextStyle(fontSize: 13, color: kSubText),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: kSubText,
              ),
              onTap: () {
                // TODO: Navigate to user growth report
              },
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: kCardBg,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            child: ListTile(
              leading: Container(
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.pie_chart, color: Colors.orange),
              ),
              title: const Text(
                'Active vs Inactive Users',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Breakdown of user activity.',
                style: TextStyle(fontSize: 13, color: kSubText),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: kSubText,
              ),
              onTap: () {
                // TODO: Navigate to activity report
              },
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
