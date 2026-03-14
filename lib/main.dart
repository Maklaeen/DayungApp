import 'dart:async';

import 'package:capstone_app/Auth/auth_redirects.dart';
import 'package:capstone_app/Auth/idle_timeout_manage.dart';
import 'package:capstone_app/Auth/password_recovery_page.dart';
import 'package:capstone_app/Collector/dashboard.dart';
import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/President/dashboard.dart';
import 'package:capstone_app/Providers/apptheme_provider.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Providers/route_observer.dart';
import 'package:capstone_app/Providers/user_provider.dart';
import 'package:capstone_app/Secretary/dashboard.dart';
import 'package:capstone_app/SuperAdmin/dashboard.dart';
import 'package:capstone_app/Treasurer/dashboard.dart';
import 'package:capstone_app/settings/custom_scroll_behavior.dart';
import 'package:capstone_app/utils/network_error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'Auth/login.dart';
import 'Auth/reapply.dart';
import 'Auth/register.dart';
import 'screens/splash_screen.dart';

final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null ||
      supabaseUrl.isEmpty ||
      supabaseAnonKey == null ||
      supabaseAnonKey.isEmpty) {
    throw StateError('Missing SUPABASE_URL or SUPABASE_ANON_KEY');
  }

  final appTheme = AppTheme();
  await appTheme.load();

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(ProviderScope(child: MyApp(appTheme: appTheme)));
}

class MyApp extends StatefulWidget {
  final AppTheme appTheme;
  const MyApp({super.key, required this.appTheme});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StreamSubscription<AuthState> _authSubscription;
  bool _passwordRecoveryOpen = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (data.event == AuthChangeEvent.signedOut) {
        unawaited(_clearSessionScopedDayungState());
      }
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _openPasswordRecoveryPage();
      }
    });
  }

  Future<void> _clearSessionScopedDayungState() async {
    final currentContext = globalNavigatorKey.currentContext;
    final dayungUnitProvider = currentContext?.read<DayungUnitProvider>();
    final dayungRoleProvider = currentContext?.read<DayungRoleProvider>();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');
    await prefs.remove('selectedDayungUnitData');
    await prefs.remove('selectedDayungUnitOwnerId');
    if (!mounted) {
      return;
    }

    if (dayungUnitProvider == null || dayungRoleProvider == null) {
      return;
    }

    await dayungUnitProvider.clear();
    dayungRoleProvider.clear();
  }

  void _openPasswordRecoveryPage() {
    if (_passwordRecoveryOpen) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = globalNavigatorKey.currentState;
      if (!mounted || navigator == null) {
        return;
      }

      _passwordRecoveryOpen = true;
      await navigator.pushNamedAndRemoveUntil(
        kPasswordRecoveryRoute,
        (route) => false,
      );
      if (mounted) {
        _passwordRecoveryOpen = false;
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => IdleTimeoutManager().reset(),
      onPointerMove: (_) => IdleTimeoutManager().reset(),
      onPointerUp: (_) => IdleTimeoutManager().reset(),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: widget.appTheme),
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
        child: Builder(
          builder: (context) {
            final mode = context.watch<AppTheme>().mode;

            return MaterialApp(
              navigatorKey: globalNavigatorKey,
              debugShowCheckedModeBanner: false,
              scrollBehavior: NoGlowScrollBehavior(),
              title: 'Dayung',
              navigatorObservers: [appRouteObserver],
              builder: (context, child) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  NetworkMonitor().start();
                });
                return child!;
              },
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF3B82F6),
                  brightness: Brightness.light,
                ),
                scaffoldBackgroundColor: const Color(0xFFF8FAFC),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF3B82F6),
                  brightness: Brightness.dark,
                ),
                scaffoldBackgroundColor: const Color(0xFF18181B),
              ),
              themeMode: mode,
              themeAnimationDuration: const Duration(milliseconds: 400),
              initialRoute: '/',
              routes: {
                '/': (context) => SplashScreen(),
                '/login': (context) => Login(),
                '/register': (context) => Register(),
                kPasswordRecoveryRoute: (context) =>
                    const PasswordRecoveryPage(),
                '/reapply': (context) => Reapply(),
                '/dashboard': (context) => MemberDashboardPage(),
                '/president-dashboard': (context) => PresidentDashboardPage(),
                '/secretary-dashboard': (context) => SecretaryDashboardPage(),
                '/treasurer-dashboard': (context) => TreasurerDashboardPage(),
                '/collector-dashboard': (context) => CollectorDashboardPage(),
                '/superadmin-dashboard': (context) => SuperAdminDashboardPage(),
              },
            );
          },
        ),
      ),
    );
  }
}
