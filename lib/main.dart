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

class _SupabaseConfig {
  const _SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;
}

class _BootstrapException implements Exception {
  const _BootstrapException(this.message);

  final String message;

  @override
  String toString() => message;
}

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

  final appTheme = AppTheme();
  await appTheme.load();

  try {
    await dotenv.load(fileName: '.env');

    final supabaseConfig = _readSupabaseConfig();

    await Supabase.initialize(
      url: supabaseConfig.url,
      anonKey: supabaseConfig.anonKey,
    );

    runApp(ProviderScope(child: MyApp(appTheme: appTheme)));
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'main',
        context: ErrorDescription('while bootstrapping the application'),
      ),
    );

    runApp(_BootstrapErrorApp(appTheme: appTheme, error: error));
  }
}

_SupabaseConfig _readSupabaseConfig() {
  final supabaseUrl = dotenv.env['SUPABASE_URL']?.trim();
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim();

  if (supabaseUrl == null ||
      supabaseUrl.isEmpty ||
      supabaseAnonKey == null ||
      supabaseAnonKey.isEmpty) {
    throw const _BootstrapException(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env.',
    );
  }

  if (_looksLikePlaceholderValue(supabaseUrl) ||
      _looksLikePlaceholderValue(supabaseAnonKey)) {
    throw const _BootstrapException(
      'The .env file still contains placeholder Supabase credentials. Replace them with your real project URL and anon key.',
    );
  }

  final uri = Uri.tryParse(supabaseUrl);
  final hasValidUrl =
      uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;

  if (!hasValidUrl) {
    throw const _BootstrapException(
      'SUPABASE_URL is not a valid URL. Use the full project URL from Supabase Settings > API.',
    );
  }

  if (!uri.host.contains('supabase.')) {
    throw const _BootstrapException(
      'SUPABASE_URL does not look like a Supabase project URL.',
    );
  }

  return _SupabaseConfig(url: supabaseUrl, anonKey: supabaseAnonKey);
}

bool _looksLikePlaceholderValue(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.contains('your-project') ||
      normalized.contains('your_supabase') ||
      normalized.contains('anon_key_here') ||
      normalized.contains('supabase_url_here');
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.appTheme, required this.error});

  final AppTheme appTheme;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      _BootstrapException bootstrapError => bootstrapError.message,
      _ =>
        'The app could not start because the local configuration is invalid. Check your .env file and try again.',
    };

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dayung Setup Error',
      theme: _buildAppTheme(Brightness.light),
      darkTheme: _buildAppTheme(Brightness.dark),
      themeMode: appTheme.mode,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configuration required',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Text(message),
                        const SizedBox(height: 16),
                        const Text(
                          'Expected .env values:',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          'SUPABASE_URL=https://your-project.supabase.co\n'
                          'SUPABASE_ANON_KEY=your-anon-key',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace', height: 1.5),
                        ),
                      ],
                    ),
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
              theme: _buildAppTheme(Brightness.light),
              darkTheme: _buildAppTheme(Brightness.dark),
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
