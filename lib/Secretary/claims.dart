import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecretaryClaimsPage extends StatefulWidget {
  const SecretaryClaimsPage({super.key});

  @override
  State<SecretaryClaimsPage> createState() => _SecretaryClaimsPageState();
}

class _SecretaryClaimsPageState extends State<SecretaryClaimsPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;
  bool _loading = true;
  List<Map<String, dynamic>> _claims = [];

  final List<String> _tabs = ["Pending", "Approved", "Rejected"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _fetchClaims();
    });
    _fetchClaims();
  }

  Future<void> _fetchClaims() async {
    setState(() => _loading = true);
    try {
      final status = _tabs[_tabController.index];
      final data = await supabase
          .from('claims')
          .select('id, title, description, status, date_submitted')
          .eq('status', status)
          .order('date_submitted', ascending: false);

      setState(() {
        _claims = (data as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint("Error fetching claims: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String claimId, String newStatus) async {
    try {
      debugPrint("Updating claimId=$claimId to $newStatus");

      final res = await supabase
          .from('claims')
          .update({'status': newStatus})
          .eq('id', claimId)
          .select();

      debugPrint("Update result: $res");

      _fetchClaims(); // refresh list
    } catch (e) {
      debugPrint("Error updating status: $e");
    }
  }

  Widget _claimItem(Map<String, dynamic> claim) {
    final status = _tabs[_tabController.index];
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              claim['title'] ?? "Untitled",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              claim['description'] ?? "",
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Text(
              "Status: ${claim['status']}",
              style: TextStyle(
                fontSize: 12,
                color: claim['status'] == "Pending"
                    ? Colors.orange
                    : claim['status'] == "Approved"
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == "Pending") ...[
                  ElevatedButton(
                    onPressed: () => _updateStatus(claim['id'], "Approved"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text("Approve"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _updateStatus(claim['id'], "Rejected"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text("Reject"),
                  ),
                ],
                if (status != "Pending")
                  ElevatedButton(
                    onPressed: () => _updateStatus(claim['id'], "Pending"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text("Set Pending"),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Claims Management"),
        backgroundColor: Colors.blue.shade700,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.black,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            fontFamily: 'Montserrat',
          ),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _claims.isEmpty
            ? const Center(child: Text("No claims found"))
            : ListView.builder(
                itemCount: _claims.length,
                itemBuilder: (context, index) => _claimItem(_claims[index]),
              ),
      ),
    );
  }
}
