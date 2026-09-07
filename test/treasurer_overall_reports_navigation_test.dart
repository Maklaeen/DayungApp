import 'package:capstone_app/Treasurer/treasurer_overall_reports.dart';
import 'package:capstone_app/Treasurer/treasurer_payment_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          switch (methodCall.method) {
            case 'getAll':
              return <String, Object>{};
            case 'setString':
            case 'setBool':
            case 'setInt':
            case 'setDouble':
            case 'setStringList':
            case 'remove':
            case 'clear':
              return true;
            default:
              return null;
          }
        });

    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'example-anon-key',
    );
  });

  testWidgets('tapping advance payment opens treasurer payment page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () =>
                          TreasurerOverallReportsPage.openAdvancePayment(
                            context,
                            42,
                          ),
                      child: const Text('Advance Payment'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Advance Payment'));
    await tester.pumpAndSettle();

    expect(find.byType(TreasurerPaymentPage), findsOneWidget);
  });
}
