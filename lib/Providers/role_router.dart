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
import 'package:supabase_flutter/supabase_flutter.dart';

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  Future<bool>? _hasNoBeneficiaries;

  Future<bool> _checkBeneficiaries() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    final rows = await Supabase.instance.client
        .from('beneficiaries')
        .select('id')
        .eq('user_id', userId)
        .limit(1);
    return (rows as List).isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final roles = context.watch<DayungRoleProvider>();

    if (roles.loading) {
      return const DayungLoadingScaffold(
        layout: DayungSkeletonLayout.dashboard,
      );
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

    if (!roles.isPresident &&
        !roles.isSecretary &&
        !roles.isTreasurer &&
        !roles.isCollector) {
      _hasNoBeneficiaries ??= _checkBeneficiaries();
      return FutureBuilder<bool>(
        future: _hasNoBeneficiaries,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const DayungLoadingScaffold(
              layout: DayungSkeletonLayout.dashboard,
            );
          }
          return GlobalSidebarWrapper(
            dashboard: dashboard,
            openBeneficiariesInitially: snapshot.data!,
          );
        },
      );
    }

    return GlobalSidebarWrapper(dashboard: dashboard);
  }
}
