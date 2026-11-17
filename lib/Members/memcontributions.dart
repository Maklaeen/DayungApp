import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/widgets/record_data_table.dart';

// Color palette

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryDark = Color(0xFF083366);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
const kNeutralText = Color(0xFF1F2937);
const kSubtleText = Color(0xFF4B5563);

class MembersContributionHistory extends StatefulWidget {
  final int dayungUnitId;
  const MembersContributionHistory({
    super.key,
    required this.dayungUnitId,
    this.onNavBarVisible,
  });

  final ValueChanged<bool>? onNavBarVisible;

  @override
  State<MembersContributionHistory> createState() =>
      _MembersContributionHistoryState();
}

class _MembersContributionHistoryState
    extends State<MembersContributionHistory> {
  Map<String, dynamic>? _selectedDayungUnitObj;
  RealtimeChannel? _notifChannel;
  String? selectedDayungUnit;
  // ignore: unused_field
  String? _profileUrl;
  // ignore: unused_field
  int _unreadNotifCount = 0;
  int? _dayungId;
  // ignore: unused_field
  final bool _loading = false;
  List<Map<String, dynamic>> _paidContributions = [];
  String _selectedStatus = 'all';
  String? _contributionError;
  bool _loadingPaid = true;

  void _setStateSafe(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _subscribeToNotifications();
    _loadDayungUnit();
    _loadProfileImage();
    _fetchPaidContributions();
    widget.onNavBarVisible?.call(true);
  }

  @override
  void dispose() {
    // Properly clean up the realtime channel to stop callbacks after dispose
    try {
      _notifChannel?.unsubscribe();
      if (_notifChannel != null) {
        Supabase.instance.client.removeChannel(_notifChannel!);
      }
    } catch (_) {}
    _notifChannel = null;
    widget.onNavBarVisible?.call(true);
    super.dispose();
  }

  void _subscribeToNotifications() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final channel = Supabase.instance.client.channel(
      'member_contrib_notifications_$userId',
    );
    _notifChannel = channel;

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: userId,
      ),
      callback: (payload) {
        if (!mounted) return; // guard callback after dispose
        final newNotif = payload.newRecord as Map<String, dynamic>?;
        _showNotificationModal(
          newNotif?['title'] ?? 'Notification',
          newNotif?['body'] ?? '',
        );
      },
    );

    channel.subscribe();
  }

  void _showNotificationModal(String title, String body) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchUnreadNotifCount() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungId;
    if (uid == null || unitId == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }
    try {
      final notifRows = await sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .eq('dayung_unit_id', unitId)
          .isFilter('read_at', null);
      final notifCount = (notifRows as List).length;

      final annRows = await sb
          .from('announcements')
          .select('id')
          .eq('dayung_unit_id', unitId);
      final annIds = (annRows as List).map((r) => (r as Map)['id']).toList();

      int annCount = 0;
      if (annIds.isNotEmpty) {
        final reads = await sb
            .from('announcement_reads')
            .select('announcement_id')
            .eq('user_id', uid)
            .inFilter('announcement_id', annIds);
        final readIds = Set.from(
          (reads as List).map((r) => (r as Map)['announcement_id']),
        );
        annCount = annIds.where((id) => !readIds.contains(id)).length;
      }
      if (mounted) setState(() => _unreadNotifCount = notifCount + annCount);
    } catch (_) {
      if (mounted) setState(() => _unreadNotifCount = 0);
    }
  }

  Future<void> _loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson != null) {
      try {
        final unit = jsonDecode(unitJson);
        _setStateSafe(() {
          selectedDayungUnit = unit['name'];
          _selectedDayungUnitObj = Map<String, dynamic>.from(unit as Map);
          final rawId = _selectedDayungUnitObj?['id'];
          _dayungId = rawId is int ? rawId : int.tryParse('$rawId'); // NEW
        });
        if (mounted && (unit['name']?.toString().isNotEmpty ?? false)) {
          context.read<DayungUnitProvider>().setDayungUnit(
            unit['name'],
            obj: _selectedDayungUnitObj,
          );
        }
      } catch (_) {
        await prefs.remove('selectedDayungUnit');
        _setStateSafe(() {
          selectedDayungUnit = 'Dayung';
          _selectedDayungUnitObj = null;
          _dayungId = null; // NEW
        });
      }
    } else {
      _setStateSafe(() {
        selectedDayungUnit = 'Dayung';
        _selectedDayungUnitObj = null;
        _dayungId = null; // NEW
      });
    }
    if (!mounted) return;
    await _fetchPaidContributions();
    await _fetchUnreadNotifCount(); // NEW: compute badge after unit is set
  }

  Future<void> _loadProfileImage() async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser != null) {
      final response = await supabase
          .from('users')
          .select('profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();
      _setStateSafe(() {
        _profileUrl = response?['profile_url'] as String?;
      });
    }
  }

  Future<void> _fetchPaidContributions() async {
    _setStateSafe(() {
      _loadingPaid = true;
      _contributionError = null;
    });
    final supabase = Supabase.instance.client;
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        _setStateSafe(() {
          _paidContributions = [];
          _contributionError = null;
          _loadingPaid = false;
        });
        return;
      }

      // Use the ID passed from dashboard
      final int dayungId = widget.dayungUnitId;
      debugPrint('Contrib: using dayungUnitId=$dayungId');

      var q = supabase
          .from('payments')
          .select(
            'id, amount, status, created_at, dayung_unit_id, userdeceased',
          )
          .eq('user_id', uid)
          .inFilter('status', ['paid', 'unpaid', 'pending']);

      q = q.eq('dayung_unit_id', dayungId);

      final payments = List<Map<String, dynamic>>.from(
        await q.order('created_at', ascending: false),
      );
      debugPrint('Contributions fetched: ${payments.length}');

      if (payments.isEmpty) {
        _setStateSafe(() {
          _paidContributions = [];
          _contributionError = null;
          _loadingPaid = false;
        });
        return;
      }

      // Collect all unique userdeceased IDs
      final userDeceasedIds = payments
          .map((p) => p['userdeceased'])
          .where((id) => id != null && id.toString().isNotEmpty)
          .toSet()
          .toList();

      // Fetch full_name for each userdeceased
      Map<String, String> userDeceasedNames = {};
      if (userDeceasedIds.isNotEmpty) {
        final users = await supabase
            .from('users')
            .select('id, full_name')
            .inFilter('id', userDeceasedIds);
        for (final u in users) {
          userDeceasedNames[u['id'].toString()] = (u['full_name'] ?? '')
              .toString();
        }
      }

      final merged = payments.map((p) {
        final userDeceasedId = p['userdeceased']?.toString();
        final userDeceasedName =
            (userDeceasedId != null &&
                userDeceasedNames[userDeceasedId]?.isNotEmpty == true)
            ? userDeceasedNames[userDeceasedId]
            : 'Membership Payment';
        return {
          'date': (p['created_at'] ?? '').toString(),
          'amount': (p['amount'] is num)
              ? (p['amount'] as num).toDouble()
              : double.tryParse('${p['amount']}') ?? 0.0,
          'userdeceased': userDeceasedName,
          'status': (p['status'] ?? '').toString().toLowerCase() == 'paid'
              ? 'paid'
              : 'unpaid',
        };
      }).toList();

      _setStateSafe(() {
        _paidContributions = merged;
        _contributionError = null;
        _loadingPaid = false;
      });
    } catch (error) {
      debugPrint('Failed to fetch member contributions: $error');
      _setStateSafe(() {
        _paidContributions = [];
        _contributionError = 'Unable to load contributions. Please try again.';
        _loadingPaid = false;
      });
    }
  }

  String _fmtDate(String iso) {
    // Simple yyyy-MM-dd from ISO string
    if (iso.isEmpty) return '';
    final t = iso.split('T').first;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final visibleContributions = _paidContributions
        .where(
          (contribution) =>
              _selectedStatus == 'all' ||
              contribution['status'] == _selectedStatus,
        )
        .toList();

    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      // appBar: AppBar(
      //   backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      //   elevation: 0,
      //   title: Text(
      //     'Contribution History',
      //     style: TextStyle(
      //       color: kText,
      //       fontWeight: FontWeight.bold,
      //       fontSize: 24,
      //       fontFamily: 'Montserrat',
      //     ),
      //   ),
      //   actions: [
      //     Padding(
      //       padding: const EdgeInsets.only(right: 16),
      //       child: CircleAvatar(
      //         backgroundColor: Colors.white,
      //         backgroundImage: _profileUrl != null && _profileUrl!.isNotEmpty
      //             ? NetworkImage(_profileUrl!)
      //             : null,
      //         radius: 20,
      //         child: _profileUrl == null
      //             ? Icon(Icons.person, color: kAccent)
      //             : null,
      //       ),
      //     ),
      //   ],
      // ),
      body: SafeArea(
        child: _loadingPaid
            ? Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: kAccent, strokeWidth: 3),
                      const SizedBox(height: 16),
                      const Text(
                        'Loading contributions...',
                        style: TextStyle(
                          color: kSubText,
                          fontSize: 16,
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final option in const [
                        ('all', 'All'),
                        ('paid', 'Paid'),
                        ('unpaid', 'Unpaid'),
                      ])
                        ChoiceChip(
                          label: Text(option.$2),
                          selected: _selectedStatus == option.$1,
                          onSelected: (_) {
                            setState(() => _selectedStatus = option.$1);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_contributionError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 40, 0, 24),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: kDanger,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _contributionError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: kDanger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _fetchPaidContributions,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (visibleContributions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 40, 0, 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 60,
                            color: kSubtleText.withValues(alpha: .35),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _selectedStatus == 'all'
                                ? 'No contributions yet.'
                                : 'No $_selectedStatus contributions yet.',
                            style: const TextStyle(
                              fontSize: 16,
                              color: kSubtleText,
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _selectedStatus == 'all'
                                ? 'Your contributions will appear here.'
                                : 'Your $_selectedStatus contributions will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: kSubText.withValues(alpha: .75),
                              fontFamily: 'OpenSans',
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    RecordDataTable(
                      minWidth: 640,
                      columns: const [
                        DataColumn(label: Text('Amount')),
                        DataColumn(label: Text('For deceased')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Date')),
                      ],
                      rows: visibleContributions.map((contrib) {
                        final amount = contrib['amount'] ?? 0.0;
                        final userDeceasedId =
                            contrib['userdeceased'] ?? 'Unknown';
                        final date = _fmtDate(contrib['date'] ?? '');
                        final isPaid = contrib['status'] == 'paid';
                        final statusColor = isPaid ? kAccent : kWarn;

                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                '₱${amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.bold,
                                  color: kText,
                                ),
                              ),
                            ),
                            DataCell(Text('For: $userDeceasedId')),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isPaid ? Icons.check_circle : Icons.pending,
                                    color: statusColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isPaid ? 'Paid' : 'Unpaid',
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(Text(date)),
                          ],
                        );
                      }).toList(),
                    ),
                ],
              ),
      ),
    );
  }
}
