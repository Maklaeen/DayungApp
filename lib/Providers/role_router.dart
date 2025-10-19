import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Members/dashboard.dart' as member;
import 'package:capstone_app/Secretary/dashboard.dart' as sec;
import 'package:capstone_app/President/dashboard.dart' as pres;
import 'package:capstone_app/Treasurer/dashboard.dart' as treas;
import 'package:capstone_app/Collector/dashboard.dart' as coll;

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DayungRoleProvider>(
      builder: (_, roles, __) {
        // While provider is resolving roles, show a small splash/loader
        if (roles.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (roles.isPresident) return const pres.PresidentDashboardPage();
        if (roles.isSecretary) return const sec.SecretaryDashboardPage();
        if (roles.isTreasurer) return const treas.TreasurerDashboardPage();
        if (roles.isCollector) return const coll.CollectorDashboardPage();
        return const member.MemberDashboardPage();
      },
    );
  }
}