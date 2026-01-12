import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

// Senior-friendly palette
const kBg = Color(0xFFFAFAF7); // warm off-white
const kText = Color(0xFF1F2937); // dark neutral
const kSubText = Color(0xFF4B5563); // softer dark gray
const kAccent = Color(0xFF3E8E7E); // muted teal

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
  bool _loading = false;
  List<Map<String, dynamic>> _paidContributions = [];
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

    _notifChannel = Supabase.instance.client.channel(
      'member_contrib_notifications_$userId',
    );

    _notifChannel!.onPostgresChanges(
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

    _notifChannel!.subscribe();
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

  Future<void> _goApplyDayung() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DayungSuggestionsPage()));
    await _loadDayungUnit();
    await _fetchPaidContributions();
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
          context.read<DayungUnitProvider>().setDayungUnit(unit['name']);
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

  Future<void> _refresh() async {
    _setStateSafe(() => _loading = true);
    await Future.wait([
      _loadDayungUnit(),
      _loadProfileImage(),
      _fetchPaidContributions(),
    ]);
    _setStateSafe(() => _loading = false);
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
    _setStateSafe(() => _loadingPaid = true);
    final supabase = Supabase.instance.client;
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        _setStateSafe(() {
          _paidContributions = [];
          _loadingPaid = false;
        });
        return;
      }

      // Use the ID passed from dashboard
      final int? dayungId = widget.dayungUnitId;
      debugPrint('Contrib: using dayungUnitId=$dayungId');

      var q = supabase
          .from('payments')
          .select(
            'id, amount, status, created_at, dayung_unit_id, userdeceased',
          )
          .eq('user_id', uid)
          .eq('status', 'paid');

      if (dayungId != null) {
        q = q.eq('dayung_unit_id', dayungId);
      }

      final payments = List<Map<String, dynamic>>.from(
        await q.order('created_at', ascending: false),
      );
      debugPrint('Paid contributions fetched: ${payments.length}');

      if (payments.isEmpty) {
        _setStateSafe(() {
          _paidContributions = [];
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

      final noticeIds = payments
          .map((p) => p['death_notice_id'])
          .where((id) => id != null)
          .cast<int>()
          .toSet()
          .toList();

      Map<int, Map<String, dynamic>> noticeById = {};
      if (noticeIds.isNotEmpty) {
        final notices = List<Map<String, dynamic>>.from(
          await supabase
              .from('death_notices')
              .select('id, name, date_of_death')
              .inFilter('id', noticeIds),
        );
        noticeById = {for (final n in notices) (n['id'] as int): n};
      }

      final merged = payments.map((p) {
        final nid = p['death_notice_id'] as int?;
        final n = nid != null ? noticeById[nid] : null;
        final userDeceasedId = p['userdeceased']?.toString();
        final userDeceasedName =
            (userDeceasedId != null &&
                userDeceasedNames[userDeceasedId]?.isNotEmpty == true)
            ? userDeceasedNames[userDeceasedId]
            : userDeceasedId ?? 'Unknown';
        return {
          'date': (p['created_at'] ?? '').toString(),
          'amount': (p['amount'] is num)
              ? (p['amount'] as num).toDouble()
              : double.tryParse('${p['amount']}') ?? 0.0,
          'date_of_death': n?['date_of_death'],
          'userdeceased': userDeceasedName,
        };
      }).toList();

      _setStateSafe(() {
        _paidContributions = merged;
        _loadingPaid = false;
      });
    } catch (_) {
      _setStateSafe(() {
        _paidContributions = [];
        _loadingPaid = false;
      });
    }
  }

  String _address(Map<String, dynamic> d) {
    final parts = <String>[
      if ((d['barangay'] ?? '').toString().isNotEmpty) d['barangay'],
      if ((d['city'] ?? '').toString().isNotEmpty) d['city'],
    ];
    return parts.join(', ');
  }

  String _fmtDate(String iso) {
    // Simple yyyy-MM-dd from ISO string
    if (iso.isEmpty) return '';
    final t = iso.split('T').first;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [const SizedBox(height: 16)],
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Contribution History',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 20,
                        color: kText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            body: _loadingPaid
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: kAccent,
                            strokeWidth: 3,
                          ),
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
                // ADD: Show "Apply dayung first" when no dayung selected
                : (widget.dayungUnitId == null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 60, 16, 32),
                          children: [
                            Icon(
                              Icons.group_add,
                              size: 64,
                              color: kSubText.withOpacity(.35),
                            ),
                            const SizedBox(height: 16),
                            const Center(
                              child: Text(
                                'Apply dayung first',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'OpenSans',
                                  fontWeight: FontWeight.w700,
                                  color: kSubText,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: _goApplyDayung,
                                icon: const Icon(Icons.how_to_reg),
                                label: const Text(
                                  'Apply Dayung',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _loadingPaid
                              ? 1
                              : _paidContributions.length,
                          itemBuilder: (context, index) {
                            if (_loadingPaid) {
                              return const Padding(
                                padding: EdgeInsets.all(24.0),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (_paidContributions.isEmpty) {
                              return Container(
                                margin: const EdgeInsets.only(top: 32),
                                child: const Center(
                                  child: Text(
                                    'No paid contributions yet.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black54,
                                      fontFamily: 'OpenSans',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final contrib = _paidContributions[index];
                            final amount = contrib['amount'] ?? 0.0;
                            // Display userdeceased id from payments
                            final userDeceasedId =
                                contrib['userdeceased'] ?? 'Unknown';
                            final date = _fmtDate(contrib['date'] ?? '');

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.black12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'You already paid ₱${amount.toStringAsFixed(2)} for $userDeceasedId',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontFamily: 'OpenSans',
                                        fontWeight: FontWeight.w700,
                                        color: kText,
                                      ),
                                    ),
                                    if (date.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 6.0,
                                        ),
                                        child: Text(
                                          'Date: $date',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: kSubText,
                                            fontFamily: 'OpenSans',
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )),
          ),
        ),
      ),
    );
  }
}
