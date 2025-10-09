import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:photo_view/photo_view.dart'; // Add this to your pubspec.yaml for image preview

class SecretaryBeneficiariesTab extends StatefulWidget {
  const SecretaryBeneficiariesTab({super.key});

  @override
  State<SecretaryBeneficiariesTab> createState() =>
      _SecretaryBeneficiariesTabState();
}

class _SecretaryBeneficiariesTabState extends State<SecretaryBeneficiariesTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _users = {};
  Map<String, List<dynamic>> _pendingByUser = {};
  Map<String, List<dynamic>> _activeByUser = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchBeneficiaries();
  }

  Future<void> _fetchBeneficiaries() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;
    try {
      final usersData = await supabase.from('users').select('id, full_name');
      final beneficiariesData = await supabase
          .from('beneficiaries')
          .select()
          .inFilter('status', ['Pending', 'Approved'])
          .order('full_name', ascending: true);

      final usersMap = <String, dynamic>{};
      for (final user in usersData) {
        usersMap[user['id']] = user['full_name'] ?? 'Unknown User';
      }

      final pendingByUser = <String, List<dynamic>>{};
      final activeByUser = <String, List<dynamic>>{};
      for (final b in beneficiariesData) {
        final uid = b['user_id'];
        if (b['status'] == 'Pending') {
          pendingByUser.putIfAbsent(uid, () => []).add(b);
        } else if (b['status'] == 'Approved') {
          activeByUser.putIfAbsent(uid, () => []).add(b);
        }
      }

      setState(() {
        _users = usersMap;
        _pendingByUser = pendingByUser;
        _activeByUser = activeByUser;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching beneficiaries: $e')),
      );
    }
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
                    b['full_name'] ?? '',
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
                    b['status'] ?? '',
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
              'Relationship: ${b['relationship'] ?? ''}',
            ),
            _infoRow(Icons.cake, 'DOB: ${b['dob'] ?? ''}'),
            if (b['birth_certificate'] != null &&
                b['birth_certificate'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                  label: const Text('View Birth Certificate'),
                  onPressed: () =>
                      _showBirthCertificateModal(b['birth_certificate']),
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

  Future<void> _approveBeneficiary(dynamic id) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase
          .from('beneficiaries')
          .update({
            'status': 'Approved',
            'eligible_to_claim': true,
          }) // <-- add this
          .eq('id', id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Beneficiary approved!')));
      _fetchBeneficiaries(); // Refresh the list
    } catch (e) {
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
      return const Center(child: Text('No beneficiaries found.'));
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(
                userName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ),
            ...beneficiaries
                .map((b) => _beneficiaryCard(b, isPending: isPending))
                .toList(),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beneficiaries'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Active'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _groupedList(_pendingByUser, isPending: true),
                _groupedList(_activeByUser),
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
      // For real PDF preview, use flutter_pdfview or advance_pdf_viewer package.
      // Example:
      // return PDFView(filePath: ...);
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
