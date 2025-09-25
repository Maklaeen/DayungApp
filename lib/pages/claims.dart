import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart' hide kBg, kPrimary, kWarn, kAccent;
import 'package:capstone_app/pages/submit_claim.dart' hide kSubtleText, kNeutralText, kPrimaryDark, kPrimary;
import 'package:capstone_app/widgets/member_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const double kCardRadius = 18;

class ClaimsPage extends StatefulWidget {
  const ClaimsPage({super.key});
  @override
  State<ClaimsPage> createState() => _ClaimsPageState();
}

class _ClaimsPageState extends State<ClaimsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  bool _submittingModalOpen = false;

  List<Map<String, dynamic>> _allClaims = [];
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _history = [];

  String _search = '';
  final _searchCtrl = TextEditingController();

  Map<String, dynamic>? _dayungObj;
  String? _profileUrl;
  String _dayungName = 'Dayung';
  String? _barangay;
  String? _city;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      _loadDayungUnit(),
      _loadProfileImage(),
      _fetchClaims(),
    ]);
  }

  Future<void> _loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson != null) {
      try {
        final raw = jsonDecode(unitJson);
        final map = Map<String, dynamic>.from(raw as Map);
        setState(() {
          _dayungObj = map;
          _dayungName = (map['name'] ?? 'Dayung').toString();
          _barangay = map['barangay'];
          _city = map['city'];
        });
      } catch (_) {
        setState(() => _dayungObj = null);
      }
    }
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
      setState(() {
        _profileUrl = (row?['profile_url'] ?? '').toString().trim();
      });
    } catch (_) {}
  }

  Future<void> _fetchClaims() async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _allClaims = [];
          _pending = [];
          _history = [];
          _loading = false;
        });
        return;
      }
      final data = await Supabase.instance.client
          .from('claims')
          .select('id, title, description, status, date_submitted')
          .eq('user_id', user.id)
          .order('date_submitted', ascending: false);
      final claims =
          List<Map<String, dynamic>>.from(data as List<dynamic>).map((c) {
        return Map<String, dynamic>.from(c);
      }).toList();

      final pending = claims
          .where((c) =>
              (c['status'] ?? '').toString().toLowerCase() == 'pending')
          .toList();
      final history = claims
          .where((c) =>
              (c['status'] ?? '').toString().toLowerCase() != 'pending')
          .toList();

      setState(() {
        _allClaims = claims;
        _pending = pending;
        _history = history;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _allClaims = [];
        _pending = [];
        _history = [];
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _fetchClaims(),
      _loadDayungUnit(),
      _loadProfileImage(),
    ]);
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
        'Dec'
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

  void _openSubmitSheet() {
    if (_submittingModalOpen) return;
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
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const SubmitClaimForm(),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  const Icon(Icons.access_time,
                      size: 16, color: kSubtleText),
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
              const SizedBox(height: 26),
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
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providerName = context.watch<DayungUnitProvider>().dayungUnit;
    if (providerName != null && providerName != _dayungName) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDayungUnit();
      });
    }

    final isWide = MediaQuery.of(context).size.width > 700;
    final ongoingList = _filteredList(true);
    final historyList = _filteredList(false);

    return Scaffold(
      backgroundColor: kBg,
      floatingActionButton: FloatingActionButton.extended(
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 120,
        child: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverToBoxAdapter(
              child: MemberHeader(
                title: _dayungName,
                subtitle: _barangay != null
                    ? '${_barangay!}${_city != null ? ', $_city' : ''}'
                    : null,
                profileUrl: _profileUrl,
                onNotificationTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationPage(),
                  ),
                ),
                onProfileTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfilePage(),
                    ),
                  ).then((_) => _loadProfileImage());
                },
              ),
            ),
            const SliverToBoxAdapter(
              child: Divider(thickness: 1, height: 24, color: Colors.grey),
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
                      borderSide:
                          const BorderSide(color: kPrimaryDark, width: 3),
                      insets:
                          EdgeInsets.symmetric(horizontal: isWide ? 120 : 40),
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
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  children: List.generate(4, (_) => _skeletonCard()),
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
      return ListView(
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
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => _claimCard(list[i]),
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
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                const Icon(Icons.chevron_right,
                    size: 20, color: Colors.black38),
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