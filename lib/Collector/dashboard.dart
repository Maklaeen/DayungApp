import 'dart:convert';
import 'package:capstone_app/Collector/collect_cash.dart';
import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class CollectorDashboardPage extends StatefulWidget {
  const CollectorDashboardPage({super.key});

  @override
  State<CollectorDashboardPage> createState() => _CollectorDashboardPageState();
}

class _CollectorDashboardPageState extends State<CollectorDashboardPage> {
  final sb = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();

  String _dayungLabel = 'Dayung';
  int? _dayungUnitId;

  bool _loading = true;
  int _activeMembers = 0;
  double _pendingAmount = 0;
  int _pendingMembers = 0;
  List<String> _recentDeaths = [];

  int _tab = 0;
  bool _showNavBar = true;

  @override
  void initState() {
    super.initState();
    _init();
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadDayungFromPrefs();
    await _ensureDayungId();
    await _fetchAll();
  }

  Future<void> _ensureDayungId() async {
    if (_dayungUnitId != null) return;
    try {
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;
      final res = await sb
          .from('users')
          .select('dayung_unit_id')
          .eq('id', uid)
          .maybeSingle();
      final id = res?['dayung_unit_id'];
      if (id != null) {
        setState(() => _dayungUnitId = int.tryParse(id.toString()));
      }
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _loadDayungFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String label = prefs.getString('selectedDayungUnit') ?? 'Dayung';
    String? jsonFull = prefs.getString('selectedDayungUnitData');
    Map<String, dynamic>? parsed;

    if (jsonFull != null) {
      try {
        parsed = jsonDecode(jsonFull);
      } catch (_) {}
    }
    if (parsed == null &&
        label.trim().startsWith('{') &&
        label.contains('"name"')) {
      try {
        parsed = jsonDecode(label);
      } catch (_) {}
    }
    if (parsed != null) {
      if ((parsed['name'] ?? '').toString().isNotEmpty) {
        label = parsed['name'];
      }
      final id = parsed['id'];
      if (id != null) _dayungUnitId = int.tryParse(id.toString());
    }
    setState(() => _dayungLabel = label);
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      final managed = await _managedDayungIds();
      await Future.wait([
        _fetchActiveMembers(managed),
        _fetchPendingPayments(managed),
        _fetchRecentDeaths(managed),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<int>> _managedDayungIds() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return <int>[];

    try {
      final rows = await sb
          .from('dayung_collectors')
          .select('dayung_unit_id')
          .eq('user_id', uid);
      final ids = <int>{
        for (final r in List<Map<String, dynamic>>.from(rows))
          if (r['dayung_unit_id'] != null)
            int.tryParse(r['dayung_unit_id'].toString()) ?? -1,
      }..remove(-1);

      if (ids.isNotEmpty) return ids.toList();
    } catch (_) {}

    // Fallback to selected pref (if any)
    if (_dayungUnitId != null) return [_dayungUnitId!];
    return <int>[];
  }

  Future<void> _fetchActiveMembers(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _activeMembers = 0;
        return;
      }
      final apps = await sb
          .from('applications')
          .select('user_id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'approved');
      final usersSet = <String>{};
      for (final r in List<Map<String, dynamic>>.from(apps)) {
        final id = (r['user_id'] ?? '').toString();
        if (id.isNotEmpty) usersSet.add(id);
      }
      if (usersSet.isEmpty) {
        _activeMembers = 0;
        return;
      }
      final users = await sb
          .from('users')
          .select('id,is_deceased')
          .inFilter('id', usersSet.toList());
      final alive = List<Map<String, dynamic>>.from(
        users,
      ).where((u) => (u['is_deceased'] ?? false) == false).length;
      _activeMembers = alive;
    } catch (_) {
      _activeMembers = 0;
    }
  }

  Future<void> _fetchPendingPayments(List<int> ids) async {
    try {
      _pendingAmount = 0;
      _pendingMembers = 0;

      // RPC if available
      try {
        final rpc = await sb.rpc(
          'collector_pending_payments',
          params: {'p_dayung_ids': ids},
        );
        if (rpc is Map && rpc['total_amount'] != null) {
          _pendingAmount = double.tryParse(rpc['total_amount'].toString()) ?? 0;
          _pendingMembers = int.tryParse(rpc['member_count'].toString()) ?? 0;
          return;
        }
      } catch (_) {}

      if (ids.isEmpty) return;
      final rows = await sb
          .from('payments')
          .select('amount, user_id, status, dayung_unit_id');
      final managed = ids.toSet();
      final memberSet = <String>{};
      double total = 0;
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        if ((m['status'] ?? '').toString().toLowerCase() == 'pending') {
          final dId = m['dayung_unit_id'];
          if (dId is int && managed.contains(dId)) {
            total += (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0;
            if (m['user_id'] != null) memberSet.add(m['user_id'].toString());
          }
        }
      }
      _pendingAmount = total;
      _pendingMembers = memberSet.length;
    } catch (_) {
      _pendingAmount = 0;
      _pendingMembers = 0;
    }
  }

  Future<void> _fetchRecentDeaths(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _recentDeaths = [];
        return;
      }
      final rows = await sb
          .from('users')
          .select('full_name')
          .inFilter('dayung_unit_id', ids)
          .eq('is_deceased', true)
          .order('date_of_death', ascending: false)
          .limit(2);
      _recentDeaths = List<Map<String, dynamic>>.from(
        rows,
      ).map((e) => (e['full_name'] ?? 'Member') as String).toList();
    } catch (_) {
      _recentDeaths = [];
    }
  }

  List<Widget> get _pages => [
    _homePage(),
    const Placeholder(), // Contributions
    ClaimsPage(onNavBarVisible: (v) => setState(() => _showNavBar = v)),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width > 820;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                const Divider(height: 1, color: Color(0xFFE1E4E8)),
                _greeting(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: IndexedStack(index: _tab, children: _pages),
                  ),
                ),
              ],
            ),
          ),
          _bottomNav(wide),
        ],
      ),
    );
  }

  /* ------------------------------- UI parts ------------------------------- */

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dayungLabel,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: kPrimaryDark,
                letterSpacing: .4,
              ),
            ),
          ),
          _iconBtn(
            icon: Icons.notifications_active_rounded,
            color: kWarn,
            tooltip: 'Notifications',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationPage()),
            ),
            badge: '1',
          ),
          const SizedBox(width: 6),
          _iconBtn(
            icon: Icons.settings_rounded,
            color: kPrimary,
            tooltip: 'Profile & Settings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _greeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Maayung buntag,\nCollector!', // or Treasurer!
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.05,
                color: kNeutralText,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
            child: const CircleAvatar(
              radius: 28,
              backgroundColor: kPrimary,
              child: Icon(Icons.person, size: 34, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homePage() {
    return RefreshIndicator(
      onRefresh: _fetchAll,
      edgeOffset: 68,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tripleCards(),
            const SizedBox(height: 18),
            _primaryAction('Open Gcash QR', Icons.qr_code_2, _openGcashQr),
            const SizedBox(height: 12),
            _primaryAction(
              'Record Cash Payment',
              Icons.receipt_long,
              _recordCashPayment,
            ),
            const SizedBox(height: 12),
            _primaryAction('Show Receipts', Icons.sticky_note_2, _showReceipts),
            const SizedBox(height: 18),
            _recentActivity(),
          ],
        ),
      ),
    );
  }

  Widget _tripleCards() {
    final cards = <Widget>[
      _statCard(
        color: const Color(0xFFD8EEFF),
        icon: Icons.groups,
        iconColor: Colors.blue[700],
        title: "Total Active\nMembers",
        bigText: _loading ? '—' : _activeMembers.toString(),
      ),
      _recentDeathsCard(),
      _statCard(
        color: const Color(0xFFFEFBDC),
        icon: Icons.account_balance_wallet,
        iconColor: Colors.orange[700],
        title: "Pending\nPayments",
        bigText: _loading ? '—' : '₱ ${_pendingAmount.toStringAsFixed(0)}',
        smallSubtitle: _loading
            ? ''
            : (_pendingMembers > 0
                  ? 'From $_pendingMembers members'
                  : 'No pending'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 360) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
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

  Widget _recentDeathsCard() {
    final names = _recentDeaths;
    final display = names.take(2).toList();
    final extra = names.length - display.length;

    return _statShell(
      color: const Color(0xFFFFDAF6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(FontAwesomeIcons.dove, size: 30, color: Colors.purple[400]),
          const SizedBox(height: 8),
          const Text(
            "Recent Death Notices",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFamily: 'Montserrat',
              color: kNeutralText,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: names.isEmpty
                ? const Center(
                    child: Text(
                      "None",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        fontFamily: 'Montserrat',
                        color: kNeutralText,
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final n in display)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                FontAwesomeIcons.dove,
                                size: 14,
                                color: Colors.black87,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  n,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    fontFamily: 'Montserrat',
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (extra > 0)
                        const Text(
                          'View All',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'OpenSans',
                            color: kPrimary,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required Color color,
    required IconData icon,
    required Color? iconColor,
    required String title,
    required String bigText,
    String smallSubtitle = '',
  }) {
    return _statShell(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 32, color: iconColor),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFamily: 'Montserrat',
              color: kNeutralText,
              height: 1.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      bigText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                        fontFamily: 'Montserrat',
                        color: kNeutralText,
                      ),
                    ),
                  ),
                  if (smallSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      smallSubtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                        color: kSubtleText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statShell({required Color color, required Widget child}) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: child,
    );
  }

  Widget _primaryAction(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 26, color: kPrimary),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
              color: kPrimaryDark,
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size.fromHeight(60),
          side: const BorderSide(color: kPrimary, width: 1.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _recentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kPrimaryDark,
            fontFamily: 'Montserrat',
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
          child: Column(
            children: const [
              _ActivityRow(
                icon: Icons.calendar_today,
                color: kPrimary,
                text: 'Jun 15    Contribution received     +₱ 23,000',
              ),
              SizedBox(height: 12),
              _ActivityRow(
                icon: Icons.handshake,
                color: kAccent,
                text: 'May 15   Assistance Received',
              ),
              SizedBox(height: 12),
              _ActivityRow(
                icon: Icons.calendar_today,
                color: kPrimary,
                text: 'Apr 15    Contribution received     +₱ 23,000',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottomNav(bool wide) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: Center(
        child: IgnorePointer(
          ignoring: !_showNavBar,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _showNavBar ? 1 : 0,
            child: Container(
              height: 86,
              margin: EdgeInsets.symmetric(horizontal: wide ? 170 : 20),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(44),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(Icons.home_rounded, "Home", 0),
                  _navItem(Icons.public, "Contributions", 1),
                  _navItem(Icons.description, "Claims", 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _tab == index;
    return TextButton(
      onPressed: () => setState(() => _tab = index),
      style: TextButton.styleFrom(
        foregroundColor: selected ? kPrimary : kNeutralText,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: selected ? kPrimary : kNeutralText),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'OpenSans',
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }

  void _openGcashQr() {
    // TODO: integrate actual QR view
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open GCASH QR (coming soon)')),
    );
  }

  void _recordCashPayment() {
    if (_dayungUnitId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No dayung selected.')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollectCashPage(dayungUnitId: _dayungUnitId!),
      ),
    );
  }

  void _showReceipts() {
    // TODO: open receipts page
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Show Receipts (coming soon)')),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
    String? badge,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kDanger,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
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
