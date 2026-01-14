import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart'
    hide kBg, kPrimary, kPrimaryDark, kAccent, kDanger, kWarn;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/pages/submit_claim.dart'
    hide kSubtleText, kNeutralText, kPrimaryDark, kPrimary;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/providers/claim_tracking_provider.dart';
import 'package:provider/provider.dart' hide Consumer;
import 'package:flutter_riverpod/flutter_riverpod.dart' as r;

const double kCardRadius = 18;
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
  bool _loading = true;
  bool _submittingModalOpen = false;
  bool _bottomRefreshing = false;
  bool _navBarVisible = true;

  // ignore: unused_field
  List<Map<String, dynamic>> _allClaims = [];
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _history = [];

  String _search = '';
  final _searchCtrl = TextEditingController();

  String? _profileUrl;
  String _dayungName = 'Dayung';
  String? _barangay;
  String? _city;
  int _unreadNotifCount = 0;

  Future<void> _goApplyDayung() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DayungSuggestionsPage()));
    //await _loadDayungUnit();
    await _fetchClaims();
  }

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
    _safeSetState(() => _loading = true);
    // await _loadDayungUnit();
    await _loadProfileImage();
    await _fetchClaims();
    if (!mounted) return;
    _safeSetState(() => _loading = false);
  }

  Future<void> _refresh() async {
    _safeSetState(() => _loading = true);
    // await _loadDayungUnit();
    await _fetchClaims();
    await _loadProfileImage();
    if (!mounted) return;
    _safeSetState(() => _loading = false);
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

  Future<void> _fetchUnreadNotifCount() async {
    // NEW
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = widget.dayungUnitId;
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

  Future<void> _loadProfileImage() async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    try {
      final row = await supabase
          .from('users')
          .select('profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();
      _safeSetState(() {
        _profileUrl = (row?['profile_url'] ?? '').toString().trim();
      });
    } catch (_) {}
  }

  Future<void> _fetchClaims() async {
    _safeSetState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _safeSetState(() {
          _allClaims = [];
          _pending = [];
          _history = [];
          _loading = false;
        });
        return;
      }

      if (widget.dayungUnitId == null) {
        _safeSetState(() {
          _allClaims = [];
          _pending = [];
          _history = [];
          _loading = false;
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
        _loading = false;
      });
    } catch (_) {
      _safeSetState(() {
        _allClaims = [];
        _pending = [];
        _history = [];
        _loading = false;
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
    return kSubtleText.withOpacity(.3);
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
                    color: kDanger.withOpacity(.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kDanger.withOpacity(.4)),
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
                                  ).withOpacity(.12),
                                  borderRadius: BorderRadius.circular(40),
                                  border: Border.all(
                                    color: trackingStepColor(
                                      status,
                                      tracking.currentIndex,
                                      i,
                                    ).withOpacity(.5),
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
                            ? kWarn.withOpacity(.9)
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
                            color: color.withOpacity(.12),
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
                          '#${claim['id'].toString().substring(0, 6)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'OpenSans',
                            color: kSubtleText.withOpacity(.8),
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
                        border: Border.all(color: kAccent.withOpacity(.12)),
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
                          color: kSubtleText.withOpacity(.8),
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

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: Text(
          'Claims',
          style: TextStyle(
            color: kText,
            fontWeight: FontWeight.bold,
            fontSize: 24,
            fontFamily: 'Montserrat',
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Stack(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage:
                      _profileUrl != null && _profileUrl!.isNotEmpty
                      ? NetworkImage(_profileUrl!)
                      : null,
                  child: _profileUrl == null
                      ? Icon(Icons.person, color: kAccent)
                      : null,
                  radius: 20,
                ),
                if (_unreadNotifCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: kAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_unreadNotifCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _searchField(),
            ),
            TabBar(
              controller: _tabController,
              labelColor: kAccent,
              unselectedLabelColor: kSubText,
              indicatorColor: kAccent,
              labelStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'Montserrat',
              ),
              tabs: [
                Tab(text: 'Pending'),
                Tab(text: 'History'),
                Tab(text: 'Tracking'),
              ],
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        icon: Icon(Icons.add),
        label: Text(
          'Submit Claim',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: _openSubmitSheet,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Search claims...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
              ),
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: kPrimaryDark, width: 1.6),
        ),
      ),
    );
  }

  Widget _claimListView(List<Map<String, dynamic>> list, bool ongoing) {
    // Use widget.dayungUnitId instead of _dayungId
    if (widget.dayungUnitId == null) {
      return _wrapWithRefreshAndNav(
        ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 120),
          children: [
            Icon(
              Icons.group_add,
              size: 64,
              color: kSubtleText.withOpacity(.35),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Apply dayung first',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'OpenSans',
                  fontWeight: FontWeight.w700,
                  color: kSubtleText,
                ),
              ),
            ),
          ],
        ),
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

  Widget _trackingListView(List<Map<String, dynamic>> list) {
    if (widget.dayungUnitId == null) {
      // Reuse apply prompt
      return _wrapWithRefreshAndNav(
        ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 120),
          children: [
            Icon(
              Icons.track_changes,
              size: 64,
              color: kSubtleText.withOpacity(.35),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Apply dayung first',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'OpenSans',
                  fontWeight: FontWeight.w700,
                  color: kSubtleText,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (list.isEmpty) {
      return _wrapWithRefreshAndNav(
        ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 120),
          children: [
            Icon(
              Icons.track_changes,
              size: 60,
              color: kSubtleText.withOpacity(.35),
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'No claims to track',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'OpenSans',
                  fontWeight: FontWeight.w600,
                  color: kSubtleText,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Submit a claim to start tracking.',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'OpenSans',
                  color: kSubtleText.withOpacity(.75),
                ),
              ),
            ),
          ],
        ),
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

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      color: Colors.white,
      child: InkWell(
        onTap: () => _openDetail(claim),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusIcon(status), color: color, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: kText,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _displayStatus(status),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              if (desc.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  desc,
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 15,
                    color: kSubText,
                  ),
                ),
              ],
              SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: kSubText),
                  SizedBox(width: 6),
                  Text(
                    date,
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontSize: 13,
                      color: kSubText,
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

  Widget _skeletonCard() {
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(110, 20),
          const SizedBox(height: 12),
          bar(200, 14),
          const SizedBox(height: 6),
          bar(180, 12),
          const SizedBox(height: 14),
          bar(140, 10),
        ],
      ),
    );
  }
}
