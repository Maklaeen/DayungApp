import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);

class MembersPage extends StatefulWidget {
  final int? dayungUnitId;
  const MembersPage({super.key, this.dayungUnitId});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage>
    with SingleTickerProviderStateMixin {
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

  Future<List<Map<String, dynamic>>> fetchPayments({
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await Supabase.instance.client
          .from('payments')
          .select(
            'user_id, amount, created_at, collected_by, users!payments_user_id_fkey(full_name), collector:users!payments_collected_by_fkey(full_name)',
          )
          .range(offset, offset + limit - 1);

      return (response as List)
          .map(
            (item) => {
              'user_id': item['user_id'].toString(),
              'amount': item['amount'].toString(),
              'full_name': item['users']?['full_name'] ?? 'Unknown',
              'created_at': item['created_at'] ?? '',
              'collected_by': item['collected_by']?.toString() ?? '',
              'collector_full_name':
                  item['collector']?['full_name'] ?? 'Unknown',
            },
          )
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  List<Map<String, dynamic>> _filterPayments(
    List<Map<String, dynamic>> payments,
  ) {
    if (_searchQuery.isEmpty) return payments;
    final isNumeric = double.tryParse(_searchQuery) != null;
    if (isNumeric) {
      return payments
          .where((p) => p['amount'].toString().contains(_searchQuery))
          .toList();
    } else {
      return payments
          .where(
            (p) => p['full_name'].toString().toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ),
          )
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Curved Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Icon(
                    Icons.people_alt_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Members',
                      style: TextStyle(
                        fontSize: 20,
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
            // TabBar
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: kAccent,
                unselectedLabelColor: kSubText,
                indicatorColor: kAccent,
                tabs: const [Tab(text: 'All Members')],
              ),
            ),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              labelText: 'Search by name or amount',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                            ),
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
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: kAccent,
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            final payments = snapshot.data ?? [];
                            if (payments.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: kSubText,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No payments found.',
                                      style: TextStyle(
                                        color: kSubText,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            payments.sort(
                              (a, b) =>
                                  b['created_at'].compareTo(a['created_at']),
                            );

                            final filteredPayments = _filterPayments(payments);

                            if (filteredPayments.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      color: kSubText,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No results found.',
                                      style: TextStyle(
                                        color: kSubText,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: filteredPayments.length,
                              itemBuilder: (context, i) {
                                final payment = filteredPayments[i];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  elevation: 2,
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        // Name and Amount
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                payment['full_name'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: kText,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Amount: ₱${payment['amount']}',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  color: kAccent,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Date: ${payment['created_at'].toString().split('T').first}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: kSubText,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Collected By
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text(
                                              'Collected By',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: kSubText,
                                              ),
                                            ),
                                            Text(
                                              payment['collector_full_name'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: kAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
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
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
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
            ),
          ],
        ),
      ),
    );
  }
}
