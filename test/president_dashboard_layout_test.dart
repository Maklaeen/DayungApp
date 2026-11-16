import 'dart:math' as math;

import 'package:capstone_app/President/dashboard.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/shared/dayung_role_navigation_bar.dart';
import 'package:capstone_app/shared/pres_sec_dashboard_overview.dart';
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

  testWidgets('president dashboard lays out across viewport and text scales', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 360.0, 390.0, 600.0, 840.0, 1024.0, 1280.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(_dashboardApp(textScale: scale));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(_presidentHeaderGreeting(), findsOneWidget);
        expect(find.text('Management tools'), findsOneWidget);
        expect(find.text('Quick access'), findsOneWidget);
        if (width == 320 && scale == 2) {
          final homeScrollView = tester.widget<SingleChildScrollView>(
            find.byType(SingleChildScrollView).first,
          );
          expect(
            homeScrollView.padding?.resolve(TextDirection.ltr).bottom,
            304,
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'width=$width scale=$scale',
        );
      }
    }
  });

  testWidgets('president dashboard follows light, dark and system themes', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(_dashboardApp(themeMode: ThemeMode.light));
    expect(
      Theme.of(tester.element(_presidentHeaderGreeting())).brightness,
      Brightness.light,
    );

    await tester.pumpWidget(_dashboardApp(themeMode: ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      Theme.of(tester.element(_presidentHeaderGreeting())).brightness,
      Brightness.dark,
    );

    await tester.pumpWidget(_dashboardApp(themeMode: ThemeMode.system));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      Theme.of(tester.element(_presidentHeaderGreeting())).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('president overview uses theme-aware cards and headings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final darkTheme = buildDayungTheme(Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PresSecDashboardOverview(
              dayungUnitId: 1,
              responsiveLayout: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sectionTitle = tester.widget<Text>(
      find.text('Cash Collected per Month'),
    );
    expect(sectionTitle.style?.color, darkTheme.colorScheme.onSurface);
    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! Container || widget.decoration is! BoxDecoration) {
          return false;
        }
        return (widget.decoration as BoxDecoration).color == Colors.white;
      }),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('president role navigation updates the selected destination', (
    tester,
  ) async {
    await tester.pumpWidget(_dashboardApp());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Claims').last);
    await tester.pump();

    expect(
      tester.getSemantics(find.bySemanticsLabel('Claims').last),
      matchesSemantics(
        label: 'Claims',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('president contribution chart scrolls above bottom navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_dashboardApp(textScale: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final batchesLegend = find.text('batches');
    expect(batchesLegend, findsOneWidget);
    final homeScrollView = find.byType(SingleChildScrollView).first;
    final scrollRect = tester.getRect(homeScrollView);
    final navigationTop = tester
        .getTopLeft(find.byType(DayungRoleNavigationBar))
        .dy;
    final dragY = math.min(scrollRect.bottom, navigationTop).toDouble() - 8;
    for (var index = 0; index < 3; index++) {
      await tester.dragFrom(
        Offset(scrollRect.center.dx, dragY),
        const Offset(0, -4000),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final contentBottom = tester.getBottomLeft(batchesLegend).dy;

    expect(contentBottom, lessThan(navigationTop));
    final headerContainer = tester.widget<Container>(
      _headerGradient(_presidentHeaderGreeting()),
    );
    expect(
      (headerContainer.decoration as BoxDecoration).gradient,
      isA<LinearGradient>(),
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _presidentHeaderGreeting() => find.textContaining('Good Morning,');

Finder _headerGradient(Finder descendant) => find
    .ancestor(
      of: descendant,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).gradient is LinearGradient,
      ),
    )
    .first;

Widget _dashboardApp({
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
}) {
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
            body: PresidentDashboardPage(),
          ),
        ),
      ),
    ),
  );
}
