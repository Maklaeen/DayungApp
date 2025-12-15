import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);

class ManageBeneficiariesPage extends StatefulWidget {
  const ManageBeneficiariesPage({super.key});

  @override
  State<ManageBeneficiariesPage> createState() =>
      _ManageBeneficiariesPageState();
}

class _ManageBeneficiariesPageState extends State<ManageBeneficiariesPage> {
  late Future<List<Map<String, dynamic>>> _beneficiariesFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _beneficiariesFuture = _fetchBeneficiaries();
  }

  Future<List<Map<String, dynamic>>> _fetchBeneficiaries() async {
    final sb = Supabase.instance.client;
    final res = await sb
        .from('beneficiaries')
        .select(
          'id, full_name, dob, marital_status, relationship, status, eligible_to_claim',
        );
    return List<Map<String, dynamic>>.from(res);
  }

  void _editBeneficiary(Map<String, dynamic> beneficiary) async {
    // You can implement an edit modal similar to the users modal if needed
    // For now, just show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Edit for "${beneficiary['full_name']}" coming soon!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: themeBg,
      appBar: AppBar(
        title: const Text('Manage Beneficiaries'),
        backgroundColor: kPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by name or relationship...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: kCardBg,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: kPrimary.withOpacity(0.15)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: kPrimary.withOpacity(0.15)),
                  ),
                ),
                onChanged: (v) =>
                    setState(() => _search = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _beneficiariesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No beneficiaries found.'));
                  }
                  final beneficiaries = snapshot.data!
                      .where(
                        (b) =>
                            (b['full_name'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(_search) ||
                            (b['relationship'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(_search),
                      )
                      .toList();
                  if (beneficiaries.isEmpty) {
                    return const Center(
                      child: Text('No beneficiaries match your search.'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: beneficiaries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final b = beneficiaries[i];
                      return Material(
                        color: kCardBg,
                        borderRadius: BorderRadius.circular(16),
                        elevation: 1,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: kPrimary.withOpacity(0.1),
                            child: const Icon(
                              Icons.family_restroom,
                              color: kPrimary,
                            ),
                          ),
                          title: Text(
                            b['full_name'] ?? 'No Name',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Relationship: ${b['relationship'] ?? ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                'Marital Status: ${b['marital_status'] ?? ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                'DOB: ${b['dob'] ?? ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Row(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(
                                      top: 4,
                                      right: 8,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      b['status'] ?? '',
                                      style: TextStyle(
                                        color: kPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  if (b['eligible_to_claim'] == true)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Eligible to Claim',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit, color: kPrimary),
                            onPressed: () => _editBeneficiary(b),
                            tooltip: 'Edit Beneficiary',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
