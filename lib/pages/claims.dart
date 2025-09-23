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

  bool isLoading = true;
  List<Map<String, dynamic>> ongoingClaims = [];
  List<Map<String, dynamic>> historyClaims = [];
  Map<String, dynamic>? _selectedDayungUnitObj;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
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
      final unit = jsonDecode(unitJson);
      setState(() {
        selectedDayungUnit = unit['name'];
        _selectedDayungUnitObj = unit;
      });
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
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    final userId = currentUser.id;

    final response = await Supabase.instance.client
        .from('claims')
        .select('id, date_submitted, title, status')
        .eq('user_id', userId)
        .order('date_submitted', ascending: false);

    // ignore: unnecessary_null_comparison
    if (response == null) {
      setState(() {
        ongoingClaims = [];
        historyClaims = [];
        isLoading = false;
      });
      return;
    }

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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final dayungName = _selectedDayungUnitObj?['name'] ?? 'Dayung';
    final barangay = _selectedDayungUnitObj?['barangay'];
    final city = _selectedDayungUnitObj?['city'];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AutoSizeText(
                    dayungName,
                    style: TextStyle(
                      fontSize: isWide ? 36 : 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Montserrat',
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
                        color: Colors.black54,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.notifications_none,
                          color: Colors.orange[700],
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
                          backgroundColor: Colors.blue,
                          backgroundImage:
                              (_profileUrl != null && _profileUrl!.isNotEmpty)
                              ? NetworkImage(_profileUrl!)
                              : null,
                          child: (_profileUrl == null || _profileUrl!.isEmpty)
                              ? const Icon(
                                  Icons.account_circle,
                                  size: 36,
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
            const Divider(thickness: 1, height: 24, color: Colors.grey),

            // Submit New Claim Button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
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
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
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
                    );
                  },
                ),
              ),
            ),

            // TabBar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.blue,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black38,
                labelStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                ),
                tabs: const [
                  Tab(text: 'Ongoing'),
                  Tab(text: 'History'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // TabBarView for Claims
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // Ongoing Claims
                        _buildClaimsList(context, ongoingClaims, isWide, true),
                        // History Claims
                        _buildClaimsList(context, historyClaims, isWide, false),
                      ],
                    ),
            ),
          ],
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
      return const Center(child: Text('No claims found.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: claims.length,
          itemBuilder: (context, index) {
            final claim = claims[index];
            final status = claim['status']?.toString().toLowerCase() ?? '';
            Color bgColor;
            Color textColor;

            if (status == 'rejected') {
              bgColor = Colors.red[100]!;
              textColor = Colors.red[800]!;
            } else if (isOngoing) {
              bgColor = Colors.orange[100]!;
              textColor = Colors.brown;
            } else {
              bgColor = Colors.green[100]!;
              textColor = Colors.green[900]!;
            }

            return _claimCard(
              _formatDate(claim['date_submitted']?.toString() ?? ''),
              claim['title']?.toString() ?? '',
              claim['status']?.toString() ?? '',
              bgColor,
              textColor,
              isWide,
            );
          },
        );
      },
    );
  }

  Widget _claimCard(
    String date,
    String title,
    String status,
    Color bgColor,
    Color textColor,
    bool isWide,
  ) {
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
            color: textColor,
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
                    fontSize: isWide ? 20 : 16,
                    color: Colors.black54,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isWide ? 22 : 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                      color: textColor,
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
          Icon(
            Icons.chevron_right,
            color: Colors.black38,
            size: isWide ? 32 : 24,
          ),
        ],
      ),
    );
  }
}
