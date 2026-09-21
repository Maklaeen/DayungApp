class PaymentUploadType {
  static const String advancePayment = 'advance_payment';
  static const String forMembership = 'for_membership';
  static const String gcash = 'gcash';
  static const String defaultType = 'default';

  static String normalize(String? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    if (normalized.isEmpty) return defaultType;
    if (normalized == advancePayment ||
        normalized == forMembership ||
        normalized == gcash) {
      return normalized;
    }
    return defaultType;
  }

  static bool canProceedWithoutDeceased(String? value) {
    final normalized = normalize(value);
    return normalized == advancePayment ||
        normalized == forMembership ||
        normalized == gcash;
  }

  static bool isStandalonePaymentRow(Map<String, dynamic> row) {
    final type = normalize((row['type'] ?? '').toString());
    if (type == advancePayment || type == forMembership || type == gcash) {
      return true;
    }

    final userDeceased = (row['userdeceased'] ?? '').toString().trim();
    final deceasedName = (row['deceased_name'] ?? '').toString().trim();
    return userDeceased.isEmpty && deceasedName.isEmpty;
  }
}
