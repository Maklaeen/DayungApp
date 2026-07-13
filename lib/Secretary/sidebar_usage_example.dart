import 'package:capstone_app/Secretary/sidebar_layout.dart';
import 'package:capstone_app/Secretary/dashboard.dart';
import 'package:flutter/material.dart';

// Example of using pushReplacement with SidebarLayout for desktop persistent sidebar
void navigateToMainDashboard(BuildContext context) {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => const SidebarLayout(
        currentPage: 'dashboard',
        child: SecretaryDashboardPage(),
      ),
    ),
  );
}

// Example of using push for temporary navigation (will return to previous page)
void navigateToOtherPage(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const SidebarLayout(
        currentPage: 'profile',
        child: SecretaryDashboardPage(), // Replace with actual page
      ),
    ),
  );
}