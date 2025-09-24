import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:provider/provider.dart';
import 'package:capstone_app/settings/dayung_provider.dart';
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
  String? selectedDayungUnit;
  String? _profileUrl;
  Map<String, dynamic>? _selectedDayungUnitObj;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadDayungUnit();
    _loadProfileImage();
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

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await Future.wait([_loadDayungUnit(), _loadProfileImage()]);
    if (mounted) setState(() => _loading = false);
  }

  String _address(Map<String, dynamic> d) {
    final parts = <String>[
      if ((d['barangay'] ?? '').toString().isNotEmpty) d['barangay'],
      if ((d['city'] ?? '').toString().isNotEmpty) d['city'],
    ];
    return parts.join(', ');
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Title + address
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AutoSizeText(
                              dayungName,
                              style: TextStyle(
                                fontSize: isWide ? 36 : 28,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Montserrat',
                                color: kText,
                              ),
                              maxLines: 1,
                              minFontSize: 20,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (addr != null && addr.isNotEmpty)
                              Text(
                                addr,
                                style: TextStyle(
                                  fontSize: isWide ? 16 : 13,
                                  color: kSubText,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Actions
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.notifications_none,
                              color: kAccent,
                              size: isWide ? 36 : 28,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProfilePage(),
                                ),
                              ).then((_) => _loadProfileImage());
                            },
                            child: CircleAvatar(
                              radius: 20,
                              backgroundColor: kAccent,
                              backgroundImage:
                                  (_profileUrl != null &&
                                      _profileUrl!.isNotEmpty)
                                  ? NetworkImage(_profileUrl!)
                                  : null,
                              child:
                                  (_profileUrl == null || _profileUrl!.isEmpty)
                                  ? const Icon(
                                      Icons.account_circle,
                                      size: 30,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Divider(thickness: 1, height: 24, color: Colors.grey),
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
              itemCount: contributions.length,
              itemBuilder: (context, index) {
                final item = contributions[index];
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
                          item['date']!,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Montserrat',
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['amount']!,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Colors.blue,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Contribution Payment',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: kSubText,
                            fontFamily: 'Montserrat',
                          ),
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
