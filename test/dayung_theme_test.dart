import 'package:capstone_app/Providers/apptheme_provider.dart';
import 'package:capstone_app/shared/dayung_role_navigation_bar.dart';
import 'package:capstone_app/ui/theme/dayung_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme builder preserves Material 3 and native font defaults', () {
    final lightTheme = buildDayungTheme(Brightness.light);
    final darkTheme = buildDayungTheme(Brightness.dark);

    expect(lightTheme.useMaterial3, isTrue);
    expect(lightTheme.brightness, Brightness.light);
    expect(darkTheme.brightness, Brightness.dark);
    expect(
      lightTheme.textTheme.bodyMedium?.fontFamily,
      ThemeData().textTheme.bodyMedium?.fontFamily,
    );
    expect(lightTheme.textTheme.bodyMedium?.fontFamily, isNot('Montserrat'));
    expect(lightTheme.textTheme.bodyMedium?.fontFamily, isNot('OpenSans'));
    expect(
      lightTheme.colorScheme.surface,
      isNot(darkTheme.colorScheme.surface),
    );
    expect(
      _contrastRatio(
        darkTheme.colorScheme.primary,
        darkTheme.colorScheme.surface,
      ),
      greaterThan(3),
    );
    expect(
      _contrastRatio(
        darkTheme.colorScheme.onSurface,
        darkTheme.colorScheme.surface,
      ),
      greaterThan(7),
    );
  });

  test('saved dark preference is reset to the light default', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final theme = AppTheme();

    expect(theme.mode, ThemeMode.light);
    await theme.load();
    expect(theme.mode, ThemeMode.light);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('theme_mode'), 'light');

    final restoredTheme = AppTheme();
    await restoredTheme.load();
    expect(restoredTheme.mode, ThemeMode.light);
  });

  testWidgets('active MaterialApp stays light when device prefers dark', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final theme = AppTheme();
    await theme.load();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: Builder(
          builder: (context) => MaterialApp(
            theme: buildDayungTheme(Brightness.light),
            darkTheme: buildDayungTheme(Brightness.dark),
            themeMode: context.watch<AppTheme>().mode,
            home: Builder(
              builder: (context) =>
                  Text(Theme.of(context).brightness.toString()),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Brightness.light'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme text responds to larger system text scaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDayungTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: Text('Accessible text', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.text('Accessible text')).height,
      greaterThan(30),
    );
  });

  testWidgets('shared role navigation adapts to viewport and text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 360.0, 390.0, 600.0, 840.0, 1024.0, 1280.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        tester.view.physicalSize = Size(width, 720);
        var selectedIndex = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDayungTheme(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 720),
                textScaler: TextScaler.linear(scale),
              ),
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: DayungRoleNavigationBar(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (index) =>
                          setState(() => selectedIndex = index),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Contributions'), findsOneWidget);
        expect(find.text('Claims'), findsOneWidget);
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
        await tester.tap(find.text('Contributions'));
        expect(selectedIndex, 1);
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Contributions')),
          matchesSemantics(
            label: 'Contributions',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
}

double _contrastRatio(Color foreground, Color background) {
  final luminances = [
    foreground.computeLuminance(),
    background.computeLuminance(),
  ]..sort((a, b) => b.compareTo(a));
  return (luminances[0] + 0.05) / (luminances[1] + 0.05);
}
