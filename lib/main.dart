import 'package:capstone_app/Admin/dashboard.dart';
import 'package:capstone_app/Collector/dashboard.dart';
import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/President/dashboard.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Providers/route_observer.dart';
import 'package:capstone_app/Providers/user_provider.dart';
import 'package:capstone_app/Secretary/dashboard.dart';
import 'package:capstone_app/Treasurer/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/settings/custom_scroll_behavior.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';
import 'Auth/login.dart';
import 'Auth/register.dart';
import 'Auth/reapply.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cbplyfoporianakushyz.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNicGx5Zm9wb3JpYW5ha3VzaHl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA3Mzk5OTAsImV4cCI6MjA2NjMxNTk5MH0.6xtt3Ajrs0j_Zo-wLuTpTut-Qi0DEg_vxvXkLWsBXgw',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (_) => DayungUnitProvider()..loadDayungUnit(),
        ),
        ChangeNotifierProxyProvider<DayungUnitProvider, DayungRoleProvider>(
          create: (_) => DayungRoleProvider(),
          update: (context, unitProv, roleProv) {
            roleProv ??= DayungRoleProvider();
            final newId = unitProv.currentUnitId;
            if (newId != roleProv.unitId) {
              roleProv.refreshRoles(newId);
            }
            return roleProv;
          },
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        scrollBehavior: NoGlowScrollBehavior(),
        title: 'Dayung',
        navigatorObservers: [appRouteObserver],
        initialRoute: '/',
        routes: {
          '/': (context) => SplashScreen(),
          '/login': (context) => Login(),
          '/register': (context) => Register(),
          '/reapply': (context) => Reapply(),
          '/dashboard': (context) => MemberDashboardPage(),
          '/president-dashboard': (context) => PresidentDashboardPage(),
          '/secretary-dashboard': (context) => SecretaryDashboardPage(),
          '/treasurer-dashboard': (context) => TreasurerDashboardPage(),
          '/collector-dashboard': (context) => CollectorDashboardPage(),
          '/admin-dashboard': (context) => AdminDashboardPage(),
        },
      ),
    );
  }
}
