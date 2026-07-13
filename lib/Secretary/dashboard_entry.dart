import 'package:flutter/material.dart';
import 'package:capstone_app/Secretary/sidebar_layout.dart';
import 'package:capstone_app/Secretary/dashboard.dart';

class SecretaryDashboardEntry extends StatelessWidget {
  const SecretaryDashboardEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return const SidebarLayout(
      currentPage: 'dashboard',
      child: SecretaryDashboardPage(),
    );
  }
}
