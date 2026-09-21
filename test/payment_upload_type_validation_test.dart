import 'package:capstone_app/utils/payment_upload_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('advance payment uploads can proceed without a deceased record', () {
    expect(
      PaymentUploadType.canProceedWithoutDeceased('advance_payment'),
      isTrue,
    );
    expect(
      PaymentUploadType.canProceedWithoutDeceased('for_membership'),
      isTrue,
    );
    expect(PaymentUploadType.canProceedWithoutDeceased('default'), isFalse);
  });

  test(
    'standalone payment rows are grouped separately from deceased payments',
    () {
      expect(
        PaymentUploadType.isStandalonePaymentRow({
          'type': 'advance_payment',
          'userdeceased': 'some-user-id',
          'deceased_name': 'Mother',
        }),
        isTrue,
      );

      expect(
        PaymentUploadType.isStandalonePaymentRow({
          'type': 'default',
          'userdeceased': '',
          'deceased_name': '',
        }),
        isTrue,
      );

      expect(
        PaymentUploadType.isStandalonePaymentRow({
          'type': 'default',
          'userdeceased': 'some-user-id',
          'deceased_name': 'Mother',
        }),
        isFalse,
      );
    },
  );
}
