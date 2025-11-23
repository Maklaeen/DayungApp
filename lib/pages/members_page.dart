import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MembersPage extends StatefulWidget {
  final int? dayungUnitId;
  const MembersPage({Key? key, this.dayungUnitId}) : super(key: key);

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentPage = 0;
  static const int _pageSize = 50;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> fetchPayments({required int limit, required int offset}) async {
    try {
      final response = await Supabase.instance.client
          .from('payments')
          .select('user_id, amount, created_at, collected_by, users!payments_user_id_fkey(full_name), collector:users!payments_collected_by_fkey(full_name)')
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((item) => {
                'user_id': item['user_id'].toString(),
                'amount': item['amount'].toString(),
                'full_name': item['users']?['full_name'] ?? 'Unknown',
                'created_at': item['created_at'] ?? '',
                'collected_by': item['collected_by']?.toString() ?? '',
                'collector_full_name': item['collector']?['full_name'] ?? 'Unknown',
              })
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  List<Map<String, dynamic>> _filterPayments(List<Map<String, dynamic>> payments) {
    if (_searchQuery.isEmpty) return payments;
    final isNumeric = double.tryParse(_searchQuery) != null;
    if (isNumeric) {
      // Search by amount (partial match)
      return payments.where((p) => p['amount'].toString().contains(_searchQuery)).toList();
    } else {
      // Search by full name (case-insensitive)
      return payments.where((p) =>
        p['full_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All Members'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search by name or amount',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: fetchPayments(
                    limit: _pageSize,
                    offset: _currentPage * _pageSize,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    final payments = snapshot.data ?? [];
                    if (payments.isEmpty) {
                      return const Center(child: Text('No payments found.'));
                    }

                    payments.sort((a, b) =>
                        b['created_at'].compareTo(a['created_at']));

                    final filteredPayments = _filterPayments(payments);

                    if (filteredPayments.isEmpty) {
                      return const Center(child: Text('No results found.'));
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Full Name')),
                          DataColumn(label: Text('Amount')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Collected By')), // <-- new column
                        ],
                        rows: filteredPayments.map((payment) {
                          return DataRow(
                            cells: [
                              DataCell(Text(payment['full_name'])),
                              DataCell(Text(payment['amount'])),
                              DataCell(Text(
                                payment['created_at']
                                    .toString()
                                    .split('T').first,
                              )),
                              DataCell(Text(payment['collector_full_name'])), // <-- new cell
                            ],
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _currentPage > 0
                          ? () {
                              setState(() {
                                _currentPage--;
                              });
                            }
                          : null,
                      child: const Text('Previous'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _currentPage++;
                        });
                      },
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}