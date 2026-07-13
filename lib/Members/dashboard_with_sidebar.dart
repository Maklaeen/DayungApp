import 'package:flutter/material.dart';
import 'package:capstone_app/widgets/shared_sidebar_layout.dart';
import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';

class MemberDashboardEntry extends StatelessWidget {
  const MemberDashboardEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return SharedSidebarLayout(
      currentPage: 'dashboard',
      roleName: 'Member',
      navigationItems: [
        SidebarNavItem(
          icon: Icons.dashboard_rounded,
          label: 'Dashboard',
          pageKey: 'dashboard',
          page: const MemberDashboardPage(),
          color: const Color(0xFF3B82F6),
        ),
        SidebarNavItem(
          icon: Icons.account_circle_rounded,
          label: 'Profile',
          pageKey: 'profile',
          page: const ProfilePage(),
          color: const Color(0xFF10B981),
        ),
        SidebarNavItem(
          icon: Icons.people_rounded,
          label: 'Beneficiaries',
          pageKey: 'beneficiaries',
          page: const BeneficiaryPage(),
          color: const Color(0xFF8B5CF6),
        ),
      ],
      child: const MemberDashboardPage(),
    );
  }
}
