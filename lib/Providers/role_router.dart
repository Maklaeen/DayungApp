import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/Secretary/dashboard.dart';
import 'package:capstone_app/President/dashboard.dart';
import 'package:capstone_app/Treasurer/dashboard.dart';
import 'package:capstone_app/Collector/dashboard.dart';
import 'package:capstone_app/SuperAdmin/dashboard.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/widgets/global_sidebar_wrapper.dart';

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final roles = context.watch<DayungRoleProvider>();

    if (roles.loading) {
      return const DayungLoadingScaffold(layout: DayungSkeletonLayout.dashboard);
    }

    // SuperAdmin has its own layout, no sidebar needed
    if (roles.isSuperAdmin) return const SuperAdminDashboardPage();

    final Widget dashboard;
    if (roles.isPresident) {
      dashboard = const PresidentDashboardPage();
    } else if (roles.isSecretary) {
      dashboard = const SecretaryDashboardPage();
    } else if (roles.isTreasurer) {
      dashboard = const TreasurerDashboardPage();
    } else if (roles.isCollector) {
      dashboard = const CollectorDashboardPage();
    } else {
      dashboard = const MemberDashboardPage();
    }

    return GlobalSidebarWrapper(dashboard: dashboard);
  }
}
