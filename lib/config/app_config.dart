import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'env.dart';

class AppConfig {
  const AppConfig._();

  static const requiredKeys = <String>['SUPABASE_URL', 'SUPABASE_ANON_KEY'];

  static const _supabaseUrlDefine = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const _supabaseAnonKeyDefine = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const _openRouteServiceApiKeyDefine = String.fromEnvironment(
    'OPENROUTESERVICE_API_KEY',
    defaultValue: '',
  );

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Allow builds that rely only on --dart-define values.
    }
  }


  static String get supabaseUrl {
    if (kIsWeb) {
      return Env.supabaseUrl;
    }
    return _firstNonEmpty(_supabaseUrlDefine, dotenv.env['SUPABASE_URL']);
  }

  static String get supabaseAnonKey {
    if (kIsWeb) {
      return Env.supabaseAnonKey;
    }
    return _firstNonEmpty(_supabaseAnonKeyDefine, dotenv.env['SUPABASE_ANON_KEY']);
  }

  static String get openRouteServiceApiKey {
    if (kIsWeb) {
      // Add to Env if needed
      return '';
    }
    return _firstNonEmpty(_openRouteServiceApiKeyDefine, dotenv.env['OPENROUTESERVICE_API_KEY']);
  }

  static String _firstNonEmpty(String primary, String? fallback) {
    if (primary.trim().isNotEmpty) {
      return primary;
    }
    return fallback?.trim() ?? '';
  }

  static List<String> missingRequiredKeys() {
    final missing = <String>[];
    if (supabaseUrl.trim().isEmpty) {
      missing.add('SUPABASE_URL');
    }
    if (supabaseAnonKey.trim().isEmpty) {
      missing.add('SUPABASE_ANON_KEY');
    }
    return missing;
  }

  static String requireValue(String name, String value) {
    if (value.trim().isEmpty) {
      throw StateError(
        'Missing app config: $name. Provide it via --dart-define or local .env.',
      );
    }
    return value;
  }
}
