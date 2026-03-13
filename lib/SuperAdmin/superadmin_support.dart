import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const kSuperAdminBackendBaseUrl = String.fromEnvironment(
  'SUPERADMIN_BACKEND_URL',
  defaultValue: '',
);
const _kAuditEdgeFunctionName = 'audit-ingest';
const _kSuperAdminEdgeFunctionName = 'superadmin-admin';
const kSuperAdminPrimary = Color(0xFF17326B);
const kSuperAdminAccent = Color(0xFF0F9D7A);
const kSuperAdminCard = Color(0xFFFFFFFF);
const kSuperAdminText = Color(0xFF14213D);
const kSuperAdminMuted = Color(0xFF667085);
const kSuperAdminBorder = Color(0xFFD9E2F2);
const kSuperAdminDanger = Color(0xFFC73A2C);
const kSuperAdminWarn = Color(0xFFE69F00);
const _kSettingsTable = 'system_settings';

const Map<String, dynamic> _kDefaultSystemSettings = {
  'id': 'global',
  'maintenance_mode': false,
  'maintenance_message':
      'Dayung is temporarily unavailable for maintenance. Please try again later.',
  'allow_sms_broadcast': false,
  'force_password_change_on_create': true,
  'force_password_change_on_reset': true,
  'updated_at': null,
  'updated_by': null,
};

const Map<String, String> _kEdgeFunctionGetActions = {
  '/superadmin/users': 'list_users',
  '/superadmin/audit-logs': 'get_audit_logs',
  '/superadmin/reports': 'get_reports',
  '/superadmin/system-snapshot': 'get_system_snapshot',
};

const Map<String, String> _kEdgeFunctionPostActions = {
  '/superadmin/create-user': 'create_user',
  '/superadmin/reset-user-password': 'reset_user_password',
  '/superadmin/set-user-disabled': 'set_user_disabled',
  '/superadmin/send-broadcast': 'send_broadcast',
};

Color superAdminBackground(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF18181B)
      : const Color(0xFFF4F7FB);
}

Future<String> _currentAccessToken() async {
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null || token.isEmpty) {
    throw Exception('Your session expired. Please sign in again.');
  }
  return token;
}

Uri _buildBackendUri(String path) {
  final baseUrl = kSuperAdminBackendBaseUrl.trim();
  if (baseUrl.isEmpty) {
    throw Exception('No external backend configured.');
  }
  return Uri.parse('$baseUrl$path');
}

bool get _hasExternalBackend => kSuperAdminBackendBaseUrl.trim().isNotEmpty;

bool _hasEdgeFunctionGet(String path) =>
    _kEdgeFunctionGetActions.containsKey(path);

bool _hasEdgeFunctionPost(String path) =>
    _kEdgeFunctionPostActions.containsKey(path);

bool _canFallbackToLocalPost(String path, Map<String, dynamic> body) {
  if (path != '/superadmin/send-broadcast') {
    return false;
  }

  final audience = '${body['audience'] ?? 'all_active'}'.toLowerCase();
  final sendSms = body['send_sms'] == true;
  return !sendSms && audience != 'inactive';
}

Uri _parseVirtualPath(String path) => Uri.parse('https://local$path');

Map<String, dynamic> _coerceJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = _tryDecodeMap(value);
    if (decoded != null) {
      return decoded;
    }
  }
  throw Exception('Unexpected response from Supabase Edge Function.');
}

String _edgeFunctionErrorMessage(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  if (raw.isEmpty) {
    return 'Supabase Edge Function superadmin-admin is not available. Deploy it first.';
  }
  if (raw.contains('Failed to fetch') ||
      raw.contains('FunctionsFetchException') ||
      raw.contains('404')) {
    return 'Supabase Edge Function superadmin-admin is not available. Deploy it first.';
  }
  return raw;
}

bool _edgeFunctionUnavailable(Object error) {
  final message = _edgeFunctionErrorMessage(error).toLowerCase();
  return message.contains('edge function superadmin-admin is not available');
}

Future<Map<String, dynamic>> _invokeSuperAdminEdgeFunction(
  String action,
  Map<String, dynamic> payload,
) async {
  await _currentAccessToken();
  try {
    final response = await Supabase.instance.client.functions.invoke(
      _kSuperAdminEdgeFunctionName,
      body: {'action': action, ...payload},
    );
    return _coerceJsonMap(response.data);
  } catch (error) {
    throw Exception(_edgeFunctionErrorMessage(error));
  }
}

Future<Map<String, dynamic>> _loadSystemSettings() async {
  try {
    final row = await Supabase.instance.client
        .from(_kSettingsTable)
        .select(
          'id, maintenance_mode, maintenance_message, allow_sms_broadcast, '
          'force_password_change_on_create, force_password_change_on_reset, '
          'updated_at, updated_by',
        )
        .eq('id', 'global')
        .maybeSingle();

    return {..._kDefaultSystemSettings, ...?row};
  } catch (_) {
    return Map<String, dynamic>.from(_kDefaultSystemSettings);
  }
}

String _sanitizeText(Object? value, {int maxLength = 255}) {
  if (value is! String) return '';
  final cleaned = value.replaceAll(RegExp(r'[<>]'), '').trim();
  return cleaned.length > maxLength ? cleaned.substring(0, maxLength) : cleaned;
}

String _sanitizeMultilineText(Object? value, {int maxLength = 800}) {
  if (value is! String) return '';
  final cleaned = value
      .replaceAll(RegExp(r'[<>]'), '')
      .replaceAll('\r', '')
      .trim();
  return cleaned.length > maxLength ? cleaned.substring(0, maxLength) : cleaned;
}

String _encodeAuditValue(Object? value) {
  return Uri.encodeComponent((value ?? '').toString().trim());
}

String _buildAuditAction(String eventName, [Map<String, dynamic>? fields]) {
  final safeEvent = _sanitizeText(
    eventName,
    maxLength: 80,
  ).replaceAll(RegExp(r'\s+'), '_').toUpperCase();
  final segments = <String>[safeEvent.isEmpty ? 'EVENT' : safeEvent];
  for (final entry in (fields ?? const <String, dynamic>{}).entries) {
    final value = entry.value;
    if (value == null || value.toString().trim().isEmpty) continue;
    segments.add(
      '${_sanitizeText(entry.key, maxLength: 40).toLowerCase()}=${_encodeAuditValue(value)}',
    );
  }
  return segments.join(' | ');
}

String _humanizeAuditEvent(String eventName) {
  return eventName
      .toLowerCase()
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _auditCategoryForEvent(String eventName) {
  if (eventName.startsWith('LOGIN_')) {
    return 'Login Attempts';
  }
  if (eventName.startsWith('SYSTEM_ERROR')) {
    return 'System Errors';
  }
  if (eventName.startsWith('ACCESS_')) {
    return 'Access Violations';
  }
  if (eventName.startsWith('USER_ACTIVITY_') ||
      eventName == 'PASSWORD_CHANGED_ON_FIRST_SIGN_IN') {
    return 'User Activities';
  }
  return _humanizeAuditEvent(eventName);
}

String _auditTitleForEvent(String eventName) {
  if (eventName.startsWith('USER_ACTIVITY_')) {
    return _humanizeAuditEvent(eventName.replaceFirst('USER_ACTIVITY_', ''));
  }
  return _humanizeAuditEvent(eventName);
}

Map<String, dynamic> _parseAuditAction(String? action) {
  final raw = (action ?? '').trim();
  if (raw.isEmpty) {
    return {
      'raw_action': '',
      'category': 'General',
      'title': 'General activity',
      'details': <String>[],
      'fields': <String, dynamic>{},
    };
  }

  final parts = raw
      .split('|')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  final eventToken = parts.isEmpty ? raw : parts.first;
  final structured = RegExp(r'^[A-Z0-9_]+$').hasMatch(eventToken);
  final fields = <String, dynamic>{};
  final details = <String>[];

  for (final part in parts.skip(1)) {
    final eqIndex = part.indexOf('=');
    if (eqIndex <= 0) {
      details.add(part);
      continue;
    }
    final key = part.substring(0, eqIndex).trim().toLowerCase();
    final value = Uri.decodeComponent(part.substring(eqIndex + 1).trim());
    fields[key] = value;
  }

  if (!structured) {
    return {
      'raw_action': raw,
      'category': 'General',
      'title': raw,
      'details': details,
      'fields': fields,
    };
  }

  final title = _auditTitleForEvent(eventToken);
  return {
    'raw_action': raw,
    'category': _auditCategoryForEvent(eventToken),
    'title': title,
    'details': details,
    'fields': fields,
  };
}

Future<void> _insertAuditLog(
  String? userId,
  String eventName, [
  Map<String, dynamic>? fields,
]) async {
  try {
    final payload = <String, dynamic>{
      'action': _buildAuditAction(eventName, fields),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (userId != null && userId.trim().isNotEmpty) {
      payload['user_id'] = userId;
    }
    await Supabase.instance.client.from('audit_logs').insert(payload);
  } catch (_) {}
}

bool _isAuditEdgeFunctionUnavailable(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('edge function audit-ingest is not available') ||
      message.contains('functionsfetchexception') ||
      message.contains('404');
}

bool _canFallbackToDirectAuditInsert(String? userId) {
  return userId != null && userId.trim().isNotEmpty;
}

Future<void> _sendAuditEventServerSide(
  String eventName, {
  Map<String, dynamic>? fields,
}) async {
  if (_hasExternalBackend) {
    final uri = _buildBackendUri('/audit/ingest');
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'event_name': eventName, 'fields': fields ?? const {}}),
    );
    await _decodeJsonResponse(response, uri);
    return;
  }

  try {
    final response = await Supabase.instance.client.functions.invoke(
      _kAuditEdgeFunctionName,
      body: {'event_name': eventName, 'fields': fields ?? const {}},
    );
    _coerceJsonMap(response.data);
  } catch (error) {
    if (_isAuditEdgeFunctionUnavailable(error)) {
      throw Exception(
        'Supabase Edge Function audit-ingest is not available. Deploy it first.',
      );
    }
    rethrow;
  }
}

String _compactAuditError(Object error, {int maxLength = 180}) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  if (raw.isEmpty) {
    return 'Unknown error';
  }
  return raw.length > maxLength ? raw.substring(0, maxLength) : raw;
}

Future<void> logAuditEvent(
  String eventName, {
  String? userId,
  Map<String, dynamic>? fields,
}) async {
  final currentUser = Supabase.instance.client.auth.currentUser;
  final resolvedUserId = userId ?? currentUser?.id;

  try {
    await _sendAuditEventServerSide(eventName, fields: fields);
    return;
  } catch (error) {
    if (!_canFallbackToDirectAuditInsert(resolvedUserId)) {
      return;
    }
  }

  await _insertAuditLog(resolvedUserId, eventName, fields);
}

Future<void> logSystemError(
  String source,
  Object error, {
  String? userId,
  Map<String, dynamic>? fields,
}) async {
  await logAuditEvent(
    'SYSTEM_ERROR',
    userId: userId,
    fields: {
      'source': source,
      'message': _compactAuditError(error),
      ...?fields,
    },
  );
}

Future<void> logAccessViolation({
  required String resource,
  String? userId,
  String? reason,
  String? attemptedRole,
}) async {
  await logAuditEvent(
    'ACCESS_VIOLATION',
    userId: userId,
    fields: {
      'resource': resource,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason,
      if (attemptedRole != null && attemptedRole.trim().isNotEmpty)
        'attempted_role': attemptedRole,
    },
  );
}

String? _monthKey(Object? value) {
  final parsed = DateTime.tryParse('${value ?? ''}')?.toUtc();
  if (parsed == null) return null;
  return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> _buildMonthSeries(
  int monthsBack,
  Iterable<Map<String, dynamic>> values, {
  bool amount = false,
}) {
  final now = DateTime.now().toUtc();
  final buckets = <String, double>{};
  for (var offset = monthsBack - 1; offset >= 0; offset--) {
    final month = DateTime.utc(now.year, now.month - offset, 1);
    final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    buckets[key] = 0;
  }

  for (final entry in values) {
    final key = _monthKey(entry['date']);
    if (key == null || !buckets.containsKey(key)) continue;
    buckets[key] =
        (buckets[key] ?? 0) +
        (amount ? ((entry['value'] as num?)?.toDouble() ?? 0) : 1);
  }

  return buckets.entries
      .map(
        (entry) => {
          'month': entry.key,
          'value': amount
              ? double.parse(entry.value.toStringAsFixed(2))
              : entry.value.toInt(),
        },
      )
      .toList();
}

Future<Map<String, dynamic>> _buildReportsModel() async {
  final sb = Supabase.instance.client;
  final users = await sb
      .from('users')
      .select('id, role, is_deceased, created_at');
  final applications = await sb
      .from('applications')
      .select('user_id, dayung_unit_id, status, approved_at');
  final units = await sb
      .from('dayung_units')
      .select('id, name, president_id, secretary_id, treasurer_id');
  final collectors = await sb
      .from('dayung_collectors')
      .select('user_id, dayung_unit_id');
  final payments = await sb.from('payments').select('amount, status, paid_at');
  final notifications = await sb.from('notifications').select('created_at');
  final auditLogs = await sb.from('audit_logs').select('created_at');

  final userRows = List<Map<String, dynamic>>.from(users);
  final appRows = List<Map<String, dynamic>>.from(applications);
  final unitRows = List<Map<String, dynamic>>.from(units);
  final collectorRows = List<Map<String, dynamic>>.from(collectors);
  final paymentRows = List<Map<String, dynamic>>.from(payments);
  final notificationRows = List<Map<String, dynamic>>.from(notifications);
  final auditRows = List<Map<String, dynamic>>.from(auditLogs);

  final approvedApps = appRows
      .where((row) => row['status'] == 'approved')
      .toList();
  final approvedMemberIds = approvedApps
      .map((row) => row['user_id']?.toString())
      .whereType<String>()
      .toSet();

  final officerIds = <String>{};
  final unitMemberCounts = <String, int>{};
  final unitNames = <String, String>{};
  for (final unit in unitRows) {
    final unitId = unit['id']?.toString();
    if (unitId != null) {
      unitNames[unitId] = (unit['name'] ?? 'Unit $unitId').toString();
    }
    for (final key in const ['president_id', 'secretary_id', 'treasurer_id']) {
      final value = unit[key]?.toString();
      if (value != null && value.isNotEmpty) officerIds.add(value);
    }
  }
  for (final collector in collectorRows) {
    final userId = collector['user_id']?.toString();
    if (userId != null && userId.isNotEmpty) officerIds.add(userId);
  }
  for (final app in approvedApps) {
    final unitId = app['dayung_unit_id']?.toString();
    if (unitId == null || unitId.isEmpty) continue;
    unitMemberCounts[unitId] = (unitMemberCounts[unitId] ?? 0) + 1;
  }

  final paidRows = paymentRows
      .where((row) => '${row['status'] ?? ''}'.toLowerCase() == 'paid')
      .toList();
  final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30));

  return {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'summary': {
      'total_users': userRows.length,
      'active_users': userRows
          .where((user) => user['is_deceased'] != true)
          .length,
      'disabled_users': 0,
      'deceased_users': userRows
          .where((user) => user['is_deceased'] == true)
          .length,
      'superadmins': userRows
          .where((user) => user['role'] == 'superadmin')
          .length,
      'officers': officerIds.length,
      'approved_members': approvedMemberIds.length,
      'pending_applications': appRows
          .where((row) => row['status'] == 'pending')
          .length,
      'dayung_units': unitRows.length,
      'paid_transactions': paidRows.length,
      'paid_total': double.parse(
        paidRows
            .fold<double>(
              0,
              (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
            )
            .toStringAsFixed(2),
      ),
      'notifications_last_30_days': notificationRows.where((row) {
        final date = DateTime.tryParse('${row['created_at'] ?? ''}')?.toUtc();
        return date != null && !date.isBefore(cutoff);
      }).length,
      'audit_logs_last_30_days': auditRows.where((row) {
        final date = DateTime.tryParse('${row['created_at'] ?? ''}')?.toUtc();
        return date != null && !date.isBefore(cutoff);
      }).length,
    },
    'monthly_users': _buildMonthSeries(
      6,
      userRows.map((row) => {'date': row['created_at']}),
    ),
    'monthly_approvals': _buildMonthSeries(
      6,
      approvedApps.map((row) => {'date': row['approved_at']}),
    ),
    'monthly_revenue': _buildMonthSeries(
      6,
      paidRows.map((row) => {'date': row['paid_at'], 'value': row['amount']}),
      amount: true,
    ),
    'role_breakdown': {
      'superadmins': userRows
          .where((user) => user['role'] == 'superadmin')
          .length,
      'officers': officerIds.length,
      'members': approvedMemberIds.length,
      'disabled': 0,
    },
    'top_units': _buildTopUnits(unitMemberCounts, unitNames),
  };
}

List<Map<String, dynamic>> _buildTopUnits(
  Map<String, int> counts,
  Map<String, String> names,
) {
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries
      .take(5)
      .map(
        (entry) => {
          'dayung_unit_id': entry.key,
          'name': names[entry.key] ?? 'Unit ${entry.key}',
          'members': entry.value,
        },
      )
      .toList();
}

Future<Set<String>> _loadUnitParticipantIds(String dayungUnitId) async {
  final sb = Supabase.instance.client;
  final participantIds = <String>{};
  final unit = await sb
      .from('dayung_units')
      .select('president_id, secretary_id, treasurer_id')
      .eq('id', dayungUnitId)
      .maybeSingle();
  final collectors = await sb
      .from('dayung_collectors')
      .select('user_id')
      .eq('dayung_unit_id', dayungUnitId);
  final apps = await sb
      .from('applications')
      .select('user_id')
      .eq('dayung_unit_id', dayungUnitId)
      .eq('status', 'approved');
  for (final key in const ['president_id', 'secretary_id', 'treasurer_id']) {
    final id = unit?[key]?.toString();
    if (id != null && id.isNotEmpty) participantIds.add(id);
  }
  for (final collector in List<Map<String, dynamic>>.from(collectors)) {
    final id = collector['user_id']?.toString();
    if (id != null && id.isNotEmpty) participantIds.add(id);
  }
  for (final app in List<Map<String, dynamic>>.from(apps)) {
    final id = app['user_id']?.toString();
    if (id != null && id.isNotEmpty) participantIds.add(id);
  }
  return participantIds;
}

Future<Map<String, dynamic>> _resolveBroadcastRecipients(
  String audience,
  int? dayungUnitId,
) async {
  final sb = Supabase.instance.client;
  final users = List<Map<String, dynamic>>.from(
    await sb
        .from('users')
        .select('id, full_name, email, role, mobile_number, is_deceased'),
  );
  final approvedApps = List<Map<String, dynamic>>.from(
    await sb
        .from('applications')
        .select('user_id, dayung_unit_id, status')
        .eq('status', 'approved'),
  );
  final units = List<Map<String, dynamic>>.from(
    await sb
        .from('dayung_units')
        .select('id, president_id, secretary_id, treasurer_id'),
  );
  final collectors = List<Map<String, dynamic>>.from(
    await sb.from('dayung_collectors').select('user_id, dayung_unit_id'),
  );

  final officerIds = <String>{};
  for (final unit in units) {
    for (final key in const ['president_id', 'secretary_id', 'treasurer_id']) {
      final id = unit[key]?.toString();
      if (id != null && id.isNotEmpty) officerIds.add(id);
    }
  }
  for (final collector in collectors) {
    final id = collector['user_id']?.toString();
    if (id != null && id.isNotEmpty) officerIds.add(id);
  }

  var recipientIds = <String>{};
  var audienceLabel = audience;
  final unitIdText = dayungUnitId?.toString();

  switch (audience) {
    case 'all_active':
      if (unitIdText != null) {
        recipientIds = await _loadUnitParticipantIds(unitIdText);
        audienceLabel = 'Active users in unit $unitIdText';
      } else {
        recipientIds = users.map((user) => user['id'].toString()).toSet();
        audienceLabel = 'All active users';
      }
      break;
    case 'members':
      recipientIds = approvedApps
          .where(
            (row) =>
                unitIdText == null || '${row['dayung_unit_id']}' == unitIdText,
          )
          .map((row) => row['user_id']?.toString())
          .whereType<String>()
          .toSet();
      audienceLabel = unitIdText == null
          ? 'All approved members'
          : 'Approved members in unit $unitIdText';
      break;
    case 'officers':
      if (unitIdText != null) {
        final unitParticipants = await _loadUnitParticipantIds(unitIdText);
        recipientIds = unitParticipants
            .where((id) => officerIds.contains(id))
            .toSet();
        audienceLabel = 'Officers in unit $unitIdText';
      } else {
        recipientIds = officerIds;
        audienceLabel = 'All officers';
      }
      break;
    case 'superadmins':
      recipientIds = users
          .where((user) => user['role'] == 'superadmin')
          .map((user) => user['id'].toString())
          .toSet();
      audienceLabel = 'All superadmins';
      break;
    case 'inactive':
      recipientIds = <String>{};
      audienceLabel =
          'Inactive accounts are only available with an Edge Function.';
      break;
    default:
      throw Exception('Unsupported audience.');
  }

  final recipients = users
      .where((user) => user['is_deceased'] != true)
      .where((user) => recipientIds.contains('${user['id']}'))
      .toList();

  return {'recipients': recipients, 'audience_label': audienceLabel};
}

Future<Map<String, dynamic>> _handleLocalGet(String path) async {
  final uri = _parseVirtualPath(path);
  final sb = Supabase.instance.client;

  switch (uri.path) {
    case '/system/runtime':
      final settings = await _loadSystemSettings();
      return {
        'maintenance_mode': settings['maintenance_mode'] == true,
        'maintenance_message': settings['maintenance_message'],
      };
    case '/superadmin/settings':
      return {
        'settings': await _loadSystemSettings(),
        'twilio_configured': false,
      };
    case '/superadmin/users':
      final users = List<Map<String, dynamic>>.from(
        await sb
            .from('users')
            .select('id, full_name, email, role, is_deceased')
            .order('full_name'),
      );
      return {
        'users': users
            .map(
              (user) => {
                ...user,
                'is_disabled': false,
                'banned_until': null,
                'email_confirmed_at': null,
              },
            )
            .toList(),
      };
    case '/superadmin/reports':
      return _buildReportsModel();
    case '/superadmin/system-snapshot':
      final report = await _buildReportsModel();
      return {
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'settings': await _loadSystemSettings(),
        'report': report,
      };
    case '/superadmin/audit-logs':
      final limit = int.tryParse(uri.queryParameters['limit'] ?? '120') ?? 120;
      final query = (uri.queryParameters['q'] ?? '').trim().toLowerCase();
      final categoryFilter = (uri.queryParameters['category'] ?? '')
          .trim()
          .toLowerCase();
      final logsRes = await sb
          .from('audit_logs')
          .select('id, action, created_at, user:user_id(full_name, email)')
          .order('created_at', ascending: false)
          .limit(limit.clamp(20, 250));
      final logs = List<Map<String, dynamic>>.from(logsRes)
          .map((log) {
            final parsed = _parseAuditAction(log['action']?.toString());
            return {
              'id': log['id'],
              'created_at': log['created_at'],
              'actor_name':
                  (log['user'] as Map?)?['full_name'] ?? 'Unknown user',
              'actor_email': (log['user'] as Map?)?['email'],
              'category': parsed['category'],
              'title': parsed['title'],
              'fields': parsed['fields'],
              'details': parsed['details'],
              'raw_action': parsed['raw_action'],
            };
          })
          .where((log) {
            final haystack =
                '${log['actor_name']} ${log['actor_email'] ?? ''} ${log['category']} ${log['title']} ${log['raw_action']}'
                    .toLowerCase();
            if (query.isNotEmpty && !haystack.contains(query)) return false;
            if (categoryFilter.isNotEmpty &&
                '${log['category']}'.toLowerCase() != categoryFilter) {
              return false;
            }
            return true;
          })
          .toList();
      final categories =
          logs.map((log) => '${log['category']}').toSet().toList()..sort();
      return {'logs': logs, 'categories': categories};
    default:
      throw Exception(
        'This action is not available in direct Supabase mode yet. Path: ${uri.path}',
      );
  }
}

Future<Map<String, dynamic>> _handleLocalPost(
  String path,
  Map<String, dynamic> body,
) async {
  final uri = _parseVirtualPath(path);
  final sb = Supabase.instance.client;
  final currentUser = sb.auth.currentUser;
  if (currentUser == null) {
    throw Exception('Your session expired. Please sign in again.');
  }

  switch (uri.path) {
    case '/superadmin/settings':
      final nextState = {
        ...await _loadSystemSettings(),
        'id': 'global',
        'maintenance_mode': body['maintenance_mode'] == true,
        'maintenance_message':
            _sanitizeMultilineText(
              body['maintenance_message'],
              maxLength: 240,
            ).isEmpty
            ? _kDefaultSystemSettings['maintenance_message']
            : _sanitizeMultilineText(
                body['maintenance_message'],
                maxLength: 240,
              ),
        'allow_sms_broadcast': body['allow_sms_broadcast'] == true,
        'force_password_change_on_create':
            body['force_password_change_on_create'] != false,
        'force_password_change_on_reset':
            body['force_password_change_on_reset'] != false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': currentUser.email ?? currentUser.id,
      };
      try {
        await sb.from(_kSettingsTable).upsert(nextState);
      } catch (_) {
        throw Exception(
          'System settings table is not ready yet. Create the public.system_settings table first.',
        );
      }
      await _insertAuditLog(currentUser.id, 'SYSTEM_SETTINGS_UPDATED', {
        'maintenance_mode': nextState['maintenance_mode'],
        'allow_sms_broadcast': nextState['allow_sms_broadcast'],
      });
      return {
        'success': true,
        'settings': nextState,
        'twilio_configured': false,
      };
    case '/superadmin/assign-unit-role':
      final unitId = body['dayung_unit_id'];
      final role = '${body['role'] ?? ''}'.toLowerCase();
      final userId = '${body['user_id'] ?? ''}';
      if ('$unitId'.isEmpty || userId.isEmpty) {
        throw Exception('Missing required role assignment data.');
      }
      if (role == 'collector') {
        await sb.from('dayung_collectors').upsert({
          'dayung_unit_id': unitId,
          'user_id': userId,
        });
      } else {
        final columns = {
          'president': 'president_id',
          'secretary': 'secretary_id',
          'treasurer': 'treasurer_id',
        };
        final column = columns[role];
        if (column == null) throw Exception('Unsupported role assignment.');
        await sb.from('dayung_units').update({column: userId}).eq('id', unitId);
      }
      await _insertAuditLog(currentUser.id, 'UNIT_ROLE_ASSIGNED', {
        'role': role,
        'target': userId,
        'unit': unitId,
      });
      return {'success': true};
    case '/superadmin/remove-unit-role':
      final unitId = body['dayung_unit_id'];
      final role = '${body['role'] ?? ''}'.toLowerCase();
      final userId = '${body['user_id'] ?? ''}';
      if (role == 'collector') {
        if (userId.isEmpty) {
          throw Exception('Collector removal requires a user id.');
        }
        await sb
            .from('dayung_collectors')
            .delete()
            .eq('dayung_unit_id', unitId)
            .eq('user_id', userId);
      } else {
        final columns = {
          'president': 'president_id',
          'secretary': 'secretary_id',
          'treasurer': 'treasurer_id',
        };
        final column = columns[role];
        if (column == null) throw Exception('Unsupported role removal.');
        await sb.from('dayung_units').update({column: null}).eq('id', unitId);
      }
      await _insertAuditLog(currentUser.id, 'UNIT_ROLE_REMOVED', {
        'role': role,
        'target': userId,
        'unit': unitId,
      });
      return {'success': true};
    case '/superadmin/send-broadcast':
      final settings = await _loadSystemSettings();
      final title = _sanitizeText(body['title'], maxLength: 120);
      final message = _sanitizeMultilineText(body['body'], maxLength: 800);
      final audience = '${body['audience'] ?? 'all_active'}'.toLowerCase();
      final dayungUnitId = body['dayung_unit_id'] is int
          ? body['dayung_unit_id'] as int
          : int.tryParse('${body['dayung_unit_id'] ?? ''}');
      final sendSms = body['send_sms'] == true;
      if (title.length < 3 || message.length < 6) {
        throw Exception('Title or message is too short.');
      }
      if (sendSms) {
        throw Exception(
          'SMS sending still requires a Supabase Edge Function because Twilio secrets must stay server-side.',
        );
      }
      if (settings['allow_sms_broadcast'] != true) {
        // no-op for in-app only; keep allowed behavior simple
      }
      final resolved = await _resolveBroadcastRecipients(
        audience,
        dayungUnitId,
      );
      final recipients = List<Map<String, dynamic>>.from(
        resolved['recipients'] ?? const [],
      );
      if (recipients.isNotEmpty) {
        final rows = recipients
            .map(
              (recipient) => {
                'recipient_id': recipient['id'],
                'type': 'announcement',
                'title': title,
                'body': message,
                'dayung_unit_id': dayungUnitId,
              },
            )
            .toList();
        await sb.from('notifications').insert(rows);
      }
      await _insertAuditLog(currentUser.id, 'BROADCAST_SENT', {
        'title': title,
        'audience': audience,
        'unit': dayungUnitId ?? 'all',
        'delivered': recipients.length,
        'sms_sent': 0,
      });
      return {
        'success': true,
        'delivered': recipients.length,
        'sms_sent': 0,
        'audience_label': resolved['audience_label'],
      };
    case '/superadmin/create-user':
    case '/superadmin/reset-user-password':
    case '/superadmin/set-user-disabled':
      throw Exception(
        'This action still requires a Supabase Edge Function because it changes Auth users or protected server-side state.',
      );
    default:
      throw Exception(
        'This action is not available in direct Supabase mode yet. Path: ${uri.path}',
      );
  }
}

bool _looksLikeHtml(http.Response response) {
  final contentType = response.headers['content-type']?.toLowerCase() ?? '';
  final body = response.body.trimLeft().toLowerCase();
  return contentType.contains('text/html') ||
      body.startsWith('<!doctype html') ||
      body.startsWith('<html');
}

Map<String, dynamic>? _tryDecodeMap(String raw) {
  if (raw.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

String _extractBackendError(http.Response response, Uri uri) {
  final decoded = _tryDecodeMap(response.body);
  final backendMessage = decoded?['error']?.toString().trim();
  if (backendMessage != null && backendMessage.isNotEmpty) {
    return backendMessage;
  }

  if (_looksLikeHtml(response)) {
    return 'The configured server endpoint at ${uri.origin} returned an HTML page instead of JSON. Point SUPERADMIN_BACKEND_URL to a valid Supabase Edge Function or server endpoint.';
  }

  return 'Request failed with status ${response.statusCode} from ${uri.origin}.';
}

Future<Map<String, dynamic>> _decodeJsonResponse(
  http.Response response,
  Uri uri,
) async {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(_extractBackendError(response, uri));
  }

  final decoded = _tryDecodeMap(response.body);
  if (decoded != null) {
    return decoded;
  }

  if (_looksLikeHtml(response)) {
    throw Exception(
      'The configured server endpoint at ${uri.origin} returned HTML instead of JSON. Point SUPERADMIN_BACKEND_URL to a valid Supabase Edge Function or server endpoint.',
    );
  }

  throw Exception('Unexpected response from server ${uri.origin}.');
}

Future<Map<String, dynamic>> superAdminGetJson(String path) async {
  final localUri = _parseVirtualPath(path);
  if (!_hasExternalBackend) {
    if (_hasEdgeFunctionGet(localUri.path)) {
      try {
        final payload = <String, dynamic>{...localUri.queryParameters};
        return await _invokeSuperAdminEdgeFunction(
          _kEdgeFunctionGetActions[localUri.path]!,
          payload,
        );
      } catch (error) {
        if (!_edgeFunctionUnavailable(error)) {
          rethrow;
        }
        return _handleLocalGet(path);
      }
    }
    return _handleLocalGet(path);
  }
  final token = await _currentAccessToken();
  final uri = _buildBackendUri(path);
  final response = await http.get(
    uri,
    headers: {'Authorization': 'Bearer $token'},
  );
  return _decodeJsonResponse(response, uri);
}

Future<Map<String, dynamic>> superAdminPostJson(
  String path,
  Map<String, dynamic> body,
) async {
  if (!_hasExternalBackend) {
    if (_hasEdgeFunctionPost(path)) {
      try {
        return await _invokeSuperAdminEdgeFunction(
          _kEdgeFunctionPostActions[path]!,
          body,
        );
      } catch (error) {
        if (_edgeFunctionUnavailable(error) &&
            _canFallbackToLocalPost(path, body)) {
          return _handleLocalPost(path, body);
        }
        rethrow;
      }
    }
    return _handleLocalPost(path, body);
  }
  final token = await _currentAccessToken();
  final uri = _buildBackendUri(path);
  final response = await http.post(
    uri,
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(body),
  );
  return _decodeJsonResponse(response, uri);
}

Future<Map<String, dynamic>> publicBackendGetJson(String path) async {
  if (!_hasExternalBackend) {
    return _handleLocalGet(path);
  }
  final uri = _buildBackendUri(path);
  final response = await http.get(uri);
  return _decodeJsonResponse(response, uri);
}

class SuperAdminAccessGuard extends StatefulWidget {
  final Widget child;
  final String title;

  const SuperAdminAccessGuard({
    super.key,
    required this.child,
    required this.title,
  });

  @override
  State<SuperAdminAccessGuard> createState() => _SuperAdminAccessGuardState();
}

class _SuperAdminAccessGuardState extends State<SuperAdminAccessGuard> {
  late Future<bool> _allowedFuture;
  bool _viewLogged = false;

  @override
  void initState() {
    super.initState();
    _allowedFuture = _checkAccess();
  }

  Future<bool> _checkAccess() async {
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) {
      await logAccessViolation(
        resource: widget.title,
        reason: 'unauthenticated_session',
      );
      return false;
    }

    try {
      final row = await sb
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      final role = row?['role']?.toString();
      final allowed = role == 'superadmin';

      if (allowed && !_viewLogged) {
        _viewLogged = true;
        await logAuditEvent(
          'USER_ACTIVITY_SCREEN_VIEW',
          userId: user.id,
          fields: {'screen': widget.title, 'area': 'superadmin'},
        );
      }

      if (!allowed) {
        await logAccessViolation(
          resource: widget.title,
          userId: user.id,
          reason: 'insufficient_role',
          attemptedRole: role,
        );
      }

      return allowed;
    } catch (error) {
      await logSystemError(
        'superadmin_access_guard',
        error,
        userId: user.id,
        fields: {'screen': widget.title},
      );
      return false;
    }
  }

  Future<void> _goToLogin() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await logAuditEvent(
        'USER_ACTIVITY_SIGN_OUT',
        userId: user.id,
        fields: {'source': 'superadmin_access_guard'},
      );
    }
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return FutureBuilder<bool>(
      future: _allowedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: themeBg,
            body: const SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Checking SuperAdmin access...',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.data == true) {
          return widget.child;
        }

        return Scaffold(
          backgroundColor: themeBg,
          body: SafeArea(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This screen is only available to SuperAdmin accounts. Please sign in with an authorized account to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _goToLogin,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Back to Login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E40AF),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
