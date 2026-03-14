import 'package:capstone_app/pages/submit_claim.dart'
    hide kSubtleText, kNeutralText, kPrimaryDark, kPrimary;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/providers/claim_tracking_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as r;

// Collor palette
const double kCardRadius = 18;
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF6B7280);
const kAccent = Color(0xFF3B82F6);
const kPrimary = Color(0xFF3B82F6);
const kPrimaryDark = Color(0xFF1E40AF);
const kWarn = Color(0xFFF59E0B);
const kDanger = Color(0xFFEF4444);
const kNeutralText = Color(0xFF1F2937);
const kSubtleText = Color(0xFF6B7280);

class MembersClaimsPage extends StatefulWidget {
  final int dayungUnitId;
  const MembersClaimsPage({
    super.key,
    required this.dayungUnitId,
    this.onNavBarVisible,
  });

  final ValueChanged<bool>? onNavBarVisible;

  @override
  State<MembersClaimsPage> createState() => _MembersClaimsPageState();
}

class _MembersClaimsPageState extends State<MembersClaimsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  RealtimeChannel? _notifChannel;
  bool _submittingModalOpen = false;
  bool _bottomRefreshing = false;
  bool _navBarVisible = true;

  // ignore: unused_field
  List<Map<String, dynamic>> _allClaims = [];
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _history = [];

  String _search = '';
  final _searchCtrl = TextEditingController();

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _subscribeToNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onNavBarVisible?.call(true);
    });

    _tabController =
        TabController(length: 3, vsync: this) // CHANGED: 2 -> 3
          ..addListener(() {
            if (_tabController.indexIsChanging) return;
            _fetchClaims();
          });

    _init();
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _notifChannel = null;

    widget.onNavBarVisible?.call(true);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _subscribeToNotifications() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _notifChannel = Supabase.instance.client.channel(
      'member_claims_notifications_$userId',
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
        if (!mounted) return;
        final newNotif = payload.newRecord as Map<String, dynamic>?;
        if (newNotif != null) {
          _showNotificationModal(
            newNotif['title'] ?? 'Notification',
            newNotif['body'] ?? '',
          );
        }
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

  Future<void> _init() async {
    // await _loadDayungUnit();
    await _fetchClaims();
  }

  Future<void> _refresh() async {
    // await _loadDayungUnit();
    await _fetchClaims();
  }

  Future<void> _triggerBottomRefresh() async {
    if (_bottomRefreshing) return;
    _bottomRefreshing = true;
    try {
      await _refresh();
    } finally {
      _bottomRefreshing = false;
    }
  }

  // Future<void> _loadDayungUnit() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final unitJson = prefs.getString('selectedDayungUnit');
  //   if (unitJson != null) {
  //     try {
  //       final map = Map<String, dynamic>.from(jsonDecode(unitJson));
  //       _safeSetState(() {
  //         _dayungId = map['id'] is int
  //             ? map['id'] as int
  //             : int.tryParse('${map['id']}');
  //         _dayungName = (map['name'] ?? 'Dayung').toString();
  //         _barangay = map['barangay'];
  //         _city = map['city'];
  //       });
  //       await _fetchUnreadNotifCount();
  //     } catch (_) {
  //       _safeSetState(() {
  //         _dayungId = null;
  //         _unreadNotifCount = 0;
  //       });
  //     }
  //   } else {
  //     _safeSetState(() {
  //       _dayungId = null;
  //       _unreadNotifCount = 0;
  //     });
  //   }
  // }

  Future<Map<String, dynamic>> getDeceasedInfo(
    Map<String, dynamic> claim,
  ) async {
    final sb = Supabase.instance.client;
    // Prefer the date stored on the claim
    final claimDod = (claim['date_of_death'] ?? '').toString();

    if (claim['beneficiary_id'] != null) {
      final b = await sb
          .from('beneficiaries')
          .select('full_name, dob')
          .eq('id', claim['beneficiary_id'])
          .maybeSingle();
      return {
        'name': b?['full_name'] ?? 'Beneficiary',
        'dob': b?['dob'] ?? '', // <--- DOB
        'date_of_death': claimDod, // <--- DOD from claim
        'type': 'beneficiary',
      };
    } else {
      final u = await sb
          .from('users')
          .select('full_name, date_of_death, dob')
          .eq('id', claim['user_id'])
          .maybeSingle();
      return {
        'name': u?['full_name'] ?? 'Member',
        'dob': u?['dob'] ?? '', // optional for member
        'date_of_death': claimDod.isNotEmpty
            ? claimDod
            : (u?['date_of_death'] ?? ''),
        'type': 'member',
      };
    }
  }

  // Helper to compute age
  int? _computeAge(String? birthIso, String? deathIso) {
    if (birthIso == null ||
        birthIso.isEmpty ||
        deathIso == null ||
        deathIso.isEmpty) {
      return null;
    }
    final b =
        DateTime.tryParse(birthIso) ??
        DateTime.tryParse('${birthIso}T00:00:00');
    final d =
        DateTime.tryParse(deathIso) ??
        DateTime.tryParse('${deathIso}T00:00:00');
    if (b == null || d == null) return null;
    int age = d.year - b.year;
    final hadBirthday =
        (d.month > b.month) || (d.month == b.month && d.day >= b.day);
    return hadBirthday ? age : age - 1;
  }

  Future<void> _fetchClaims() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _safeSetState(() {
          _allClaims = [];
          _pending = [];
          _history = [];
        });
        return;
      }

      final data = await Supabase.instance.client
          .from('claims')
          .select(
            'id, title, description, status, date_submitted, dayung_unit_id, user_id, beneficiary_id, death_certificate_url, date_of_death, claimedmoney',
          )
          .eq('user_id', user.id)
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('date_submitted', ascending: false);

      debugPrint('Claims fetched: ${(data as List).length}');

      final claims = List<Map<String, dynamic>>.from(data).map((c) {
        final map = Map<String, dynamic>.from(c);

        // Treat as claimed if approved + claimedmoney truthy
        final rawStatus = (map['status'] ?? '').toString();
        final claimedMoneyVal = map['claimedmoney'];

        final claimedMoneyYes = (() {
          if (claimedMoneyVal == null) return false;
          if (claimedMoneyVal is bool) return claimedMoneyVal;
          if (claimedMoneyVal is num) return claimedMoneyVal != 0;
          final s = claimedMoneyVal.toString().toLowerCase();
          return s == 'yes' || s == 'true' || s == '1';
        })();

        if (rawStatus.toLowerCase() == 'approved' && claimedMoneyYes) {
          map['status'] = 'claimed';
        }

        return map;
      }).toList();

      final pending = claims
          .where(
            (c) => (c['status'] ?? '').toString().toLowerCase() == 'pending',
          )
          .toList();
      final history = claims
          .where(
            (c) => (c['status'] ?? '').toString().toLowerCase() != 'pending',
          )
          .toList();

      _safeSetState(() {
        _allClaims = claims;
        _pending = pending;
        _history = history;
      });
    } catch (_) {
      _safeSetState(() {
        _allClaims = [];
        _pending = [];
        _history = [];
      });
    }
  }

  // ...existing code...
  String _displayStatus(String s) {
    // f(extended)
    final low = s.toLowerCase();
    if (low == 'approved') return 'Approved ✓';
    if (low == 'claimed') return 'Claimed ✓'; // already handled
    if (low == 'rejected') return 'Rejected';
    if (low == 'pending') return 'Pending';
    return s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s;
  }

  Color _statusColor(String status) {
    final low = status.toLowerCase();
    if (low == 'approved' || low == 'claimed') return kAccent;
    if (low == 'rejected') return kDanger;
    if (low == 'pending') return kWarn;
    return kSubtleText;
  }

  IconData _statusIcon(String status) {
    final low = status.toLowerCase();
    if (low == 'approved' || low == 'claimed') return Icons.check_circle;
    if (low == 'rejected') return Icons.cancel;
    if (low == 'pending') return Icons.pending;
    return Icons.info;
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    final dt = DateTime.tryParse(date.toString());
    if (dt == null) return date.toString();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Color trackingStepColor(String status, int currentIndex, int stepIndex) {
    if (stepIndex < currentIndex) return kAccent;
    if (stepIndex == currentIndex) {
      final low = status.toLowerCase();
      if (low == 'pending') return kWarn;
      if (low == 'approved' || low == 'claimed') return kAccent;
      if (low == 'rejected') return kDanger;
    }
    return kSubtleText.withValues(alpha: .3);
  }

  IconData trackingStepIcon(String status, int currentIndex, int stepIndex) {
    if (stepIndex < currentIndex) return Icons.check_circle;
    if (stepIndex == currentIndex) return Icons.radio_button_checked;
    return Icons.radio_button_unchecked;
  }

  List<Map<String, dynamic>> _filteredList(bool ongoing) {
    final base = ongoing ? _pending : _history;
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<Map<String, dynamic>>.from(base)
        : base.where((c) {
            final title = (c['title'] ?? '').toString().toLowerCase();
            final id = (c['id'] ?? '').toString().toLowerCase();
            final status = (c['status'] ?? '').toString().toLowerCase();
            final desc = (c['description'] ?? '').toString().toLowerCase();
            return title.contains(q) ||
                id.contains(q) ||
                status.contains(q) ||
                desc.contains(q);
          }).toList();

    filtered.sort((a, b) {
      final ad = DateTime.tryParse('${a['date_submitted']}');
      final bd = DateTime.tryParse('${b['date_submitted']}');
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad); // newest first
    });
    return filtered;
  }

  List<Map<String, dynamic>> _filteredTrackingList() {
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<Map<String, dynamic>>.from(_allClaims)
        : _allClaims.where((c) {
            final title = (c['title'] ?? '').toString().toLowerCase();
            final id = (c['id'] ?? '').toString().toLowerCase();
            final status = (c['status'] ?? '').toString().toLowerCase();
            final desc = (c['description'] ?? '').toString().toLowerCase();
            return title.contains(q) ||
                id.contains(q) ||
                status.contains(q) ||
                desc.contains(q);
          }).toList();

    filtered.sort((a, b) {
      final ad = DateTime.tryParse('${a['date_submitted']}');
      final bd = DateTime.tryParse('${b['date_submitted']}');
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return filtered;
  }

  void _openSubmitSheet() async {
    if (_submittingModalOpen) return;
    // Ensure we have the latest selected unit before opening the form
    // await _loadDayungUnit();

    _submittingModalOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SubmitClaimForm(dayungUnitId: widget.dayungUnitId),
      ),
    ).whenComplete(() {
      _submittingModalOpen = false;
    });
  }

  void _openDetail(Map<String, dynamic> claim) async {
    final status = (claim['status'] ?? '').toString();
    final color = _statusColor(status);

    final deceasedInfo = await getDeceasedInfo(claim);
    final deceasedName = deceasedInfo['name'] ?? '';
    final deceasedDob = deceasedInfo['dob'] ?? '';
    final deceasedDod = deceasedInfo['date_of_death'] ?? '';
    final deceasedType = deceasedInfo['type'] ?? '';
    final deceasedAge = _computeAge(deceasedDob, deceasedDod);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return r.Consumer(
          builder: (ctx, ref, child) {
            final tracking = ref.watch(claimTrackingProvider(status));

            Widget trackingSection() {
              if (tracking.rejected) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kDanger.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kDanger.withValues(alpha: .4)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.cancel, color: kDanger, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This claim was rejected.',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w600,
                            color: kDanger,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tracking Status',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Montserrat',
                      color: kNeutralText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (int i = 0; i < tracking.steps.length; i++) ...[
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: trackingStepColor(
                                    status,
                                    tracking.currentIndex,
                                    i,
                                  ).withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(40),
                                  border: Border.all(
                                    color: trackingStepColor(
                                      status,
                                      tracking.currentIndex,
                                      i,
                                    ).withValues(alpha: .5),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      trackingStepIcon(
                                        status,
                                        tracking.currentIndex,
                                        i,
                                      ),
                                      size: 16,
                                      color: trackingStepColor(
                                        status,
                                        tracking.currentIndex,
                                        i,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        tracking.steps[i],
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'Montserrat',
                                          color: trackingStepColor(
                                            status,
                                            tracking.currentIndex,
                                            i,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (i < tracking.steps.length - 1)
                                Container(
                                  height: 4,
                                  margin: const EdgeInsets.only(top: 6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        trackingStepColor(
                                          status,
                                          tracking.currentIndex,
                                          i,
                                        ),
                                        trackingStepColor(
                                          status,
                                          tracking.currentIndex,
                                          i + 1,
                                        ),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (i < tracking.steps.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (tracking.helperText.isNotEmpty)
                    Text(
                      tracking.helperText,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'OpenSans',
                        fontWeight: FontWeight.w600,
                        color: status.toLowerCase() == 'pending'
                            ? kWarn.withValues(alpha: .9)
                            : kAccent,
                      ),
                    ),
                ],
              );
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Row(
                            children: [
                              Icon(_statusIcon(status), size: 16, color: color),
                              const SizedBox(width: 6),
                              Text(
                                _displayStatus(status),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Montserrat',
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Show only short claim ID (first 6 chars) or remove if you want
                        Text(
                          '',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'OpenSans',
                            color: kSubtleText.withValues(alpha: .8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      (claim['title'] ?? 'Untitled').toString(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                        height: 1.15,
                        color: kNeutralText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: kSubtleText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(claim['date_submitted']),
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w600,
                            color: kSubtleText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Deceased details section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: kBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: kAccent.withValues(alpha: .12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deceasedType == 'beneficiary'
                                ? 'Beneficiary Details'
                                : 'Member Details',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Montserrat',
                              color: kAccent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.person, color: kAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  deceasedName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'OpenSans',
                                    color: kText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.cake, color: kSubText, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                deceasedDob.isNotEmpty
                                    ? 'Born: ${_formatDate(deceasedDob)}'
                                    : 'Born: N/A',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'OpenSans',
                                  color: kSubText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.event, color: kDanger, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                deceasedDod.isNotEmpty
                                    ? 'Died: ${_formatDate(deceasedDod)}'
                                    : 'Died: N/A',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'OpenSans',
                                  color: kDanger,
                                ),
                              ),
                            ],
                          ),
                          if (deceasedAge != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.timeline, color: kAccent, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Age at death: $deceasedAge',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'OpenSans',
                                    color: kAccent,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if ((claim['description'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      Text(
                        (claim['description'] ?? '').toString(),
                        style: const TextStyle(
                          fontSize: 14.2,
                          fontFamily: 'OpenSans',
                          height: 1.32,
                        ),
                      )
                    else
                      Text(
                        'No description provided.',
                        style: TextStyle(
                          fontSize: 13.2,
                          fontFamily: 'OpenSans',
                          fontStyle: FontStyle.italic,
                          color: kSubtleText.withValues(alpha: .8),
                        ),
                      ),
                    const SizedBox(height: 18),
                    trackingSection(),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text(
                          'Close',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ongoingList = _filteredList(true);
    final historyList = _filteredList(false);
    final trackingList = _filteredTrackingList();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 720;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isWide),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 20,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 24 : 16,
                        18,
                        isWide ? 24 : 16,
                        0,
                      ),
                      child: _buildOverviewCard(
                        pendingCount: ongoingList.length,
                        historyCount: historyList.length,
                        trackingCount: trackingList.length,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 24 : 16,
                        16,
                        isWide ? 24 : 16,
                        0,
                      ),
                      child: _searchField(),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 24 : 16,
                        12,
                        isWide ? 24 : 16,
                        12,
                      ),
                      child: _buildTabShell(),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _claimListView(ongoingList, true),
                          _claimListView(historyList, false),
                          _trackingListView(trackingList),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: FloatingActionButton.extended(
          backgroundColor: kPrimaryDark,
          foregroundColor: Colors.white,
          elevation: 4,
          extendedPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: const Text(
            'Submit Claim',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: 'Montserrat',
            ),
          ),
          onPressed: _openSubmitSheet,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader(bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 20,
        20,
        isWide ? 24 : 20,
        isWide ? 36 : 30,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E40AF), Color(0xFF3B82F6), Color(0xFF60A5FA)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Container(
          //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          //   decoration: BoxDecoration(
          //     color: Colors.white.withValues(alpha: 0.16),
          //     borderRadius: BorderRadius.circular(999),
          //   ),
          //   child: const Text(
          //     'Member Claims',
          //     style: TextStyle(
          //       color: Colors.white,
          //       fontSize: 12,
          //       fontWeight: FontWeight.w700,
          //       fontFamily: 'Montserrat',
          //       letterSpacing: 0.2,
          //     ),
          //   ),
          // ),
          // const SizedBox(height: 14),
          // Text(
          //   'Track, review, and submit your claims in one place.',
          //   style: TextStyle(
          //     color: Colors.white,
          //     fontSize: isWide ? 28 : 24,
          //     fontWeight: FontWeight.w800,
          //     fontFamily: 'Montserrat',
          //     height: 1.15,
          //   ),
          // ),
          // const SizedBox(height: 10),
          // Text(
          //   'Claims overview and submission portal for members.',
          //   style: TextStyle(
          //     color: Colors.white.withValues(alpha: 0.88),
          //     fontSize: isWide ? 15 : 14,
          //     fontWeight: FontWeight.w600,
          //     fontFamily: 'OpenSans',
          //     height: 1.4,
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required int pendingCount,
    required int historyCount,
    required int trackingCount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8E6F8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _buildSummaryChip(
            icon: Icons.pending_actions_rounded,
            label: '$pendingCount pending',
            color: kWarn,
            background: const Color(0xFFFFF7E8),
          ),
          _buildSummaryChip(
            icon: Icons.history_rounded,
            label: '$historyCount in history',
            color: kPrimaryDark,
            background: const Color(0xFFEFF6FF),
          ),
          _buildSummaryChip(
            icon: Icons.track_changes_rounded,
            label: '$trackingCount tracking',
            color: const Color(0xFF059669),
            background: const Color(0xFFECFDF5),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'OpenSans',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabShell() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: kPrimaryDark,
        unselectedLabelColor: kSubText,
        padding: const EdgeInsets.all(4),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontFamily: 'Montserrat',
          fontSize: 12,
        ),
        tabs: const [
          Tab(text: 'Pending'),
          Tab(text: 'History'),
          Tab(text: 'Tracking'),
        ],
      ),
    );
  }

  Widget _wrapWithRefreshAndNav(Widget scrollable) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;

        final atBottom =
            n.metrics.pixels >= n.metrics.maxScrollExtent &&
            n.metrics.maxScrollExtent > 0;

        final wantVisible = !atBottom;
        if (wantVisible != _navBarVisible) {
          _navBarVisible = wantVisible;
          widget.onNavBarVisible?.call(_navBarVisible);
        }

        if (atBottom && n is OverscrollNotification && n.overscroll > 0) {
          _triggerBottomRefresh();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 0,
        color: kPrimary, // Material spinner color
        child: scrollable,
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (value) {
        setState(() => _search = value.trim().toLowerCase());
      },
      style: const TextStyle(
        color: kText,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: 'OpenSans',
      ),
      decoration: InputDecoration(
        hintText: 'Search by title, description, or claim status',
        hintStyle: TextStyle(
          color: kSubText.withValues(alpha: 0.85),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontFamily: 'OpenSans',
        ),
        prefixIcon: const Icon(Icons.search_rounded, color: kPrimaryDark),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
                icon: const Icon(Icons.close_rounded, color: kSubText),
              ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: kPrimaryDark, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _claimListView(List<Map<String, dynamic>> list, bool ongoing) {
    if (list.isEmpty) {
      return _buildEmptyState(
        icon: ongoing ? Icons.hourglass_top_rounded : Icons.history_rounded,
        title: ongoing ? 'No pending claims' : 'No claim history yet',
        message: ongoing
            ? 'Your active requests will appear here after submission.'
            : 'Completed or rejected claims will show up here.',
      );
    }

    return _wrapWithRefreshAndNav(
      ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _claimCard(list[i]),
      ),
    );
  }

  Widget _trackingListView(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return _buildEmptyState(
        icon: Icons.track_changes_rounded,
        title: 'No claims to track',
        message: 'Submit a claim to start tracking its progress here.',
      );
    }

    return _wrapWithRefreshAndNav(
      ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _claimCard(list[i]),
      ),
    );
  }

  Widget _claimCard(Map<String, dynamic> claim) {
    final status = (claim['status'] ?? '').toString();
    final title = (claim['title'] ?? 'Untitled').toString();
    final desc = (claim['description'] ?? '').toString().trim();
    final date = _formatDate(claim['date_submitted']);
    final color = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          const BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _openDetail(claim),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_statusIcon(status), color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: kText,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          date,
                          style: const TextStyle(
                            fontFamily: 'OpenSans',
                            fontSize: 13,
                            color: kSubText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _displayStatus(status),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  desc,
                  style: const TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 15,
                    color: kSubText,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.arrow_outward_rounded, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    'View details',
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return _wrapWithRefreshAndNav(
      ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, size: 34, color: kPrimaryDark),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: kSubText,
                    fontFamily: 'OpenSans',
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
