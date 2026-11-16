import 'dart:async';

import 'package:capstone_app/Auth/pin_lock_page.dart';
import 'package:capstone_app/Auth/pin_service.dart';
import 'package:capstone_app/Providers/role_router.dart';
import 'package:capstone_app/Secretary/dashboard.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/env.dart';
import 'package:capstone_app/Auth/auth_redirects.dart';
import 'package:capstone_app/Auth/password_recovery_page.dart';
import 'package:capstone_app/Collector/dashboard.dart';
import 'package:capstone_app/President/dashboard.dart';
import 'package:capstone_app/Providers/apptheme_provider.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Providers/route_observer.dart';
import 'package:capstone_app/Providers/user_provider.dart';
import 'package:capstone_app/SuperAdmin/dashboard.dart';
import 'package:capstone_app/Treasurer/dashboard.dart';
import 'package:capstone_app/services/firebase_push_service.dart';
import 'package:capstone_app/services/push_notification_service.dart';
import 'package:capstone_app/settings/custom_scroll_behavior.dart';
import 'package:capstone_app/ui/theme/dayung_theme.dart';
import 'package:capstone_app/utils/network_error_dialog.dart';
import 'config/app_config.dart';
import 'package:flutter/material.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();

  String supabaseUrl = '';
  String supabaseAnonKey = '';

  // Try to use Env class (for web), fallback to dotenv for other platforms
  supabaseUrl = Env.supabaseUrl;
  supabaseAnonKey = Env.supabaseAnonKey;

  // If still placeholders, try dotenv (for mobile/desktop)
  if (supabaseUrl == '  YOUR_SUPABASE_URL' ||
      supabaseAnonKey == 'YOUR_SUPABASE_ANON_KEY') {
    await dotenv.load(fileName: '.env');
    supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  }

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError('Missing SUPABASE_URL or SUPABASE_ANON_KEY');
  }

  final appTheme = AppTheme();
  await appTheme.load();

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  await PushNotificationService.instance.initialize(
    navigatorKey: globalNavigatorKey,
    onTap: (payload) {
      if (payload != null) {
        debugPrint('Notification tapped with payload: $payload');
      }
    },
  );
  unawaited(FirebasePushService.instance.initialize());

  runApp(ProviderScope(child: MyApp(appTheme: appTheme)));
}

class AppSetupRequiredApp extends StatelessWidget {
  final AppTheme appTheme;
  final List<String> missingKeys;

  const AppSetupRequiredApp({
    super.key,
    required this.appTheme,
    required this.missingKeys,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appTheme,
      child: Builder(
        builder: (context) {
          final appTheme = context.watch<AppTheme>();
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Dayung Setup Required',
            theme: buildDayungTheme(Brightness.light),
            darkTheme: buildDayungTheme(Brightness.dark),
            themeMode: appTheme.mode,
            home: _SetupRequiredScreen(missingKeys: missingKeys),
          );
        },
      ),
    );
  }
}

class _SetupRequiredScreen extends StatelessWidget {
  final List<String> missingKeys;

  const _SetupRequiredScreen({required this.missingKeys});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [
                    Color(0xFF0F172A),
                    Color(0xFF111827),
                    Color(0xFF1E293B),
                  ]
                : const [
                    Color(0xFFEFF6FF),
                    Color(0xFFF8FAFC),
                    Color(0xFFDBEAFE),
                  ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Setup required before Dayung can connect',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The app started correctly, but this machine is missing the config values needed to connect to Supabase.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Missing values:',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: missingKeys
                            .map(
                              (key) => Chip(
                                label: Text(key),
                                avatar: const Icon(Icons.key_rounded, size: 18),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Option 1: create a local .env file in the project root',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        'SUPABASE_URL=https://your-project.supabase.co\nSUPABASE_ANON_KEY=your_supabase_anon_key\nOPENROUTESERVICE_API_KEY=your_openrouteservice_api_key',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Option 2: run with --dart-define values',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        'flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key --dart-define=OPENROUTESERVICE_API_KEY=your_openrouteservice_api_key',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'After adding the values, stop the current run and launch the app again.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    return MultiProvider(
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
          final appTheme = context.watch<AppTheme>();
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
            theme: buildDayungTheme(Brightness.light),
            darkTheme: buildDayungTheme(Brightness.dark),
            themeMode: appTheme.mode,
            themeAnimationDuration: const Duration(milliseconds: 400),
            initialRoute: '/',
            routes: {
              '/': (context) => const _AuthGate(),
              '/splash': (context) => const SplashScreen(),
              '/role-router': (context) => const RoleRouter(),
              '/login': (context) => Login(),
              '/register': (context) => Register(),
              kPasswordRecoveryRoute: (context) => const PasswordRecoveryPage(),
              '/reapply': (context) => Reapply(),
              '/dashboard': (context) => const RoleRouter(),
              '/president-dashboard': (context) => PresidentDashboardPage(),
              '/secretary-dashboard': (context) =>
                  const SecretaryDashboardPage(),
              '/treasurer-dashboard': (context) => TreasurerDashboardPage(),
              '/collector-dashboard': (context) => CollectorDashboardPage(),
              '/superadmin-dashboard': (context) => SuperAdminDashboardPage(),
            },
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final StreamSubscription<AuthState> _sub;

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.initialSession) {
        if (data.session != null) {
          await context.read<DayungUnitProvider>().loadDayungUnit();
          if (!mounted) return;
          final uid = data.session!.user.id;
          final hasPin = await PinService.hasPin(uid);
          if (!mounted) return;
          if (hasPin) {
            final unlocked = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const PinLockPage()),
            );
            if (!mounted) return;
            if (unlocked == true) {
              Navigator.pushReplacementNamed(context, '/role-router');
            } else {
              // Forgot PIN — clear session and go to login
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            }
          } else {
            Navigator.pushReplacementNamed(context, '/role-router');
          }
        } else {
          Navigator.pushReplacementNamed(context, '/splash');
        }
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
