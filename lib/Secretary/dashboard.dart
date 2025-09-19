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

      if (data is List) {
        for (final row in data) {
          final status = (row['status'] ?? '').toString().trim().toLowerCase();
          if (status == 'pending')
            pending++;
          else if (status == 'approved')
            approved++;
          else if (status == 'rejected')
            rejected++;
        }
      }

      setState(() {
        _pendingCount = pending;
        _approvedCount = approved;
        _rejectedCount = rejected;
        _loadingCounts = false;
      });
    } catch (e) {
      debugPrint('Error fetching claims counts: $e');
      setState(() => _loadingCounts = false);
    }
  }

  /// Fetch recent certificates (instead of claims)
  Future<void> _fetchRecentCertificates() async {
    final supabase = Supabase.instance.client;
    try {
      final recent = await supabase
          .from('certificates')
          .select('id, title, date_submitted')
          .order('date_submitted', ascending: false)
          .limit(3);

      List<Map<String, dynamic>> certList = [];
      if (recent is List) {
        certList = recent.map<Map<String, dynamic>>((e) {
          return Map<String, dynamic>.from(e as Map);
        }).toList();
      }

      setState(() => _recentCertificates = certList);
    } catch (e) {
      debugPrint('Error fetching certificates: $e');
    }
  }

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              _buildWelcomeMessage(),
              const SizedBox(height: 20),
              _buildSecretaryTools(),
              const SizedBox(height: 20),
              _buildRecentDeathNotices(),
              const SizedBox(height: 12),
              _buildDeathCertificateInboxButton(),
              const SizedBox(height: 20),
              _buildClaimsInbox(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildHeader() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        _selectedDayungUnit,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF2C3E50),
        ),
      ),
      IconButton(
        icon: const Icon(
          Icons.notifications_none,
          size: 26,
          color: Colors.black87,
        ),
        onPressed: () {},
      ),
    ],
  );

  Widget _buildWelcomeMessage() => Row(
    children: [
      CircleAvatar(
        radius: 25,
        backgroundColor: Colors.blue.shade200,
        child: const Icon(Icons.person, size: 30, color: Colors.white),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          "Maayung buntag, $_fullName!",
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
    ],
  );

  Widget _buildSecretaryTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Secretary Tools",
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _toolButton("Notify Members", Icons.campaign, Colors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _toolButton("Assign Members", Icons.group_add, Colors.green),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () {},
          icon: const Icon(Icons.assignment, size: 18),
          label: const Text(
            "Death Notice",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ],
  );

  Widget _toolButton(String label, IconData icon, Color color) => Container(
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: Column(
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Certificates instead of claims
  Widget _buildRecentDeathNotices() => _dashboardCard(
    title: "Recent Death Notices",
    child: _recentCertificates.isEmpty
        ? const Text('No recent certificates')
        : Column(
            children: _recentCertificates.map((c) {
              final title = c['title'] ?? 'Untitled';
              final date = _formatDate(c['date_submitted']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.article_outlined,
                      size: 20,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
  );

  /// New button under recent notices
  Widget _buildDeathCertificateInboxButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.red.shade600,
        foregroundColor: Colors.white,
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CertificatesPage()),
        );
      },
      icon: const Icon(Icons.folder_shared, size: 18),
      label: const Text(
        "Death Certificate Inbox",
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
  );

  /// Claims Inbox counts with clickable navigation
  Widget _buildClaimsInbox() => _dashboardCard(
    title: "Claims Inbox",
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _inboxItem(
          "Pending Claims",
          _loadingCounts ? null : _pendingCount,
          Colors.orange,
        ),
        const SizedBox(height: 8),
        _inboxItem(
          "Approved Claims",
          _loadingCounts ? null : _approvedCount,
          Colors.green,
        ),
        const SizedBox(height: 8),
        _inboxItem(
          "Rejected Claims",
          _loadingCounts ? null : _rejectedCount,
          Colors.red,
        ),
      ],
    ),
  );

  Widget _inboxItem(String label, int? count, Color color) => InkWell(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SecretaryClaimsPage()),
      );
    },
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

  Widget _buildBottomNavBar() => BottomNavigationBar(
    currentIndex: _currentIndex,
    onTap: (index) => setState(() => _currentIndex = index),
    selectedItemColor: const Color(0xFF1976D2),
    unselectedItemColor: Colors.black54,
    type: BottomNavigationBarType.fixed,
    items: [
      _navBarItem(Icons.dashboard, "Dashboard"),
      _navBarItem(Icons.folder, "Files"),
      _navBarItem(Icons.chat, "Chat"),
      _navBarItem(Icons.settings, "Settings"),
    ],
  );

  BottomNavigationBarItem _navBarItem(IconData icon, String label) =>
      BottomNavigationBarItem(icon: Icon(icon, size: 24), label: label);
}
