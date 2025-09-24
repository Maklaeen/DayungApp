import 'package:capstone_app/settings/dayung_provider.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/pages/submit_claim.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'dart:convert';

// Senior-friendly palette
const kBg = Color(0xFFFAFAF7); // warm off-white
const kText = Color(0xFF1F2937); // dark neutral
const kSubText = Color(0xFF4B5563); // softer dark gray
const kAccent = Color(0xFF3E8E7E); // muted teal

class ClaimsPage extends StatefulWidget {
  const ClaimsPage({super.key});

  @override
  State<ClaimsPage> createState() => _ClaimsPageState();
}

class _ClaimsPageState extends State<ClaimsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? selectedDayungUnit;
  String? _profileUrl;
  Map<String, dynamic>? _selectedDayungUnitObj;

  bool isLoading = true;
  List<Map<String, dynamic>> ongoingClaims = [];
  List<Map<String, dynamic>> historyClaims = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    _loadDayungUnit();
    _fetchClaims();
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

  Future<void> _fetchClaims() async {
    setState(() => isLoading = true);
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          ongoingClaims = [];
          historyClaims = [];
          isLoading = false;
        });
        return;
      }

      final response = await Supabase.instance.client
          .from('claims')
          .select('id, date_submitted, title, status')
          .eq('user_id', currentUser.id)
          .order('date_submitted', ascending: false);

      final List<Map<String, dynamic>> claimsList =
          List<Map<String, dynamic>>.from(response as List);

      final pending = claimsList.where((c) {
        final s = (c['status'] ?? '').toString().toLowerCase();
        return s == 'pending';
      }).toList();

      final history = claimsList.where((c) {
        final s = (c['status'] ?? '').toString().toLowerCase();
        return s != 'pending';
      }).toList();

      setState(() {
        ongoingClaims = pending;
        historyClaims = history;
        isLoading = false;
      });
    } on PostgrestException catch (_) {
      setState(() {
        ongoingClaims = [];
        historyClaims = [];
        isLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to load claims.')));
    } catch (_) {
      setState(() {
        ongoingClaims = [];
        historyClaims = [];
        isLoading = false;
      });
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
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
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _capitalize(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'Pending';
    return t[0].toUpperCase() + t.substring(1);
  }

  Future<void> _refresh() async {
    await Future.wait([_fetchClaims(), _loadDayungUnit(), _loadProfileImage()]);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    final barangay = _selectedDayungUnitObj?['barangay'];
    final city = _selectedDayungUnitObj?['city'];

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
                            if (barangay != null)
                              Text(
                                '$barangay${city != null ? ', $city' : ''}',
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 24,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: Text(
                        'Submit New Claim',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: isWide ? 20 : 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          builder: (context) => Padding(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).viewInsets.bottom,
                            ),
                            child: const SubmitClaimForm(),
                          ),
                        ).whenComplete(() => _fetchClaims());
                      },
                    ),
                  ),
                ),
              ),
              SliverAppBar(
                pinned: true,
                backgroundColor: kBg,
                elevation: 0,
                toolbarHeight: 0,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: kAccent,
                      labelColor: kText,
                      unselectedLabelColor: kSubText,
                      labelStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
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
            body: isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildClaimsList(context, ongoingClaims, isWide, true),
                      _buildClaimsList(context, historyClaims, isWide, false),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildClaimsList(
    BuildContext context,
    List<Map<String, dynamic>> claims,
    bool isWide,
    bool isOngoing,
  ) {
    if (claims.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.inbox, size: 56, color: Colors.black26),
          SizedBox(height: 8),
          Center(
            child: Text(
              'No claims found.',
              style: TextStyle(
                fontSize: 18,
                color: kSubText,
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: claims.length,
      itemBuilder: (context, index) {
        final claim = claims[index];
        final statusRaw = claim['status']?.toString() ?? '';
        final status = statusRaw.toLowerCase();
        final colors = _statusColors(status, isOngoing);
        return _claimCard(
          date: _formatDate(claim['date_submitted']?.toString() ?? ''),
          title: claim['title']?.toString() ?? '',
          statusText: _capitalize(status),
          chipBg: colors.$1,
          chipFg: colors.$2,
          isWide: isWide,
        );
      },
    );
  }

  (Color, Color) _statusColors(String status, bool isOngoing) {
    if (status == 'rejected') {
      return (Colors.red[100]!, Colors.red[800]!);
    } else if (status == 'approved') {
      return (Colors.green[100]!, Colors.green[900]!);
    } else if (isOngoing) {
      return (Colors.orange[100]!, Colors.brown);
    }
    return (Colors.grey[200]!, Colors.black87);
  }

  Widget _claimCard({
    required String date,
    required String title,
    required String statusText,
    required Color chipBg,
    required Color chipFg,
    required bool isWide,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 32 : 20,
        vertical: isWide ? 20 : 12,
      ),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FontAwesomeIcons.fileInvoice,
            color: chipFg,
            size: isWide ? 32 : 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: TextStyle(
                    fontSize: isWide ? 18 : 16,
                    color: kSubText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title.isEmpty ? 'Untitled claim' : title,
                  style: TextStyle(
                    fontSize: isWide ? 22 : 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Montserrat',
                    color: kText,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: chipFg,
                      fontWeight: FontWeight.bold,
                      fontSize: isWide ? 16 : 14,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.black38, size: 28),
        ],
      ),
    );
  }
}
