import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Treasurer/dashboard.dart';
import 'package:capstone_app/shared/dayung_role_navigation_bar.dart';
import 'package:capstone_app/ui/theme/dayung_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'example-anon-key',
      httpClient: MockClient(
        (_) async =>
            Response('[]', 200, headers: {'content-type': 'application/json'}),
      ),
    );
  });

  testWidgets('Treasurer dashboard adapts across widths and text scales', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 360.0, 390.0, 600.0, 840.0, 1024.0, 1280.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(_app(textScale: scale));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.textContaining('Good Morning,'), findsOneWidget);
        expect(find.text('Financial overview'), findsOneWidget);
        expect(find.text('Current Funds'), findsOneWidget);
        expect(find.text('Collected Today'), findsOneWidget);
        expect(find.text('Pending Contributions'), findsOneWidget);
        expect(find.text('Monthly collections'), findsOneWidget);
        expect(find.text('Contribution Confirmation'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'width=$width scale=$scale',
        );
      }
    }
  });

  testWidgets('Treasurer dashboard follows Light, Dark and System modes', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    for (final (mode, brightness) in [
      (ThemeMode.light, Brightness.light),
      (ThemeMode.dark, Brightness.dark),
      (ThemeMode.system, Brightness.dark),
    ]) {
      await tester.pumpWidget(_app(themeMode: mode));
      await tester.pump(const Duration(milliseconds: 400));

      final heading = find.text('Financial overview');
      expect(Theme.of(tester.element(heading)).brightness, brightness);
      final title = tester.widget<Text>(heading);
      expect(
        title.style?.color,
        Theme.of(tester.element(heading)).colorScheme.onSurface,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Treasurer dashboard preserves actions and nav destinations', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 400));

    for (final label in [
      'Contribution Confirmation',
      'Collection Reports',
      'Manage Fund',
      'Payment Release History',
      'Advance Payment',
      'Open GCash QR',
      'Assign Collectors',
      'Membership',
      'Paid & Unpaid Members',
      'Collector Records',
      'Overall Reports',
      'Reports',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(find.byType(DayungRoleNavigationBar), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Dashboard')),
      matchesSemantics(
        label: 'Dashboard',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app({ThemeMode themeMode = ThemeMode.light, double textScale = 1}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => DayungUnitProvider()),
      ChangeNotifierProvider(create: (_) => DayungRoleProvider()),
    ],
    child: MaterialApp(
      theme: buildDayungTheme(Brightness.light),
      darkTheme: buildDayungTheme(Brightness.dark),
      themeMode: themeMode,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(
            drawer: Drawer(),
            body: TreasurerDashboardPage(),
          ),
        ),
      ),
    ),
  );
}
