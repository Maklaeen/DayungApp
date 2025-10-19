import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/pages/submit_claim.dart'
    hide kSubtleText, kNeutralText, kPrimaryDark, kPrimary;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const double kCardRadius = 18;

class ClaimsPage extends StatefulWidget {
  const ClaimsPage({super.key, this.onNavBarVisible});

  // Dashboard passes a callback to show/hide the bottom navbar
  final ValueChanged<bool>? onNavBarVisible;

  @override
  State<ClaimsPage> createState() => _ClaimsPageState();
}

class _ClaimsPageState extends State<ClaimsPage>
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
  int? _dayungId;
  int _unreadNotifCount = 0;

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

    _tabController = TabController(length: 2, vsync: this)
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
    await _loadDayungUnit();
    await _loadProfileImage();
    await _fetchClaims();
    if (!mounted) return;
    _safeSetState(() => _loading = false);
  }

  Future<void> _refresh() async {
    _safeSetState(() => _loading = true);
    await _loadDayungUnit();
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

  Future<void> _loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(unitJson));
        _safeSetState(() {
          _dayungId = map['id'] is int
              ? map['id'] as int
              : int.tryParse('${map['id']}');
          _dayungName = (map['name'] ?? 'Dayung').toString();
          _barangay = map['barangay'];
          _city = map['city'];
        });
        await _fetchUnreadNotifCount();
      } catch (_) {
        _safeSetState(() {
          _dayungId = null;
          _unreadNotifCount = 0;
        });
      }
    } else {
      _safeSetState(() {
        _dayungId = null;
        _unreadNotifCount = 0;
      });
    }
  }

  Future<void> _fetchUnreadNotifCount() async {
    // NEW
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
        deathIso.isEmpty)
      return null;
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

      if (_dayungId == null) {
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
            'id, title, description, status, date_submitted, dayung_unit_id, user_id, beneficiary_id, death_certificate_url, date_of_death',
          )
          .eq('user_id', user.id)
          .eq('dayung_unit_id', _dayungId as Object)
          .order('date_submitted', ascending: false);

      final claims = List<Map<String, dynamic>>.from(
        data as List<dynamic>,
      ).map((c) => Map<String, dynamic>.from(c)).toList();

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

  String _formatDate(dynamic v) {
    if (v == null) return '';
    try {
      final dt = DateTime.parse(v.toString()).toLocal();
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
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return v.toString();
    }
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return kAccent;
      case 'rejected':
        return kDanger;
      case 'pending':
        return kWarn;
      default:
        return kWarn;
    }
  }

  IconData _statusIcon(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return Icons.verified;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'pending':
      default:
        return Icons.pending_actions;
    }
  }

  List<Map<String, dynamic>> _filteredList(bool ongoing) {
    final base = ongoing ? _pending : _history;
    if (_search.trim().isEmpty) return base;
    final q = _search.toLowerCase();
    return base.where((c) {
      final title = (c['title'] ?? '').toString().toLowerCase();
      final id = (c['id'] ?? '').toString().toLowerCase();
      final status = (c['status'] ?? '').toString().toLowerCase();
      final desc = (c['description'] ?? '').toString().toLowerCase();
      return title.contains(q) ||
          id.contains(q) ||
          status.contains(q) ||
          desc.contains(q);
    }).toList();
  }

  void _openSubmitSheet() async {
    if (_submittingModalOpen) return;
    // Ensure we have the latest selected unit before opening the form
    await _loadDayungUnit();

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
        child: SubmitClaimForm(dayungUnitId: _dayungId),
      ),
    ).whenComplete(() {
      _submittingModalOpen = false;
      _fetchClaims();
    });
  }

  void _openDetail(Map<String, dynamic> claim) {
    final status = (claim['status'] ?? '').toString();
    final color = _statusColor(status);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 26,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(.12),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: color.withOpacity(.45)),
                    ),
                    child: Row(
                      children: [
                        Icon(_statusIcon(status), size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(
                          status[0].toUpperCase() + status.substring(1),
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
                  Text(
                    '#${claim['id']}',
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
                  const Icon(Icons.access_time, size: 16, color: kSubtleText),
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
              if ((claim['description'] ?? '').toString().trim().isNotEmpty)
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
              FutureBuilder<Map<String, dynamic>>(
                future: getDeceasedInfo(claim),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final deceased = snapshot.data!;
                  final dob = (deceased['dob'] ?? '').toString();
                  final dod = (deceased['date_of_death'] ?? '').toString();
                  final age = _computeAge(dob, dod);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deceased: ${deceased['name']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kNeutralText,
                        ),
                      ),
                      if (dob.isNotEmpty)
                        Text(
                          'Date of Birth: $dob',
                          style: const TextStyle(
                            fontSize: 13,
                            color: kSubtleText,
                          ),
                        ),
                      if (dod.isNotEmpty)
                        Text(
                          'Date of Death: $dod',
                          style: const TextStyle(
                            fontSize: 13,
                            color: kSubtleText,
                          ),
                        ),
                      if (age != null)
                        Text(
                          'Age at death: $age years',
                          style: const TextStyle(
                            fontSize: 13,
                            color: kSubtleText,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerName = context.watch<DayungUnitProvider>().dayungUnit;
    if (providerName != null && providerName != _dayungName) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadDayungUnit();
      });
    }

    final isWide = MediaQuery.of(context).size.width > 700;
    final ongoingList = _filteredList(true);
    final historyList = _filteredList(false);

    // Compute a safe bottom offset so the FAB clears the bottom nav
    final bottomSafeInset = MediaQuery.of(context).viewPadding.bottom;
    final double fabBottom =
        (_navBarVisible ? 90.0 : 24.0) + bottomSafeInset; // tweak 76 as needed

    return Scaffold(
      backgroundColor: kBg,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: fabBottom),
          child: FloatingActionButton.extended(
            onPressed: _openSubmitSheet,
            icon: const Icon(Icons.add),
            label: const Text(
              'New Claim',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontFamily: 'Montserrat',
              ),
            ),
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        // ensure header not under status bar
        child: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [const SizedBox(height: 16)],
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _searchField(),
              ),
            ),
            SliverAppBar(
              pinned: true,
              backgroundColor: kBg,
              elevation: 0,
              toolbarHeight: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: kPrimaryDark,
                    unselectedLabelColor: kSubtleText,
                    indicator: UnderlineTabIndicator(
                      borderSide: const BorderSide(
                        color: kPrimaryDark,
                        width: 3,
                      ),
                      insets: EdgeInsets.symmetric(
                        horizontal: isWide ? 120 : 40,
                      ),
                    ),
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      fontFamily: 'Montserrat',
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      fontFamily: 'Montserrat',
                    ),
                    tabs: const [
                      Tab(text: 'Ongoing'),
                      Tab(text: 'History'),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: _loading
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300, width: 1),
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
                          color: kPrimary,
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Loading claims...',
                          style: TextStyle(
                            color: kSubtleText,
                            fontSize: 16,
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _claimListView(ongoingList, true),
                    _claimListView(historyList, false),
                  ],
                ),
        ),
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
    if (list.isEmpty) {
      return _wrapWithRefreshAndNav(
        ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 120),
          children: [
            Icon(
              ongoing ? Icons.pending_actions : Icons.inbox_outlined,
              size: 60,
              color: kSubtleText.withOpacity(.35),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                ongoing ? 'No pending claims' : 'No claim history',
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'OpenSans',
                  fontWeight: FontWeight.w600,
                  color: kSubtleText,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (ongoing)
              Center(
                child: Text(
                  'Tap "New Claim" to submit one.',
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
    final color = _statusColor(status);
    final title = (claim['title'] ?? 'Untitled').toString();
    final date = _formatDate(claim['date_submitted']);
    final desc = (claim['description'] ?? '').toString().trim();

    return InkWell(
      onTap: () => _openDetail(claim),
      borderRadius: BorderRadius.circular(kCardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(color: color.withOpacity(.35), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ...status, title, desc, etc...
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: color.withOpacity(.45)),
                  ),
                  child: Row(
                    children: [
                      Icon(_statusIcon(status), size: 14, color: color),
                      const SizedBox(width: 4),
                      Text(
                        status[0].toUpperCase() + status.substring(1),
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
                Text(
                  '#${claim['id']}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w600,
                    color: kSubtleText.withOpacity(.65),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                fontFamily: 'Montserrat',
                height: 1.15,
                color: kNeutralText,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'OpenSans',
                  height: 1.3,
                  color: kSubtleText,
                ),
              ),
            ],
            // --- INSERT THE FUTUREBUILDER HERE ---
            const SizedBox(height: 10),
            FutureBuilder<Map<String, dynamic>>(
              future: getDeceasedInfo(claim),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final deceased = snapshot.data!;
                final dob = (deceased['dob'] ?? '').toString();
                final dod = (deceased['date_of_death'] ?? '').toString();
                final age = _computeAge(dob, dod);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deceased: ${deceased['name']}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kNeutralText,
                      ),
                    ),
                    if (dob.isNotEmpty)
                      Text(
                        'Date of Birth: $dob',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kSubtleText,
                        ),
                      ),
                    if (dod.isNotEmpty)
                      Text(
                        'Date of Death: $dod',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kSubtleText,
                        ),
                      ),
                    if (age != null)
                      Text(
                        'Age at death: $age years',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kSubtleText,
                        ),
                      ),
                  ],
                );
              },
            ),
            // --- END FUTUREBUILDER ---
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: kSubtleText),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    date,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.w600,
                      color: kSubtleText,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.black38,
                ),
              ],
            ),
          ],
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
