import 'package:capstone_app/Secretary/beneficiaries_tab.dart'
    show SecretaryBeneficiariesTab;
import 'package:capstone_app/Secretary/certificates.dart';
import 'package:capstone_app/Secretary/claims.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecretaryDashboard extends StatefulWidget {
  const SecretaryDashboard({super.key});

  @override
  State<SecretaryDashboard> createState() => _SecretaryDashboardState();
}

class _SecretaryDashboardState extends State<SecretaryDashboard> {
  String _fullName = '';
  String _selectedDayungUnit = 'Dayung Unit';
  int _currentIndex = 0;

  // claims counts + loading
  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;
  bool _loadingCounts = true;

  // recent certificates list
  List<Map<String, dynamic>> _recentCertificates = [];

  @override
  void initState() {
    super.initState();
    _loadSecretaryInfo();
    _fetchClaimsCounts();
    _fetchRecentCertificates();
  }

  Future<void> _loadSecretaryInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fullName = prefs.getString('secretaryFullName') ?? 'Secretary';
      _selectedDayungUnit =
          prefs.getString('selectedDayungUnit') ?? 'Dayung Unit';
    });
  }

  /// Fetch claims counts
  Future<void> _fetchClaimsCounts() async {
    final supabase = Supabase.instance.client;
    try {
      final data = await supabase
          .from('claims')
          .select('status, date_submitted');

      int pending = 0, approved = 0, rejected = 0;

      for (final row in data) {
        final status = (row['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'pending') {
          pending++;
        } else if (status == 'approved')
          // ignore: curly_braces_in_flow_control_structures
          approved++;
        else if (status == 'rejected')
          // ignore: curly_braces_in_flow_control_structures
          rejected++;
      }

      if (!mounted) return;
      setState(() {
        _pendingCount = pending;
        _approvedCount = approved;
        _rejectedCount = rejected;
        _loadingCounts = false;
      });
    } catch (e) {
      debugPrint('Error fetching claims counts: $e');
      if (!mounted) return;
      setState(() => _loadingCounts = false);
    }
  }

  /// Fetch recent certificates (instead of claims)
  Future<void> _fetchRecentCertificates() async {
    final supabase = Supabase.instance.client;
    try {
      final recent = await supabase
          .from('certificates')
          .select('id, deceased_name, submitted_at')
          .order('submitted_at', ascending: false)
          .limit(3);

      List<Map<String, dynamic>> certList = [];
      certList = recent.map<Map<String, dynamic>>((e) {
        return Map<String, dynamic>.from(e as Map);
      }).toList();

      if (!mounted) return;
      setState(() => _recentCertificates = certList);
    } catch (e) {
      debugPrint('Error fetching certificates: $e');
    }
  }

  // ignore: unused_element
  String _formatDate(dynamic ds) {
    if (ds == null) return '';
    try {
      final d = DateTime.parse(ds.toString());
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
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return ds.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedDayungUnit,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    Row(
                      children: [
                        Stack(
                          children: [
                            const Icon(
                              Icons.notifications,
                              color: Colors.orange,
                              size: 32,
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: const Text(
                                  '1',
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
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            shape: BoxShape.circle,
                          ),
                          child: const CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.transparent,
                            child: Icon(
                              Icons.settings,
                              color: Colors.blue,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(thickness: 1.2),
              // Welcome row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.blueGrey,
                      child: Icon(Icons.person, size: 40, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Maayung buntag, $_fullName!",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // 3 info cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _infoCard(
                      color: Colors.blue[100]!,
                      icon: Icons.groups,
                      title: "Total Active\nMembers",
                      value: "259", // Replace with your actual data if needed
                      action: "View All",
                      actionColor: Colors.blue[800]!,
                      onTap: () {}, // TODO: Add navigation
                    ),
                    const SizedBox(width: 8),
                    _infoCard(
                      color: Colors.pink[100]!,
                      icon: Icons.local_florist,
                      title: "Recent\nDeath Notices",
                      value: _recentCertificates.isEmpty
                          ? "No recent"
                          : _recentCertificates
                                .map(
                                  (c) => "• ${c['deceased_name'] ?? 'Unknown'}",
                                )
                                .join('\n'),
                      action: "View All",
                      actionColor: Colors.blue[800]!,
                      isDeathNotice: true,
                      onTap: () {}, // TODO: Add navigation
                    ),
                    const SizedBox(width: 8),
                    _infoCard(
                      color: Colors.yellow[100]!,
                      icon: Icons.account_balance_wallet,
                      title: "Pending\nPayments",
                      value:
                          "₱ 21,900\nFrom 219 members", // Replace with your actual data if needed
                      action: "",
                      actionColor: Colors.transparent,
                      onTap: () {}, // TODO: Add navigation
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Death Certificate Inbox
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Death Certificate\nInbox",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 120,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CertificatesPage(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            side: const BorderSide(color: Colors.grey),
                          ),
                          child: const Text("View"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // 2 green action cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _actionCard(
                        color: Colors.green[50]!,
                        icon: Icons.info_outline,
                        label: "Notify members\nto update info",
                        onTap: () {}, // TODO: Add logic
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _actionCard(
                        color: Colors.green[50]!,
                        icon: Icons.volunteer_activism,
                        label: "Assign members\nto assist at vigil",
                        onTap: () {}, // TODO: Add logic
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Death Notice button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // TODO: Add logic for Death Notice
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text(
                      "Death Notice",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Claims Inbox
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _dashboardCard(
                  title: "Claims Inbox",
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _inboxItem(
                        "Pending Claims",
                        _loadingCounts ? null : _pendingCount,
                        Colors.orange,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SecretaryClaimsPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _inboxItem(
                        "Approved Claims",
                        _loadingCounts ? null : _approvedCount,
                        Colors.green,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SecretaryClaimsPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _inboxItem(
                        "Rejected Claims",
                        _loadingCounts ? null : _rejectedCount,
                        Colors.red,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SecretaryClaimsPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Beneficiaries button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SecretaryBeneficiariesTab(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.people, size: 18),
                    label: const Text(
                      "Beneficiaries",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomNavBar(),
    );
  }

  Widget _infoCard({
    required Color color,
    required IconData icon,
    required String title,
    required String value,
    required String action,
    required Color actionColor,
    bool isDeathNotice = false,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.black54, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontWeight: isDeathNotice ? FontWeight.w500 : FontWeight.bold,
                  fontSize: isDeathNotice ? 13 : 24,
                  fontFamily: 'Montserrat',
                ),
              ),
              if (action.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      action,
                      style: TextStyle(
                        color: actionColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCard({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.green[900], size: 32),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Montserrat',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardCard({required String title, required Widget child}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _inboxItem(
    String label,
    int? count,
    Color color, {
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        if (count == null)
          const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "$count",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _bottomNavBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      selectedItemColor: Colors.blue[900],
      unselectedItemColor: Colors.black54,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home, size: 28),
          label: "Home",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.public, size: 28),
          label: "Contributions",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.description, size: 28),
          label: "Claims",
        ),
      ],
    );
  }
}
