import 'package:capstone_app/Secretary/secretarymemberspage.dart';
import 'package:capstone_app/ui/theme/dayung_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
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

  testWidgets('secretary member search uses the active input surface', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = buildDayungTheme(brightness);
      await _pumpPage(
        tester,
        theme,
        const SecretaryMembersPage(dayungUnitId: 1),
      );

      final search = tester.widget<TextField>(find.byType(TextField).first);
      expect(
        search.decoration?.fillColor,
        theme.inputDecorationTheme.fillColor,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  ThemeData theme,
  Widget page,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: theme, home: page));
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}
