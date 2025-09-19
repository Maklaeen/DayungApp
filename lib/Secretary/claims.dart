import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecretaryClaimsPage extends StatefulWidget {
  const SecretaryClaimsPage({super.key});

  @override
  State<SecretaryClaimsPage> createState() => _SecretaryClaimsPageState();
}

class _SecretaryClaimsPageState extends State<SecretaryClaimsPage> {
  final supabase = Supabase.instance.client;

  String _selectedTab = "Pending";
  bool _loading = true;
  List<Map<String, dynamic>> _claims = [];

  @override
  void initState() {
    super.initState();
    _fetchClaims();
  }

  Future<void> _fetchClaims() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('claims')
          .select('id, title, description, status, date_submitted')
          .eq('status', _selectedTab)
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
          .select(); // ← para bumalik yung updated row

      debugPrint("Update result: $res");

      _fetchClaims(); // refresh list
    } catch (e) {
      debugPrint("Error updating status: $e");
    }
  }

  Widget _tabButton(String label) {
    final bool isActive = _selectedTab == label;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTab = label);
          _fetchClaims();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.blue.shade700 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isActive ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _claimItem(Map<String, dynamic> claim) {
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
                if (_selectedTab == "Pending") ...[
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
                if (_selectedTab != "Pending")
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Claims Management"),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                _tabButton("Pending"),
                const SizedBox(width: 8),
                _tabButton("Approved"),
                const SizedBox(width: 8),
                _tabButton("Rejected"),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _claims.isEmpty
                  ? const Center(child: Text("No claims found"))
                  : ListView.builder(
                      itemCount: _claims.length,
                      itemBuilder: (context, index) =>
                          _claimItem(_claims[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
