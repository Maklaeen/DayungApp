import 'package:flutter/services.dart';

class AppInputSecurity {
  static final RegExp _controlChars = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
  );

  static final List<RegExp> _blockedPayloadPatterns = [
    RegExp(r'<\s*/?\s*script\b', caseSensitive: false),
    RegExp(r'<\s*iframe\b', caseSensitive: false),
    RegExp(r'<\s*img\b', caseSensitive: false),
    RegExp(r'javascript\s*:', caseSensitive: false),
    RegExp(r'data\s*:\s*text/html', caseSensitive: false),
    RegExp(r'on(?:error|load|click|focus)\s*=', caseSensitive: false),
    RegExp(r'\bunion\s+select\b', caseSensitive: false),
    RegExp(r'\bdrop\s+table\b', caseSensitive: false),
    RegExp(r'\binsert\s+into\b', caseSensitive: false),
    RegExp(r'\bdelete\s+from\b', caseSensitive: false),
    RegExp(r'\bupdate\s+\w+\s+set\b', caseSensitive: false),
    RegExp(r'\bor\s+1\s*=\s*1\b', caseSensitive: false),
    RegExp(r'\band\s+1\s*=\s*1\b', caseSensitive: false),
  ];

  static String normalizeWhitespace(String raw, {bool allowNewLines = false}) {
    var value = raw.replaceAll(_controlChars, '');
    if (allowNewLines) {
      value = value
          .replaceAll(RegExp(r'\r\n?'), '\n')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n');
      return value.trim();
    }

    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String sanitizePlainText(
    String raw, {
    bool allowNewLines = false,
    int? maxLength,
  }) {
    var value = normalizeWhitespace(
      raw,
      allowNewLines: allowNewLines,
    ).replaceAll('<', '').replaceAll('>', '');

    value = value
        .replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), '')
        .replaceAll(RegExp(r'data\s*:\s*text/html', caseSensitive: false), '');

    if (maxLength != null && value.length > maxLength) {
      value = value.substring(0, maxLength);
    }
    return value;
  }

  static String sanitizeEmail(String raw) {
    return sanitizePlainText(raw, maxLength: 120).toLowerCase();
  }

  static String sanitizePhone(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  static String sanitizeSearchQuery(String raw) {
    return sanitizePlainText(raw, maxLength: 80);
  }

  static bool hasBlockedPayload(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    for (final pattern in _blockedPayloadPatterns) {
      if (pattern.hasMatch(value)) {
        return true;
      }
    }
    return false;
  }

  static String? validateSafeText(
    String? value, {
    required String fieldName,
    int minLength = 1,
    int maxLength = 255,
    bool required = true,
    bool allowNewLines = false,
  }) {
    final raw = value ?? '';
    final sanitized = sanitizePlainText(
      raw,
      allowNewLines: allowNewLines,
      maxLength: maxLength,
    );

    if (required && sanitized.isEmpty) {
      return '$fieldName is required';
    }
    if (!required && sanitized.isEmpty) {
      return null;
    }
    if (sanitized.length < minLength) {
      return '$fieldName is too short';
    }
    if (raw.trim().length > maxLength) {
      return '$fieldName is too long';
    }
    if (hasBlockedPayload(raw)) {
      return '$fieldName contains invalid content';
    }
    return null;
  }

  static String? validateEmail(String? value, {bool required = true}) {
    final email = sanitizeEmail(value ?? '');
    if (required && email.isEmpty) {
      return 'Email is required';
    }
    if (!required && email.isEmpty) {
      return null;
    }
    if (hasBlockedPayload(value ?? '')) {
      return 'Email contains invalid content';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email';
    }
    return null;
  }

  static String? validatePhone(String? value, {bool required = true}) {
    final digits = sanitizePhone(value ?? '').replaceAll('+', '');
    if (required && digits.isEmpty) {
      return 'Mobile number is required';
    }
    if (!required && digits.isEmpty) {
      return null;
    }
    if (!RegExp(r'^\d{10,15}$').hasMatch(digits)) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? validateEmailOrPhone(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return 'Phone number or email is required';
    }
    if (hasBlockedPayload(raw)) {
      return 'Input contains invalid content';
    }
    return raw.contains('@') ? validateEmail(raw) : validatePhone(raw);
  }

  static List<TextInputFormatter> singleLineFormatters({int? maxLength}) {
    return [
      FilteringTextInputFormatter.deny(RegExp(r'[<>]')),
      FilteringTextInputFormatter.deny(_controlChars),
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  static List<TextInputFormatter> multiLineFormatters({int? maxLength}) {
    return [
      FilteringTextInputFormatter.deny(RegExp(r'[<>]')),
      FilteringTextInputFormatter.deny(_controlChars),
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  static List<TextInputFormatter> phoneFormatters({int maxLength = 15}) {
    return [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }
}
