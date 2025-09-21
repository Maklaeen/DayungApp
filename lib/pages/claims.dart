import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/pages/contributionhistory.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/submit_claim.dart';

class ClaimsPage extends StatefulWidget {
  const ClaimsPage({super.key});

  @override
  State<ClaimsPage> createState() => _ClaimsPageState();
}

class _ClaimsPageState extends State<ClaimsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? selectedDayungUnit;

  bool isLoading = true;
  List<Map<String, dynamic>> ongoingClaims = [];
  List<Map<String, dynamic>> historyClaims = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // To refresh the tab view if needed
    });
    _loadDayungUnit();
    _fetchClaims();
  }

  Future<void> _loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final unit = prefs.getString('selectedDayungUnit');
    setState(() => selectedDayungUnit = unit ?? 'Dayung');
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedDayungUnit ?? 'Dayung',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationPage(),
                                ),
                              );
                            },
                            child: Stack(
                              children: [
                                Icon(
                                  Icons.notifications_none,
                                  color: Colors.orange[700],
                                  size: 36,
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    child: const Text(
                                      '1',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProfilePage(),
                                ),
                              );
                            },
                            child: const CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.blue,
                              child: Icon(
                                Icons.account_circle,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 1),

                // Submit New Claim Button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 32,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Submit New Claim',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SubmitClaimPage(),
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
                            ongoingClaims.isEmpty
                                ? const Center(
                                    child: Text('No ongoing claims.'),
                                  )
                                : ListView(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    children: ongoingClaims.map((claim) {
                                      return _claimCard(
                                        claim['date_submitted']?.toString() ??
                                            '',
                                        claim['title']?.toString() ?? '',
                                        claim['status']?.toString() ?? '',
                                        Colors.orange[100]!,
                                        Colors.brown,
                                      );
                                    }).toList(),
                                  ),
                            // History Claims
                            historyClaims.isEmpty
                                ? const Center(child: Text('No claim history.'))
                                : ListView(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    children: historyClaims.map((claim) {
                                      return _claimCard(
                                        claim['date_submitted']?.toString() ??
                                            '',
                                        claim['title']?.toString() ?? '',
                                        claim['status']?.toString() ?? '',
                                        Colors.green[100]!,
                                        Colors.green[900]!,
                                      );
                                    }).toList(),
                                  ),
                          ],
                        ),
                ),
              ],
            ),
          ),

          // Bottom Navigation
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Container(
                height: 70,
                margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _navBarItem(
                      icon: Icons.home,
                      label: 'Home',
                      selected: false,
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MemberDashboard(),
                          ),
                        );
                      },
                    ),
                    _navBarItem(
                      icon: FontAwesomeIcons.globe,
                      label: 'Contributions',
                      selected: false,
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ContributionHistory(),
                          ),
                        );
                      },
                    ),
                    _navBarItem(
                      icon: Icons.receipt_long,
                      label: 'Claims',
                      selected: true,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _claimCard(
    String date,
    String title,
    String status,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        title: Row(
          children: [
            Text(
              date,
              style: const TextStyle(
                fontSize: 20,
                color: Colors.black54,
                fontFamily: 'Montserrat',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navBarItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.blue[800] : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: selected ? Colors.blue[800] : Colors.black,
            size: 30,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.blue[800] : Colors.black,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
