import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart'
    hide kPrimary, kNeutralText, kPrimaryDark, kSubtleText;
import 'package:capstone_app/pages/paymentmethod.dart';
import 'package:capstone_app/pages/contributionhistory.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/profile/profile.dart' hide kPrimary, kWarn;
import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/Auth/login.dart'
    hide kPrimary, kNeutralText, kSubtleText, kPrimaryDark;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/Members/member_header.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Shared palette aligned to Secretary
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);

class MemberDashboardPage extends StatefulWidget {
  const MemberDashboardPage({super.key});
  @override
  State<MemberDashboardPage> createState() => _MemberDashboardPageState();
}

class _MemberDashboardPageState extends State<MemberDashboardPage> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _notifChannel;
  final ScrollController _scrollController = ScrollController();
  int _unreadNotifCount = 0;

  Map<String, dynamic>? _selectedDayungUnitObj;
  String? selectedDayungUnit;

  // ignore: unused_field
  User? _user;
  String _fullName = 'Member';
  String? _profileUrl;

  bool _showNavBar = true;
  // ignore: unused_field
  bool _loadingUser = true;
  int _selectedIndex = 0;

  // Dynamic stats
  int _activeMembersCount = 0;
  bool _loadingActiveMembers = true;

  List<Map<String, dynamic>> _recentCertificates = [];
  bool _loadingCertificates = true;

  List<Map<String, dynamic>> _pendingPaymentsByDeathNotice = [];

  double _pendingPaymentsAmount = 0;
  int _pendingPaymentCount = 0;
  bool _loadingPending = true;

  bool _loadingActivity = true;
  List<Map<String, dynamic>> _latestActivities = [];

  int? _asInt(dynamic v) => v == null ? null : int.tryParse(v.toString());

  @override
  void initState() {
    super.initState();
    _subscribeMembershipApproved();
    _loadOrAskDayung();
    _fetchUnreadNotifCount();
    _loadUserData();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if (current >= maxScroll && _showNavBar) {
        setState(() => _showNavBar = false);
      } else if (current < maxScroll && !_showNavBar) {
        setState(() => _showNavBar = true);
      }
    });
  }

  Future<void> _fetchUnreadNotifCount() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }

    // 1. Unread notifications
    final notifData = await sb
        .from('notifications')
        .select('id')
        .eq('recipient_id', uid)
        .isFilter('read_at', null);

    int notifCount = (notifData as List).length;

    // 2. Unread announcements (for all user's approved dayung units)
    final apps = await sb
        .from('applications')
        .select('dayung_unit_id')
        .eq('user_id', uid)
        .eq('status', 'approved');
    final unitIds = List<Map<String, dynamic>>.from(apps)
        .map((a) => a['dayung_unit_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    int annCount = 0;
    if (unitIds.isNotEmpty) {
      // Get all announcements for user's units
      final annData = await sb
          .from('announcements')
          .select('id')
          .inFilter('dayung_unit_id', unitIds);

      final allAnnIds = (annData as List).map((a) => a['id']).toList();

      // Get which announcements the user has read
      final reads = await sb
          .from('announcement_reads')
          .select('announcement_id')
          .eq('user_id', uid);

      final readIds = Set.from(
        (reads as List).map((r) => r['announcement_id']),
      );

      // Count only announcements the user has NOT read
      annCount = allAnnIds.where((id) => !readIds.contains(id)).length;
    }

    if (mounted) setState(() => _unreadNotifCount = notifCount + annCount);
  }

  Future<bool> _isApprovedForUnit(int unitId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final rows = await supabase
          .from('applications')
          .select('id')
          .eq('user_id', uid)
          .eq('dayung_unit_id', unitId)
          .eq('status', 'approved')
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _subscribeMembershipApproved() {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    _notifChannel?.unsubscribe();
    _notifChannel = sb.channel('member_notifications_${uid}');

    _notifChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            if ((row['type'] ?? '') == 'membership_approved' &&
                row['read_at'] == null) {
              _showAnnouncementDialog(row);
            }
            if ((row['type'] ?? '') == 'announcement' &&
                row['read_at'] == null) {
              _showAnnouncementDialog(row);
            }
          },
        )
        .subscribe();

    _checkUnreadNotifications();
  }

  Future<void> _checkUnreadNotifications() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    final data = await sb
        .from('notifications')
        .select('id, title, body, type, created_at')
        .eq('recipient_id', uid)
        .isFilter('read_at', null)
        .order('created_at', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(data);
    if (list.isNotEmpty) {
      final notif = list.first;
      if (notif['type'] == 'membership_approved' ||
          notif['type'] == 'announcement') {
        _showAnnouncementDialog(notif);
      }
    }
  }

  void _showAnnouncementDialog(Map<String, dynamic> notif) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          backgroundColor: const Color(0xFF8CA6C7), // blueish background
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Announcement',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.amber,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  notif['body']?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () async {
                    final sb = Supabase.instance.client;
                    try {
                      await sb
                          .from('notifications')
                          .update({'read_at': DateTime.now().toIso8601String()})
                          .eq('id', notif['id']);
                    } catch (_) {}
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    await _loadOrAskDayung();
                    await _fetchUnreadNotifCount();
                  },
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: Color(0xFFDDE3EA),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showApprovedDialog(Map<String, dynamic> notif) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text(notif['title']?.toString() ?? 'Approved'),
          content: Text(
            notif['body']?.toString() ??
                'You are now a member. Congratulations!',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final sb = Supabase.instance.client;
                try {
                  await sb
                      .from('notifications')
                      .update({'read_at': DateTime.now().toIso8601String()})
                      .eq('id', notif['id']);
                } catch (_) {}
                if (!mounted) return;
                Navigator.of(context).pop();
                // Refresh member dashboard data and unit selection
                await _loadOrAskDayung(); // uses approved applications
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reloadDayungFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson == null) {
      setState(() {
        selectedDayungUnit = null;
        _selectedDayungUnitObj = null;
      });
      return;
    }
    try {
      final decoded = jsonDecode(unitJson);
      if (decoded is Map) {
        final unit = Map<String, dynamic>.from(decoded);
        final id = _asInt(unit['id']);
        if (id != null && await _isApprovedForUnit(id)) {
          setState(() {
            selectedDayungUnit = unit['name']?.toString();
            _selectedDayungUnitObj = unit;
          });
        } else {
          await prefs.remove('selectedDayungUnit');
          setState(() {
            selectedDayungUnit = null;
            _selectedDayungUnitObj = null;
          });
        }
      } else {
        await prefs.remove('selectedDayungUnit');
        setState(() {
          selectedDayungUnit = null;
          _selectedDayungUnitObj = null;
        });
      }
    } catch (_) {
      await prefs.remove('selectedDayungUnit');
      setState(() {
        selectedDayungUnit = null;
        _selectedDayungUnitObj = null;
      });
    }
  }

  Future<void> _loadOrAskDayung() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson != null) {
      try {
        final unit = jsonDecode(unitJson);
        final id = _asInt((unit as Map)['id']);
        if (id != null && await _isApprovedForUnit(id)) {
          setState(() {
            selectedDayungUnit = unit['name'];
            _selectedDayungUnitObj = Map<String, dynamic>.from(unit);
          });
          await _fetchAllStats(); // ...existing code...
          return;
        } else {
          await prefs.remove('selectedDayungUnit');
        }
      } catch (_) {
        await prefs.remove('selectedDayungUnit');
      }
    }

    // Auto-pick latest APPROVED application (do NOT use users.dayung_unit_id)
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        final apps = await supabase
            .from('applications')
            .select('dayung_unit_id, approved_at')
            .eq('user_id', uid)
            .eq('status', 'approved')
            .order('approved_at', ascending: false)
            .limit(1);

        final list = (apps as List);
        if (list.isNotEmpty) {
          final dId = _asInt((list.first as Map)['dayung_unit_id']);
          if (dId != null) {
            final unit = await supabase
                .from('dayung_units')
                .select('id, name, barangay, city')
                .eq('id', dId)
                .maybeSingle();
            if (unit != null) {
              await prefs.setString('selectedDayungUnit', jsonEncode(unit));
              setState(() {
                _selectedDayungUnitObj = Map<String, dynamic>.from(unit);
                selectedDayungUnit = unit['name']?.toString();
              });
              await _fetchAllStats(); // ...existing code...
              return;
            }
          }
        }
      }
    } catch (_) {
      // ignore and fallback to manual pick
    }

    // No approved membership -> open selection flow (may show none)
    await _navigateAndPickUnit(); // ...existing code...
  }

  Future<void> _fetchAllStats() async {
    await Future.wait([
      _fetchActiveMembers(),
      _fetchRecentDeaths(),
      _fetchPendingPayments(),
      _fetchRecentActivity(),
    ]);
  }

  Future<void> _fetchRecentActivity() async {
    setState(() => _loadingActivity = true);
    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser?.id;
      final dayungId = _asInt(_selectedDayungUnitObj?['id']);

      // Debug prints
      debugPrint('DEBUG: User ID: $uid, Dayung ID: $dayungId');

      if (uid == null || dayungId == null) {
        setState(() {
          _latestActivities = [];
          _loadingActivity = false;
        });
        return;
      }

      // 1. Get most recent paid contribution
      final contribResult = await supabase
          .from('payments')
          .select('amount, created_at, death_notice_id')
          .eq('user_id', uid)
          .eq('status', 'paid')
          .order('created_at', ascending: false)
          .limit(1);

      // Debug
      debugPrint('DEBUG: Contributions result: $contribResult');
      final recentContributions = contribResult as List? ?? [];

      // 2. Get most recent claim update
      final claimResult = await supabase
          .from('claims')
          .select('status, title, date_submitted')
          .eq('user_id', uid)
          .order('date_submitted', ascending: false)
          .limit(1);

      // Debug
      debugPrint('DEBUG: Claims result: $claimResult');
      final recentClaims = claimResult as List? ?? [];

      List<Map<String, dynamic>> activities = [];

      // Always add today's date
      activities.add({
        'icon': Icons.calendar_today,
        'color': kPrimary,
        'text': _formatTodayDate(),
        'date': DateTime.now().toIso8601String(),
        'type': 'date',
      });

      // Add contribution if exists
      if (recentContributions.isNotEmpty && recentContributions is List) {
        final contrib = recentContributions[0];
        final amount = (contrib['amount'] is num)
            ? (contrib['amount'] as num).toDouble()
            : double.tryParse('${contrib['amount']}') ?? 0.0;

        activities.add({
          'icon': Icons.attach_money,
          'color': kAccent,
          'text': 'Paid ₱${amount.toStringAsFixed(0)} contribution',
          'date': contrib['created_at'],
          'type': 'payment',
        });
      }

      // Add claim if exists
      if (recentClaims.isNotEmpty && recentClaims is List) {
        final claim = recentClaims[0];
        final status = (claim['status'] ?? '').toString();

        String statusText = 'Claim ';
        IconData icon = Icons.circle;
        Color color = kAccent;

        switch (status.toLowerCase()) {
          case 'approved':
            statusText += 'approved';
            icon = Icons.check_circle;
            color = kAccent;
            break;
          case 'rejected':
            statusText += 'rejected';
            icon = Icons.cancel_outlined;
            color = Colors.red;
            break;
          case 'pending':
            statusText += 'pending';
            icon = Icons.pending_actions;
            color = Colors.orange;
            break;
          default:
            statusText += status;
        }

        activities.add({
          'icon': icon,
          'color': color,
          'text': statusText,
          'date': claim['date_submitted'],
          'type': 'claim',
        });
      }

      // Sort by date (most recent first)
      activities.sort((a, b) {
        final aDate =
            DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime.now();
        final bDate =
            DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime.now();
        return bDate.compareTo(aDate);
      });

      // Limit to 3 most recent activities
      activities = activities.take(3).toList();

      setState(() {
        _latestActivities = activities;
        _loadingActivity = false;
      });
    } catch (e) {
      setState(() {
        _latestActivities = [];
        _loadingActivity = false;
      });
    }
  }

  // Helper to format today's date
  String _formatTodayDate() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Future<void> _refreshDashboard() async {
    await _loadUserData();
    await _reloadDayungFromPrefs();
    await _fetchAllStats();
  }

  Future<void> _loadUserData() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      _redirectToLogin();
      return;
    }
    try {
      final response = await supabase
          .from('users')
          .select('full_name, sex, profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();

      final full = (response?['full_name'] as String?)?.trim();
      final sex = response?['sex'];
      setState(() {
        _user = currentUser;
        _fullName = '${_getTitle(sex)} ${full ?? 'Member'}'.trim();
        _profileUrl = (response?['profile_url'] as String?)?.trim();
        _loadingUser = false;
      });
    } catch (_) {
      setState(() {
        _loadingUser = false;
        _fullName = 'Member';
      });
    }
  }

  String _getTitle(dynamic sex) {
    final s = (sex ?? '').toString().toLowerCase().trim();
    if (s == 'male') return 'Mr.';
    if (s == 'female') return 'Mrs.';
    return '';
  }

  Future<void> _navigateAndPickUnit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelectDayungPage()),
    );
    if (result != null && result is Map) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedDayungUnit', jsonEncode(result));
      setState(() {
        selectedDayungUnit = result['name'];
        _selectedDayungUnitObj = Map<String, dynamic>.from(result);
      });
      context.read<DayungUnitProvider>().setDayungUnit(result['name']);
      await _fetchAllStats();
    }
  }

  Future<void> _fetchActiveMembers() async {
    setState(() => _loadingActiveMembers = true);
    try {
      final id = _asInt(_selectedDayungUnitObj?['id']);
      if (id == null) {
        _activeMembersCount = 0;
      } else {
        // Get approved application user_ids in this dayung
        final appRows = await supabase
            .from('applications')
            .select('user_id')
            .eq('dayung_unit_id', id)
            .eq('status', 'approved');

        final userIds = <String>[
          for (final r in (appRows as List))
            if ((r as Map)['user_id'] != null) (r['user_id']).toString(),
        ];
        if (userIds.isEmpty) {
          _activeMembersCount = 0;
        } else {
          final users = await supabase
              .from('users')
              .select('id, is_deceased')
              .inFilter('id', userIds);
          _activeMembersCount = (users as List)
              .where((u) => ((u as Map)['is_deceased'] ?? false) == false)
              .length;
        }
      }
    } catch (_) {
      _activeMembersCount = 0;
    } finally {
      if (mounted) setState(() => _loadingActiveMembers = false);
    }
  }

  Future<void> _fetchRecentDeaths() async {
    setState(() => _loadingCertificates = true);
    try {
      final unitId = _asInt(_selectedDayungUnitObj?['id']);
      if (unitId == null) {
        _recentCertificates = [];
      } else {
        final data = await supabase
            .from('death_notices')
            .select('id, name, date_of_death, dayung_unit_id')
            .eq('dayung_unit_id', unitId)
            .order('date_of_death', ascending: false)
            .limit(5);

        // Normalize to existing UI keys
        _recentCertificates = (data as List)
            .map(
              (e) => {
                'deceased_name': (e as Map)['name'],
                'date_of_death': e['date_of_death'],
                'dayung_unit_id': e['dayung_unit_id'],
              },
            )
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {
      _recentCertificates = [];
    } finally {
      if (mounted) setState(() => _loadingCertificates = false);
    }
  }

  Future<void> _fetchPendingPayments() async {
    setState(() => _loadingPending = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      final dayungId = _asInt(_selectedDayungUnitObj?['id']);
      if (uid == null || dayungId == null) {
        _pendingPaymentsAmount = 0;
        _pendingPaymentCount = 0;
        _pendingPaymentsByDeathNotice = [];
      } else {
        final rows = await supabase
            .from('payments')
            .select('amount, status, user_id, death_notice_id')
            .eq('user_id', uid)
            .eq('dayung_unit_id', dayungId)
            .eq('status', 'pending');

        double total = 0;
        int cnt = 0;
        final noticeTotals = <int, double>{};
        final noticeCounts = <int, int>{};

        for (final r in rows as List) {
          final m = r as Map<String, dynamic>;
          final noticeId = m['death_notice_id'] as int?;
          final amt = (m['amount'] is num)
              ? (m['amount'] as num).toDouble()
              : 0.0;
          if (noticeId != null) {
            noticeTotals[noticeId] = (noticeTotals[noticeId] ?? 0) + amt;
            noticeCounts[noticeId] = (noticeCounts[noticeId] ?? 0) + 1;
          }
          total += amt;
          cnt++;
        }

        List<Map<String, dynamic>> notices = [];
        if (noticeTotals.isNotEmpty) {
          final ids = noticeTotals.keys.toList();
          final noticeRows = await supabase
              .from('death_notices')
              .select('id, name, date_of_death')
              .inFilter('id', ids);
          final noticeMap = {
            for (final n in (noticeRows as List))
              (n as Map)['id'] as int: Map<String, dynamic>.from(n),
          };
          for (final id in ids) {
            notices.add({
              'id': id,
              'name': noticeMap[id]?['name'] ?? 'Death Notice #$id',
              'date_of_death': noticeMap[id]?['date_of_death'],
              'amount': noticeTotals[id],
              'count': noticeCounts[id],
            });
          }
        }

        _pendingPaymentsAmount = total;
        _pendingPaymentCount = cnt;
        _pendingPaymentsByDeathNotice = notices;
      }
    } catch (_) {
      _pendingPaymentsAmount = 0;
      _pendingPaymentCount = 0;
      _pendingPaymentsByDeathNotice = [];
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  void _redirectToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
    );
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  List<Widget> get _pages => [
    _buildHomePage(context),
    const ContributionHistory(),
    const ClaimsPage(),
  ];

  get _dayungUnitId => null;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          SafeArea(
            child: IndexedStack(index: _selectedIndex, children: _pages),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: IgnorePointer(
                ignoring: !_showNavBar,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _showNavBar ? 1.0 : 0.0,
                  child: Container(
                    height: 76,
                    margin: EdgeInsets.symmetric(
                      horizontal: isWide ? width * 0.15 : 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _navBarItem(
                          icon: Icons.home,
                          label: 'Home',
                          selected: _selectedIndex == 0,
                          onTap: () => setState(() => _selectedIndex = 0),
                        ),
                        _navBarItem(
                          icon: FontAwesomeIcons.globe,
                          label: 'Contributions',
                          selected: _selectedIndex == 1,
                          onTap: () => setState(() => _selectedIndex = 1),
                        ),
                        _navBarItem(
                          icon: Icons.receipt_long,
                          label: 'Claims',
                          selected: _selectedIndex == 2,
                          onTap: () => setState(() => _selectedIndex = 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBarItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: selected ? kPrimary : kNeutralText,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? kPrimary : kNeutralText, size: 32),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? kPrimary : kNeutralText,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.2,
                fontFamily: 'OpenSans',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomePage(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: _buildHeader(),
            ),
            const SizedBox(height: 16),
            const Divider(thickness: 1, height: 24, color: Colors.grey),
            const SizedBox(height: 13),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildWelcomeMessage(),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCards(isWide),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildNextPaymentCard(isWide),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildRecentActivity(isWide),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final dayungName = _selectedDayungUnitObj?['name'] ?? 'Dayung';
    final barangay = _selectedDayungUnitObj?['barangay'];
    final city = _selectedDayungUnitObj?['city'];
    final subtitle = (barangay != null)
        ? '$barangay${city != null ? ', $city' : ''}'
        : null;

    return MemberHeader(
      title: dayungName,
      subtitle: subtitle,
      profileUrl: _profileUrl,
      onNotificationTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationPage()),
        );
        await _fetchUnreadNotifCount(); // Refresh badge after returning
      },
      onProfileTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      },
      notificationBadge: _unreadNotifCount > 0 ? _unreadNotifCount : null,
    );
  }

  Widget _buildWelcomeMessage() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          'Maayung buntag,\n$_fullName!',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: kPrimaryDark, // CHANGED to match secretary header tone
            fontFamily: 'Montserrat',
            letterSpacing: .6,
            height: 1.1,
          ),
        ),
      ),
    ],
  );

  Widget _buildCards(bool isWide) {
    // Active Members card value
    final activeValue = _loadingActiveMembers
        ? '…'
        : _activeMembersCount.toString();

    // Recent deaths card lines
    String recentDeathsValue;
    if (_loadingCertificates) {
      recentDeathsValue = 'Loading…';
    } else if (_recentCertificates.isEmpty) {
      recentDeathsValue = 'None';
    } else {
      final names = _recentCertificates
          .map((e) => (e['deceased_name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.length <= 2) {
        recentDeathsValue = names.join('\n');
      } else {
        recentDeathsValue =
            '${names.take(2).join('\n')}\n+${names.length - 2} more';
      }
    }

    final pendingValue = _loadingPending
        ? '…'
        : '₱ ${_pendingPaymentsAmount.toStringAsFixed(0)}';
    final pendingSubtitle = _loadingPending
        ? ''
        : (_pendingPaymentCount > 0
              ? '$_pendingPaymentCount pending'
              : 'No pending');

    final cards = [
      _dashboardCard(
        color: const Color(0xFFD8EEFF),
        icon: Icons.groups,
        iconColor: Colors.blue[700],
        title: "Total Active\nMembers",
        value: activeValue,
      ),
      _dashboardCard(
        color: const Color(0xFFFFDAF6),
        icon: FontAwesomeIcons.dove,
        iconColor: Colors.purple[400],
        title: "Recent Deaths",
        value: recentDeathsValue,
        isDeathNotice: true,
        context: context,
        onTap: () {
          final id = _asInt(_selectedDayungUnitObj?['id']);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecentDeathNotices(dayungUnitId: id),
            ),
          );
        },
      ),
      _dashboardCard(
        color: const Color(0xFFFEFBDC),
        icon: Icons.account_balance_wallet,
        iconColor: Colors.orange[700],
        title: "Pending\nPayments",
        value: pendingValue,
        subtitle: pendingSubtitle,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: cards
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: c,
                  ),
                )
                .toList(),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
            const SizedBox(width: 12),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _dashboardCard({
    required Color color,
    required IconData icon,
    required Color? iconColor,
    required String title,
    required String value,
    String subtitle = "",
    double iconSize = 30,
    bool isDeathNotice = false,
    BuildContext? context,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 220,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: kPrimary.withOpacity(.12), // NEW ripple color
        highlightColor: kPrimary.withOpacity(.05),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: iconSize, color: iconColor),
              const SizedBox(height: 8),
              AutoSizeText(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: kNeutralText,
                  fontFamily: 'Montserrat',
                  height: 1.15,
                ),
                maxLines: 2,
                minFontSize: 11,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: isDeathNotice
                    ? _recentDeathsValueWidget(value, context)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AutoSizeText(
                            value,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 30,
                              color: kNeutralText,
                              fontFamily: 'Montserrat',
                            ),
                            maxLines: 2,
                            minFontSize: 12,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: AutoSizeText(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: kSubtleText.withOpacity(.9),
                                  fontFamily: 'OpenSans',
                                ),
                                maxLines: 2,
                                minFontSize: 10,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentDeathsValueWidget(String raw, BuildContext? ctx) {
    if (raw == 'Loading…') {
      return const Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: kPrimary, // unified color
          ),
        ),
      );
    }
    if (raw == 'None') {
      return const Center(
        child: Text(
          "None",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Montserrat',
            color: kNeutralText,
          ),
        ),
      );
    }
    final lines = raw.split('\n');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...lines
            .where((l) => !l.startsWith('+'))
            .map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      FontAwesomeIcons.dove,
                      size: 14,
                      color: kNeutralText,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: kNeutralText,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (lines.any((l) => l.startsWith('+')))
          Text(
            lines.firstWhere((l) => l.startsWith('+')),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              color: kSubtleText,
            ),
          ),
        TextButton(
          onPressed: () {
            final id = _asInt(_selectedDayungUnitObj?['id']);
            if (ctx != null) {
              Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => RecentDeathNotices(dayungUnitId: id),
                ),
              );
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: kPrimary,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            "View All",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextPaymentCard(bool isWide) {
    final loading = _loadingPending;
    final amount = loading
        ? '…'
        : '₱ ${_pendingPaymentsAmount.toStringAsFixed(0)}';
    final dueDate = 'Due soon';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 32 : 24),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPrimary.withOpacity(.25), width: 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next Payment Due:',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: kPrimaryDark,
              fontFamily: 'Montserrat',
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: kPrimaryDark,
                  fontFamily: 'Montserrat',
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(width: 10),
              if (!_loadingPending && _pendingPaymentsByDeathNotice.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _pendingPaymentsByDeathNotice.map((p) {
                      final amt = (p['amount'] is num)
                          ? (p['amount'] as num).toDouble()
                          : 0.0;
                      final name = (p['name'] ?? '').toString();
                      final dod = p['date_of_death'];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                '₱${amt.toStringAsFixed(0)} for $name',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: kPrimaryDark,
                                  fontFamily: 'Montserrat',
                                ),
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                            if (dod != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                '($dod)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: kSubtleText,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dueDate,
            style: TextStyle(
              color: kSubtleText.withOpacity(.9),
              fontSize: 14.5,
              fontFamily: 'OpenSans',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loading
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PaymentMethodPage(
                            dayungUnitId: _asInt(_selectedDayungUnitObj?['id']),
                          ),
                        ),
                      ).then((_) {
                        _refreshDashboard();
                      });
                    },
              icon: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.payments_rounded),
              label: Text(
                loading ? 'Loading…' : 'Pay Now',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamily: 'Montserrat',
                  letterSpacing: .3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kPrimaryDark,
            fontFamily: 'Montserrat',
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 40 : 20,
            vertical: isWide ? 24 : 16,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _loadingActivity
              ? const Center(child: CircularProgressIndicator())
              : _latestActivities.isEmpty ||
                    _latestActivities.length <=
                        1 // Updated condition
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No recent activity',
                      style: TextStyle(
                        fontSize: 16,
                        color: kSubtleText,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (int i = 0; i < _latestActivities.length; i++) ...[
                      _ActivityRow(
                        icon: _latestActivities[i]['icon'],
                        color: _latestActivities[i]['color'],
                        text: _latestActivities[i]['text'],
                      ),
                      if (i < _latestActivities.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _ActivityRow({
    required this.icon,
    required this.color,
    required this.text,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
            ),
          ),
        ),
      ],
    );
  }
}
