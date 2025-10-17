import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:photo_view/photo_view.dart'; // Add this to your pubspec.yaml for image preview

const Color kPrimary = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFF8FAFC);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class SecretaryBeneficiariesTab extends StatefulWidget {
  final int dayungUnitId;
  const SecretaryBeneficiariesTab({super.key, required this.dayungUnitId});

  @override
  State<SecretaryBeneficiariesTab> createState() =>
      _SecretaryBeneficiariesTabState();
}

class _SecretaryBeneficiariesTabState extends State<SecretaryBeneficiariesTab> {
  int _selectedTab = 0; // 0: Pending, 1: Active
  Map<String, dynamic> _users = {};
  Map<String, List<dynamic>> _pendingByUser = {};
  Map<String, List<dynamic>> _activeByUser = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchBeneficiaries();
  }

  Future<void> _fetchBeneficiaries() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;
    try {
      // 1) Get approved members for this unit
      final apps = await supabase
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');

      final userIds = (apps as List<dynamic>)
          .map((e) => (e as Map)['user_id'])
          .where((v) => v != null && v.toString().trim().isNotEmpty)
          .map((v) => v.toString())
          .toSet()
          .toList();

      if (userIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _users = {};
          _pendingByUser = {};
          _activeByUser = {};
          _loading = false;
        });
        return;
      }

      // 2) Load users (scoped)
      final usersData = await supabase
          .from('users')
          .select('id, full_name')
          .inFilter('id', userIds);

      final usersMap = <String, dynamic>{};
      for (final user in usersData as List<dynamic>) {
        final m = user as Map<String, dynamic>;
        usersMap[m['id'].toString()] = (m['full_name'] ?? 'Unknown User')
            .toString();
      }

      // 3) Load beneficiaries for those users only
      final beneficiariesData = await supabase
          .from('beneficiaries')
          .select(
            'id, user_id, full_name, relationship, dob, status, birth_certificate',
          )
          .inFilter('user_id', userIds)
          .inFilter('status', ['Approved', 'Pending'])
          .order('full_name', ascending: true);

      // 4) Group and split by status
      final pendingByUser = <String, List<dynamic>>{};
      final activeByUser = <String, List<dynamic>>{};
      for (final raw in beneficiariesData as List<dynamic>) {
        final b = raw as Map<String, dynamic>;
        final uid = (b['user_id'] ?? '').toString();
        if (uid.isEmpty) continue;
        final status = (b['status'] ?? '').toString();
        if (status == 'Pending') {
          pendingByUser.putIfAbsent(uid, () => []).add(b);
        } else if (status == 'Approved') {
          activeByUser.putIfAbsent(uid, () => []).add(b);
        }
      }

      if (!mounted) return;
      setState(() {
        _users = usersMap;
        _pendingByUser = pendingByUser;
        _activeByUser = activeByUser;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching beneficiaries: $e')),
      );
    }
  }

  Future<void> _approveBeneficiary(dynamic id) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase
          .from('beneficiaries')
          .update({'status': 'Approved', 'eligible_to_claim': true})
          .eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Beneficiary approved!')));
      await _fetchBeneficiaries(); // Refresh
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error approving: $e')));
    }
  }

  Widget _groupedList(
    Map<String, List<dynamic>> grouped, {
    bool isPending = false,
  }) {
    if (grouped.isEmpty) {
      // Empty state (matches the new UI style)
      return Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color:
                      (isPending
                              ? const Color(0xFF10B981)
                              : const Color(0xFFFF6B35))
                          .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Icon(
                  isPending
                      ? Icons.schedule_rounded
                      : Icons.check_circle_rounded,
                  color: isPending
                      ? const Color(0xFF10B981)
                      : const Color(0xFFFF6B35),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isPending
                    ? 'No active beneficiaries found'
                    : 'No pending beneficiaries found',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                  fontFamily: 'Montserrat',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isPending
                    ? 'No active beneficiaries have been recorded yet'
                    : 'No pending beneficiaries have been recorded yet',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  fontFamily: 'OpenSans',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final sortedUserIds = grouped.keys.toList()
      ..sort(
        (a, b) => (_users[a] ?? '').toString().compareTo(
          (_users[b] ?? '').toString(),
        ),
      );

    return ListView.builder(
      itemCount: sortedUserIds.length,
      itemBuilder: (context, idx) {
        final userId = sortedUserIds[idx];
        final userName = _users[userId] ?? 'Unknown User';
        final beneficiaries = grouped[userId]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(
                userName.toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ),
            // Cards
            ...beneficiaries
                .map(
                  (b) => _beneficiaryCard(
                    Map<String, dynamic>.from(b as Map),
                    isPending: isPending,
                  ),
                )
                .toList(),
          ],
        );
      },
    );
  }

  Widget _beneficiaryCard(Map b, {bool isPending = false}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo.shade100,
                  child: const Icon(Icons.person, color: Colors.indigo),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (b['full_name'] ?? '').toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.indigo,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: b['status'] == 'Pending'
                        ? Colors.orange.shade100
                        : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    (b['status'] ?? '').toString(),
                    style: TextStyle(
                      color: b['status'] == 'Pending'
                          ? Colors.orange.shade800
                          : Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _infoRow(
              Icons.family_restroom,
              'Relationship: ${(b['relationship'] ?? '').toString()}',
            ),
            _infoRow(Icons.cake, 'DOB: ${(b['dob'] ?? '').toString()}'),
            if ((b['birth_certificate'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                  label: const Text('View Birth Certificate'),
                  onPressed: () => _showBirthCertificateModal(
                    b['birth_certificate'].toString(),
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                ),
              ),
            if (isPending)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _approveBeneficiary(b['id']),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showBirthCertificateModal(String url) async {
    final isPdf = url.toLowerCase().endsWith('.pdf');
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 350,
          height: 500,
          padding: const EdgeInsets.all(12),
          child: isPdf ? _PdfViewer(url: url) : _ImageViewer(url: url),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kPrimaryDark,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF1E40AF),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.family_restroom_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Beneficiaries',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Navigation Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _NavTab(
                    label: 'Active',
                    icon: Icons.schedule_rounded,
                    selected: _selectedTab == 0,
                    onTap: () => setState(() => _selectedTab = 0),
                  ),
                  const SizedBox(width: 40),
                  _NavTab(
                    label: 'Pending',
                    icon: Icons.check_circle_rounded,
                    selected: _selectedTab == 1,
                    onTap: () => setState(() => _selectedTab = 1),
                  ),
                ],
              ),
            ),
            // Search Bar (placeholder)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.search_rounded, color: Colors.grey, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Find beneficiary',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Content (wired to backend data)
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchBeneficiaries,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_selectedTab == 0
                          ? _groupedList(_activeByUser, isPending: true)
                          : _groupedList(_pendingByUser, isPending: false)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? const Color(0xFF3B82F6)
                    : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF6B7280),
                  fontFamily: 'Montserrat',
                ),
              ),
            ],
          ),
          if (selected) ...[
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: label.length * 8.0,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// PDF Viewer Widget
class _PdfViewer extends StatelessWidget {
  final String url;
  const _PdfViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'PDF preview is not implemented.\nOpen this PDF in browser:\n$url',
        textAlign: TextAlign.center,
      ),
    );
  }
}

// Image Viewer Widget
class _ImageViewer extends StatelessWidget {
  final String url;
  const _ImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: PhotoView(
        imageProvider: NetworkImage(url),
        backgroundDecoration: const BoxDecoration(color: Colors.white),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
        loadingBuilder: (context, event) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, stackTrace) =>
            const Center(child: Text('Failed to load image')),
      ),
    );
  }
}
