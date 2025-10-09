import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/Members/member_header.dart';
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

class ContributionHistory extends StatefulWidget {
  const ContributionHistory({super.key});

  @override
  State<ContributionHistory> createState() => _ContributionHistoryState();
}

class _ContributionHistoryState extends State<ContributionHistory> {
  Map<String, dynamic>? _selectedDayungUnitObj;
  String? selectedDayungUnit;
  String? _profileUrl;

  bool _loading = false;
  List<Map<String, dynamic>> _paidContributions = [];
  bool _loadingPaid = true;

  @override
  void initState() {
    super.initState();
    _loadDayungUnit();
    _loadProfileImage();
    _fetchPaidContributions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadDayungUnit();
  }

  Future<void> _loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson != null) {
      try {
        final unit = jsonDecode(unitJson);
        setState(() {
          selectedDayungUnit = unit['name'];
          _selectedDayungUnitObj = Map<String, dynamic>.from(unit as Map);
        });
      } catch (_) {
        await prefs.remove('selectedDayungUnit');
        setState(() {
          selectedDayungUnit = 'Dayung';
          _selectedDayungUnitObj = null;
        });
      }
    } else {
      setState(() {
        selectedDayungUnit = 'Dayung';
        _selectedDayungUnitObj = null;
      });
    }
    // Refresh data when dayung selection changes
    await _fetchPaidContributions();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadDayungUnit(),
      _loadProfileImage(),
      _fetchPaidContributions(),
    ]);
    if (mounted) setState(() => _loading = false);
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
      setState(() {
        _profileUrl = response?['profile_url'] as String?;
      });
    }
  }

  Future<void> _fetchPaidContributions() async {
    setState(() => _loadingPaid = true);
    final supabase = Supabase.instance.client;
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _paidContributions = [];
          _loadingPaid = false;
        });
        return;
      }

      final dayungId = _selectedDayungUnitObj?['id'];
      var q = supabase
          .from('payments')
          .select(
            'id, amount, status, created_at, dayung_unit_id, death_notice_id',
          )
          .eq('user_id', uid)
          .eq('status', 'paid');

      if (dayungId != null) {
        q = q.eq('dayung_unit_id', dayungId);
      }

      final payments = List<Map<String, dynamic>>.from(
        await q.order('created_at', ascending: false),
      );

      if (payments.isEmpty) {
        setState(() {
          _paidContributions = [];
          _loadingPaid = false;
        });
        return;
      }

      // Fetch notice details
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

      // Merge and normalize for UI
      final merged = payments.map((p) {
        final nid = p['death_notice_id'] as int?;
        final n = nid != null ? noticeById[nid] : null;
        return {
          'date': (p['created_at'] ?? '').toString(), // fallback to created_at
          'amount': (p['amount'] is num)
              ? (p['amount'] as num).toDouble()
              : double.tryParse('${p['amount']}') ?? 0.0,
          'notice_name': (n?['name'] ?? 'Death Notice #$nid').toString(),
          'date_of_death': n?['date_of_death'],
        };
      }).toList();

      setState(() {
        _paidContributions = merged;
        _loadingPaid = false;
      });
    } catch (_) {
      setState(() {
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
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    // Update header immediately when provider changes
    final providerName = context.watch<DayungUnitProvider>().dayungUnit;
    if (providerName != null && providerName != selectedDayungUnit) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        setState(() => selectedDayungUnit = providerName);
        await _loadDayungUnit(); // reload full object for address/coords
      });
    }

    final dayungName =
        providerName ?? _selectedDayungUnitObj?['name'] ?? 'Dayung';
    final addr = _selectedDayungUnitObj != null
        ? _address(_selectedDayungUnitObj!)
        : null;

    // Demo data; replace with backend data when ready
    final contributions = [
      {'date': 'February 17, 2025', 'amount': '₱ 200'},
      {'date': 'March 20, 2024', 'amount': '₱ 200'},
      {'date': 'June 30, 2023', 'amount': '₱ 200'},
    ];

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh, // pull-to-refresh from header area
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      child: MemberHeader(
                        title: (providerName ?? 'Dayung'),
                        subtitle: (addr ?? ''),
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
                    const SizedBox(height: 16),
                    const Divider(thickness: 1, height: 24, color: Colors.grey),
                  ],
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
            body: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _loadingPaid ? 1 : _paidContributions.length,
              itemBuilder: (context, index) {
                if (_loadingPaid) {
                  return const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator()),
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

                final item = _paidContributions[index];
                final datePaid = _fmtDate(item['date']?.toString() ?? '');
                final amount = (item['amount'] as double?) ?? 0.0;
                final name = item['notice_name']?.toString() ?? 'Death Notice';
                final dod = item['date_of_death']?.toString();

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
                        // Notice name
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Montserrat',
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Optional DoD
                        if (dod != null && dod.isNotEmpty)
                          Text(
                            'Date of death: $dod',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kSubText,
                              fontFamily: 'OpenSans',
                            ),
                          ),
                        const SizedBox(height: 10),
                        // Amount + date paid
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '₱ ${amount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                color: Colors.blue,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            Text(
                              datePaid.isEmpty ? '' : 'Paid on $datePaid',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kSubText,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Unused but kept for compatibility
  Widget _navBarItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? kAccent : kText,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: selected ? kAccent : kText, size: 30),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: selected ? kAccent : kText,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
