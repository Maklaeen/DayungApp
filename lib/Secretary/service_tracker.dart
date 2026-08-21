import 'package:flutter/material.dart';
import 'package:capstone_app/Secretary/add_service_dialog.dart';
import 'package:capstone_app/Secretary/secretary_ui.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryLight = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const kAccentDark = Color(0xFF059669);
const Color kBg = Color(0xFFF8FAFC);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kDanger = Color(0xFFEF4444);
const double kEdge = 16;

final serviceChecklistProvider =
    StateNotifierProvider.family<
      ServiceChecklistNotifier,
      List<Map<String, dynamic>>,
      String
    >((ref, claimId) {
      return ServiceChecklistNotifier(claimId);
    });

class ServiceChecklistNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  final String claimId;
  ServiceChecklistNotifier(this.claimId) : super([]);

  Future<void> removeService(int checklistId) async {
    final sb = Supabase.instance.client;
    try {
      await sb.from('service_checklist').delete().eq('id', checklistId);
      state = state.where((item) => item['id'] != checklistId).toList();
    } catch (e) {
      debugPrint('Error removing service: $e');
    }
  }

  Future<void> fetchServices() async {
    final sb = Supabase.instance.client;
    try {
      final response = await sb
          .from('service_checklist')
          .select()
          .eq('claim_id', claimId);
      state = List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching services: $e');
    }
  }
}

class ServiceTrackerPage extends StatefulWidget {
  final int dayungUnitId;
  final bool allowManage;
  final bool allowJoin;
  final String title;
  final String subtitle;

  const ServiceTrackerPage({
    super.key,
    required this.dayungUnitId,
    this.allowManage = true,
    this.allowJoin = false,
    this.title = 'Service Tracker',
    this.subtitle = '',
  });

  @override
  State<ServiceTrackerPage> createState() => _ServiceTrackerPageState();
}

class _ServiceTrackerPageState extends State<ServiceTrackerPage> {
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  List<Map<String, dynamic>> _notices = [];
  Map<String, List<Map<String, dynamic>>> _servicesByNotice = {};
  Map<String, String> _userNamesById = {};
  String? _currentUserId;
  String _currentUserName = 'You';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final sb = Supabase.instance.client;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _currentUserId = sb.auth.currentUser?.id;
      if (_currentUserId != null) {
        final profile = await sb
            .from('users')
            .select('full_name')
            .eq('id', _currentUserId!)
            .maybeSingle();
        final fullName = (profile?['full_name'] ?? '').toString().trim();
        if (fullName.isNotEmpty) {
          _currentUserName = fullName;
        }
      }

      final response = await sb
          .from('claims')
          .select()
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'Approved')
          .order('date_of_death', ascending: false);
      final notices = List<Map<String, dynamic>>.from(response as List);

      // Collect user_ids and beneficiary_ids
      final userIds = notices
          .where((n) => n['deceased_type'] == 'member' && n['user_id'] != null)
          .map((n) => n['user_id'])
          .toSet()
          .toList();
      final beneficiaryIds = notices
          .where(
            (n) =>
                n['deceased_type'] == 'beneficiary' &&
                n['beneficiary_id'] != null,
          )
          .map((n) => n['beneficiary_id'])
          .toSet()
          .toList();

      // Fetch users and beneficiaries in batch
      Map userMap = {};
      Map beneficiaryMap = {};
      if (userIds.isNotEmpty) {
        final users = await sb
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds);
        userMap = {for (var u in users) u['id']: u['full_name']};
      }
      if (beneficiaryIds.isNotEmpty) {
        final beneficiaries = await sb
            .from('beneficiaries')
            .select('id, full_name')
            .inFilter('id', beneficiaryIds);
        beneficiaryMap = {for (var b in beneficiaries) b['id']: b['full_name']};
      }

      // Attach the correct name to each notice
      for (final notice in notices) {
        if (notice['deceased_type'] == 'member') {
          notice['display_name'] = userMap[notice['user_id']] ?? 'No Name';
        } else if (notice['deceased_type'] == 'beneficiary') {
          notice['display_name'] =
              beneficiaryMap[notice['beneficiary_id']] ?? 'No Name';
        } else {
          notice['display_name'] = 'No Name';
        }
      }

      final servicesByNotice = <String, List<Map<String, dynamic>>>{};
      final userNamesById = <String, String>{
        for (final entry in userMap.entries)
          entry.key.toString(): (entry.value ?? '').toString(),
      };
      final claimIds = notices
          .map((notice) => notice['id'])
          .where((id) => id != null)
          .toList();

      if (claimIds.isNotEmpty) {
        // Fetch only services that are not removed
        final services = await sb
            .from('service_checklist')
            .select()
            .or('is_removed.is.null,is_removed.eq.false');
        debugPrint(
          '--- DEBUG: Raw services fetched from Supabase (is_removed = false) ---',
        );
        debugPrint(services.toString());

        final serviceRows = List<Map<String, dynamic>>.from(services as List);
        final joinedUserIds = <String>{};

        for (final raw in serviceRows) {
          for (final member in _joinedMembersFromValue(raw['joined_members'])) {
            final userId = (member['user_id'] ?? '').trim();
            if (userId.isNotEmpty) {
              joinedUserIds.add(userId);
            }
          }
        }

        final missingUserIds = joinedUserIds
            .where((userId) => !userNamesById.containsKey(userId))
            .toList();

        if (missingUserIds.isNotEmpty) {
          final joinedUsers = await sb
              .from('users')
              .select('id, full_name')
              .inFilter('id', missingUserIds);
          for (final user in List<Map<String, dynamic>>.from(joinedUsers)) {
            userNamesById[user['id'].toString()] = (user['full_name'] ?? '')
                .toString();
          }
        }

        for (final raw in serviceRows) {
          final claimId = _noticeKey({'id': raw['claim_id']});
          if (claimId.isEmpty) continue;
          servicesByNotice.putIfAbsent(claimId, () => []).add(raw);
        }

        for (final entry in servicesByNotice.entries) {
          entry.value.sort((a, b) {
            final aDate = DateTime.tryParse('${a['time_service'] ?? ''}');
            final bDate = DateTime.tryParse('${b['time_service'] ?? ''}');
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return aDate.compareTo(bDate);
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _notices = notices;
        _servicesByNotice = servicesByNotice;
        _userNamesById = userNamesById;
        _loading = false;
      });
      // DEBUG: Print mapping after fetch
      debugPrint('--- DEBUG: Notices ---');
      for (final n in notices) {
        debugPrint(
          'Notice id: \\${n['id']} (as string: \\${n['id']?.toString()}) display_name: \\${n['display_name']}',
        );
      }
      debugPrint('--- DEBUG: Services by Notice ---');
      servicesByNotice.forEach((key, services) {
        debugPrint('NoticeKey: \\$key -> Services count: \\${services.length}');
        for (final s in services) {
          debugPrint(
            '  Service id: \\${s['id']} claim_id: \\${s['claim_id']} service_name: \\${s['service_name']}',
          );
        }
      });
    } catch (e) {
      debugPrint('Error fetching notices/services: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load service tracker data: $e';
      });
    }
  }

  // Always return claim id as a string for correct matching
  String _noticeKey(Map<String, dynamic> notice) =>
      notice['id']?.toString() ?? '';

  String _formatDateValue(dynamic value, {String pattern = 'MMM d, yyyy'}) {
    if (value == null) return 'N/A';
    final date = value is DateTime ? value : DateTime.tryParse('$value');
    if (date == null) return '$value';
    return DateFormat(pattern).format(date);
  }

  String _formatServiceSchedule(dynamic value) {
    if (value == null) return 'Schedule TBD';
    final date = value is DateTime ? value : DateTime.tryParse('$value');
    if (date == null) return '$value';
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  String _serviceRequiredLabel(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return 'Flexible';
    if (text.toLowerCase() == 'all') return 'All members';
    return '$text person${text == '1' ? '' : 's'}';
  }

  bool _serviceAllowsJoin(Map<String, dynamic> service) {
    final text = (service['required'] ?? '').toString().trim().toLowerCase();
    return text.isNotEmpty && text != 'all';
  }

  bool _serviceJoinWindowOpen(Map<String, dynamic> service) {
    final endValue = service['end_time_service'];
    if (endValue == null) return true;

    final endTime = endValue is DateTime
        ? endValue.toLocal()
        : DateTime.tryParse('$endValue')?.toLocal();
    if (endTime == null) return true;

    return !DateTime.now().isAfter(endTime);
  }

  List<Map<String, String>> _joinedMembers(Map<String, dynamic> service) {
    return _joinedMembersFromValue(service['joined_members']);
  }

  List<Map<String, String>> _joinedMembersFromValue(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }

    if (decoded is! List) return const [];

    return decoded
        .whereType<dynamic>()
        .map<Map<String, String>?>((entry) {
          if (entry is Map) {
            final userId = (entry['user_id'] ?? '').toString().trim();
            final fullName = _resolveJoinedMemberName(
              userId,
              (entry['full_name'] ?? '').toString().trim(),
            );
            if (userId.isEmpty && fullName.isEmpty) return null;
            return {'user_id': userId, 'full_name': fullName};
          }
          final value = entry.toString().trim();
          if (value.isEmpty) return null;
          if (_looksLikeUserId(value)) {
            return {
              'user_id': value,
              'full_name': _resolveJoinedMemberName(value, ''),
            };
          }
          return {'user_id': '', 'full_name': value};
        })
        .whereType<Map<String, String>>()
        .toList();
  }

  String _resolveJoinedMemberName(String userId, String fallbackName) {
    if (fallbackName.isNotEmpty) return fallbackName;
    return _userNamesById[userId]?.trim() ?? '';
  }

  bool _looksLikeUserId(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  bool _isCurrentUserJoined(Map<String, dynamic> service) {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) return false;
    return _joinedMembers(
      service,
    ).any((member) => member['user_id'] == currentUserId);
  }

  String _joinedMembersLabel(Map<String, dynamic> service) {
    final names = _joinedMembers(service)
        .map((member) => (member['full_name'] ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) return 'None yet';
    return names.join(', ');
  }

  Future<void> _toggleJoinService(Map<String, dynamic> service) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in again to join a service.'),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final joinedMembers = _joinedMembers(service);
    final alreadyJoined = joinedMembers.any(
      (member) => member['user_id'] == currentUserId,
    );

    final updatedMembers = alreadyJoined
        ? joinedMembers
              .where((member) => member['user_id'] != currentUserId)
              .map((member) => (member['user_id'] ?? '').trim())
              .where((userId) => userId.isNotEmpty)
              .toList()
        : [
            ...joinedMembers
                .map((member) => (member['user_id'] ?? '').trim())
                .where((userId) => userId.isNotEmpty),
            currentUserId,
          ];

    try {
      await Supabase.instance.client
          .from('service_checklist')
          .update({'joined_members': updatedMembers})
          .eq('id', int.parse(service['id'].toString()));

      await _fetchData();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            alreadyJoined ? 'You left the service.' : 'You joined the service.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update service join: $e')),
      );
    }
  }

  List<Map<String, dynamic>> get _visibleNotices {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _notices;

    return _notices.where((notice) {
      final noticeId = _noticeKey(notice);
      final services = _servicesByNotice[noticeId] ?? const [];
      final noticeName = (notice['name'] ?? '').toString().toLowerCase();
      final barangay = (notice['barangay'] ?? '').toString().toLowerCase();
      final serviceNames = services
          .map(
            (service) =>
                (service['service_name'] ?? '').toString().toLowerCase(),
          )
          .join(' ');
      return noticeName.contains(query) ||
          barangay.contains(query) ||
          serviceNames.contains(query);
    }).toList();
  }

  int get _totalServices {
    return _servicesByNotice.values.fold<int>(
      0,
      (sum, items) => sum + items.length,
    );
  }

  int get _scheduledToday {
    final now = DateTime.now();
    return _servicesByNotice.values.expand((items) => items).where((service) {
      final scheduled = DateTime.tryParse(
        '${service['time_service'] ?? ''}',
      )?.toLocal();
      if (scheduled == null) return false;
      return scheduled.year == now.year &&
          scheduled.month == now.month &&
          scheduled.day == now.day;
    }).length;
  }

  int get _noticesWithServices {
    return _notices.where((notice) {
      final noticeId = _noticeKey(notice);
      return (_servicesByNotice[noticeId] ?? const []).isNotEmpty;
    }).length;
  }

  Future<void> _removeService(Map<String, dynamic> service) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove service?'),
        content: Text(
          'Remove ${service['service_name'] ?? 'this service'} from the tracker?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      debugPrint('--- DEBUG: _removeService called ---');
      debugPrint('Service object: $service');
      debugPrint('Service id: ${service['id']?.toString() ?? 'NULL'}');
      final updateQuery = Supabase.instance.client
          .from('service_checklist')
          .update({'is_removed': true})
          .eq('id', int.parse(service['id'].toString()));
      debugPrint('Update query constructed. About to execute.');
      final response = await updateQuery;
      debugPrint('Supabase update response: $response');
      if (response is Map &&
          response.containsKey('error') &&
          response['error'] != null) {
        debugPrint('Supabase error: ${response['error']}');
      }
      await _fetchData();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Service removed from tracker.')),
      );
    } catch (e, stack) {
      debugPrint('Error in _removeService: $e');
      debugPrint('Stack trace: $stack');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to remove service: $e')),
      );
    }
  }

  void _showAddServiceDialog(Map<String, dynamic> notice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AddServiceDialog(deathNotice: notice, onServiceAdded: _fetchData),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kPrimary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceTile(Map<String, dynamic> service) {
    final notes = (service['notes'] ?? '').toString().trim();
    final canJoin =
        widget.allowJoin &&
        _serviceAllowsJoin(service) &&
        _serviceJoinWindowOpen(service);
    final joinedLabel = _joinedMembersLabel(service);
    final isJoined = _isCurrentUserJoined(service);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_rounded, color: kPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (service['service_name'] ?? 'Service').toString(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatServiceSchedule(service['time_service']),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kPrimaryDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Required: ${_serviceRequiredLabel(service['required'])}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: kSubText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_serviceAllowsJoin(service)) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Joined:',
                        style: TextStyle(
                          fontSize: 12,
                          color: kSubText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          joinedLabel,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kPrimaryDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (canJoin) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _toggleJoinService(service),
                      icon: Icon(
                        isJoined
                            ? Icons.person_remove_alt_1_rounded
                            : Icons.volunteer_activism_rounded,
                        size: 18,
                      ),
                      label: Text(isJoined ? 'Leave Service' : 'Join Service'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isJoined ? kDanger : kPrimary,
                        side: BorderSide(
                          color: isJoined ? kDanger : kPrimaryLight,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
                // Progress/track display for start_time_service and end_time_service
                if (service['start_time_service'] != null ||
                    service['end_time_service'] != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        size: 16,
                        color: kPrimaryDark,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Start: '
                        '${_formatServiceSchedule(service['start_time_service'])}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: kPrimaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (service['end_time_service'] != null) ...[
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.flag_rounded,
                          size: 16,
                          color: kAccentDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'End: '
                          '${_formatServiceSchedule(service['end_time_service'])}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: kAccentDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    notes,
                    style: const TextStyle(fontSize: 13, color: kSubText),
                  ),
                ],
              ],
            ),
          ),
          if (widget.allowManage)
            IconButton(
              tooltip: 'Remove service',
              onPressed: () => _removeService(service),
              icon: const Icon(Icons.delete_outline_rounded, color: kDanger),
            ),
        ],
      ),
    );
  }

  Widget _overviewStat({
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tone, size: 16),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: kText,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kSubText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _overviewStat(
                icon: Icons.feed_rounded,
                label: 'Notices',
                value: '${_notices.length}',
                tone: kPrimary,
              ),
              _overviewStat(
                icon: Icons.event_available_rounded,
                label: 'Services',
                value: '$_totalServices',
                tone: kAccentDark,
              ),
              _overviewStat(
                icon: Icons.today_rounded,
                label: 'Today',
                value: '$_scheduledToday',
                tone: const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kPrimary),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildSummaryChip(
                icon: Icons.checklist_rtl_rounded,
                label: '$_noticesWithServices with schedules',
              ),
              if (_searchQuery.trim().isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _searchQuery = ''),
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  label: const Text('Reset search'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kPrimaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Color(0xFFB45309)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Could not load service tracker',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _error ?? 'Unknown error',
                style: const TextStyle(
                  color: kSubText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _fetchData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry fetch'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 42, color: kPrimary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: kSubText),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleNotices = _visibleNotices;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            SecretaryPageHeader(
              title: widget.title,
              icon: Icons.track_changes_rounded,
              usePaymentStyle: true,
            ),
            _loading
                ? const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                ? Expanded(child: _buildErrorState())
                : Expanded(
                    child: RefreshIndicator(
                      onRefresh: _fetchData,
                      child: _notices.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
                              children: [
                                _buildToolbarCard(),
                                _buildEmptyState(
                                  icon: Icons.playlist_add_check_circle_rounded,
                                  title: 'No tracked services yet',
                                  message:
                                      'Recent death notices will appear here so you can schedule services and assign participation.',
                                ),
                              ],
                            )
                          : visibleNotices.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
                              children: [
                                _buildToolbarCard(),
                                _buildEmptyState(
                                  icon: Icons.search_off_rounded,
                                  title: 'No matching notices found',
                                  message:
                                      'Try a different search keyword or clear the current filter.',
                                  action: OutlinedButton.icon(
                                    onPressed: () =>
                                        setState(() => _searchQuery = ''),
                                    icon: const Icon(
                                      Icons.filter_alt_off_rounded,
                                    ),
                                    label: const Text('Reset search'),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
                              itemCount: visibleNotices.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return _buildToolbarCard();
                                }

                                final notice = visibleNotices[index - 1];
                                final services =
                                    _servicesByNotice[_noticeKey(notice)] ?? [];

                                return Container(
                                  decoration: BoxDecoration(
                                    color: kCardBg,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: kBorderColor.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF6FF),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: const Icon(
                                                Icons
                                                    .volunteer_activism_rounded,
                                                color: kPrimary,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (notice['display_name'] ??
                                                            'No Name')
                                                        .toString(),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 18,
                                                      color: kText,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    services.isEmpty
                                                        ? 'No services scheduled yet'
                                                        : '${services.length} active service${services.length == 1 ? '' : 's'} scheduled',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: services.isEmpty
                                                          ? kSubText
                                                          : kAccentDark,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (widget.allowManage)
                                              FilledButton.icon(
                                                onPressed: () =>
                                                    _showAddServiceDialog(
                                                      notice,
                                                    ),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: kPrimary,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 12,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.add_rounded,
                                                  size: 18,
                                                ),
                                                label: const Text('Add'),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _buildMetaChip(
                                              Icons.event_busy_rounded,
                                              'DOD: ${_formatDateValue(notice['date_of_death'])}',
                                            ),
                                            _buildMetaChip(
                                              Icons.cake_rounded,
                                              'DOB: ${_formatDateValue(notice['dob'])}',
                                            ),
                                            _buildMetaChip(
                                              Icons.accessibility_new_rounded,
                                              'Age: ${notice['deceased_age'] ?? 'N/A'}',
                                            ),
                                            if ((notice['barangay'] ?? '')
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                              _buildMetaChip(
                                                Icons.place_rounded,
                                                '${notice['barangay']}',
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Scheduled Services',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: kText,
                                          ),
                                        ),
                                        if (services.isEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 10,
                                            ),
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FAFC),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: kBorderColor.withValues(
                                                  alpha: 0.8,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.info_outline_rounded,
                                                  color: kSubText,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    widget.allowManage
                                                        ? 'No services added yet.'
                                                        : 'No services scheduled yet for this notice.',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: kSubText,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          ...services.map(_buildServiceTile),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
