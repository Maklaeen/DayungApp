import 'dart:async';

import 'package:capstone_app/Auth/pin_lock_page.dart';
import 'package:capstone_app/Auth/pin_service.dart';
import 'package:capstone_app/Providers/role_router.dart';
import 'package:capstone_app/Secretary/dashboard.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/env.dart';
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
import 'package:capstone_app/SuperAdmin/dashboard.dart';
import 'package:capstone_app/Treasurer/dashboard.dart';
import 'package:capstone_app/services/firebase_push_service.dart';
import 'package:capstone_app/services/push_notification_service.dart';
import 'package:capstone_app/settings/custom_scroll_behavior.dart';
import 'package:capstone_app/utils/network_error_dialog.dart';
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

ThemeData _buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: brightness,
    ),
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF6F8FC),
  );
  final colors = base.colorScheme;
  final outlineColor = isDark
      ? colors.outline.withValues(alpha: 0.32)
      : const Color(0xFFD6DCE8);

  return base.copyWith(
    canvasColor: isDark ? const Color(0xFF111827) : Colors.white,
    cardColor: isDark ? const Color(0xFF162033) : Colors.white,
    textTheme: base.textTheme.apply(
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colors.onSurface,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w700,
        fontFamily: 'Montserrat',
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF162033) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF162033) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF162033) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1B2435) : Colors.white,
      labelStyle: TextStyle(color: colors.onSurfaceVariant),
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
      prefixIconColor: colors.primary,
      suffixIconColor: colors.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: outlineColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: outlineColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.primary, width: 1.8),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Montserrat',
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Montserrat',
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        side: BorderSide(color: outlineColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Montserrat',
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      indicatorColor: colors.primary.withValues(alpha: isDark ? 0.28 : 0.14),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.selected)
            ? colors.primary
            : colors.onSurfaceVariant;
        return TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontFamily: 'OpenSans',
        );
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.primary,
      textColor: colors.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: isDark
          ? const Color(0xFF1B2435)
          : const Color(0xFFEFF4FF),
      selectedColor: colors.primary.withValues(alpha: 0.16),
      labelStyle: TextStyle(color: colors.onSurface),
      side: BorderSide(color: outlineColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    dividerTheme: DividerThemeData(color: outlineColor, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark
          ? const Color(0xFF1E293B)
          : const Color(0xFF0F172A),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(outlineColor),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  unawaited(FirebasePushService.instance.initialize());
  unawaited(
    PushNotificationService.instance.initialize(
      navigatorKey: globalNavigatorKey,
      onTap: (payload) {
        if (payload != null) {
          debugPrint('Notification tapped with payload: $payload');
        }
      },
    ),
  );

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
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Dayung Setup Required',
            theme: _buildAppTheme(Brightness.light),
            themeMode: ThemeMode.light,
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
              theme: _buildAppTheme(Brightness.light),
              themeMode: ThemeMode.light,
              themeAnimationDuration: const Duration(milliseconds: 400),
              initialRoute: '/',
              routes: {
                '/': (context) => const _AuthGate(),
                '/splash': (context) => const SplashScreen(),
                '/role-router': (context) => const RoleRouter(),
                '/login': (context) => Login(),
                '/register': (context) => Register(),
                kPasswordRecoveryRoute: (context) =>
                    const PasswordRecoveryPage(),
                '/reapply': (context) => Reapply(),
                '/dashboard': (context) => MemberDashboardPage(),
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
          IdleTimeoutManager().start(context);
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
