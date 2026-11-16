import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Secretary/dashboard.dart';
import 'package:capstone_app/Secretary/secclaims.dart';
import 'package:capstone_app/Secretary/seccontributions.dart';
import 'package:capstone_app/ui/theme/dayung_theme.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' show Response;
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

  testWidgets('Secretary dashboard headings follow Light, Dark and System', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    for (final (mode, brightness) in [
      (ThemeMode.light, Brightness.light),
      (ThemeMode.dark, Brightness.dark),
      (ThemeMode.system, Brightness.dark),
    ]) {
      await tester.pumpWidget(
        _app(home: const SecretaryDashboardPage(), mode: mode),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      for (final title in ['Quick Actions', 'Quick Access']) {
        final titleFinder = find.text(title);
        final titleWidget = tester.widget<Text>(titleFinder);
        final context = tester.element(titleFinder);
        expect(Theme.of(context).brightness, brightness);
        expect(
          titleWidget.style?.color,
          Theme.of(context).colorScheme.onSurface,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Secretary contributions empty state uses theme surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        home: const SecretaryContributionsPage(dayungUnitId: 1),
        mode: ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No contributions found'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == Colors.white,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Secretary claims search and empty state use dark theme tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(home: const SecretaryClaimsPage(), mode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      search.decoration?.fillColor,
      dayungSurface(tester.element(find.byType(TextField).first)),
    );
    expect(find.text('No claims found'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == Colors.white,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app({required Widget home, required ThemeMode mode}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) =>
            DayungUnitProvider()..setDayungUnit('Test Dayung', obj: {'id': 1}),
      ),
      ChangeNotifierProvider(create: (_) => DayungRoleProvider()..unitId = 1),
    ],
    child: MaterialApp(
      theme: buildDayungTheme(Brightness.light),
      darkTheme: buildDayungTheme(Brightness.dark),
      themeMode: mode,
      home: Scaffold(drawer: const Drawer(), body: home),
    ),
  );
}
