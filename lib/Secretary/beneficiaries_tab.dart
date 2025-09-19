import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
      // Fetch all users (id, full_name)
      final usersData = await supabase.from('users').select('id, full_name');
      // Fetch all beneficiaries
      final beneficiariesData = await supabase
          .from('beneficiaries')
          .select()
          .inFilter('status', ['Pending', 'Approved'])
          .order('full_name', ascending: true);

      // Map user_id to user full_name
      final usersMap = <String, dynamic>{};
      for (final user in usersData) {
        usersMap[user['id']] = user['full_name'] ?? 'Unknown User';
      }

      // Group beneficiaries by user_id
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
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: ListTile(
        leading: const Icon(Icons.person, color: Colors.blue),
        title: Text(
          b['full_name'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Relationship: ${b['relationship'] ?? ''}'),
            Text('DOB: ${b['dob'] ?? ''}'),
            Text('Status: ${b['status'] ?? ''}'),
            if (b['birth_certificate'] != null &&
                b['birth_certificate'].toString().isNotEmpty)
              InkWell(
                onTap: () => launchUrl(Uri.parse(b['birth_certificate'])),
                child: const Padding(
                  padding: EdgeInsets.only(top: 4.0),
                  child: Text(
                    'View Birth Certificate',
                    style: TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            if (isPending)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 36),
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

  Future<void> _approveBeneficiary(dynamic id) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase
          .from('beneficiaries')
          .update({'status': 'Approved'})
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
    // Sort user names alphabetically
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
