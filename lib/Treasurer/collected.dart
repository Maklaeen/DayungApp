import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class CollectedFromCollectorsPage extends StatefulWidget {
  final int dayungUnitId;
  const CollectedFromCollectorsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectedFromCollectorsPage> createState() =>
      _CollectedFromCollectorsPageState();
}

class _CollectedFromCollectorsPageState
    extends State<CollectedFromCollectorsPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _collectors = [];
  List<Map<String, dynamic>> _deceasedList = [];
  int? _selectedDeceasedId;
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _fetchDeceasedList();
    _fetchCollectors();
  }

  Future<void> _fetchDeceasedList() async {
    try {
      final res = await sb
          .from('death_notices')
          .select('id, name, date_of_death')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('date_of_death', ascending: false);
      setState(() {
        _deceasedList = List<Map<String, dynamic>>.from(res);
      });
    } catch (_) {
      setState(() {
        _deceasedList = [];
      });
    }
  }

  Future<void> _fetchCollectors() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 1. Get all collectors for this dayung
      final collectorRows = await sb
          .from('dayung_collectors')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId);
      final collectorIds = List<String>.from(
        collectorRows.map((r) => r['user_id']),
      );

      // 2. Get collector user info
      final users = collectorIds.isNotEmpty
          ? await sb
                .from('users')
                .select('id, full_name')
                .inFilter('id', collectorIds)
          : [];
      final userMap = {
        for (final u in users) u['id']: u['full_name'] ?? 'Collector',
      };

      // 3. Get all paid payments for this dayung (with filters)
      var query = sb
          .from('payments')
          .select('collected_by, amount, user_id, paid_at, death_notice_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'paid');

      if (_selectedDeceasedId != null) {
        query = query.eq('death_notice_id', _selectedDeceasedId as Object);
      }
      if (_selectedDateRange != null) {
        query = query
            .gte('paid_at', _selectedDateRange!.start.toIso8601String())
            .lte(
              'paid_at',
              _selectedDateRange!.end
                  .add(const Duration(days: 1))
                  .toIso8601String(),
            );
      }

      final payments = List<Map<String, dynamic>>.from(await query);

      // 4. Group by collector
      final collectorMap = <String, Map<String, dynamic>>{};
      for (final p in payments) {
        final collectorId = p['collected_by']?.toString();
        if (collectorId != null && collectorIds.contains(collectorId)) {
          if (!collectorMap.containsKey(collectorId)) {
            collectorMap[collectorId] = {
              'collector_id': collectorId,
              'collector_name': userMap[collectorId] ?? 'Collector',
              'total_collected': 0.0,
              'payment_count': 0,
              'recent_payment': null,
            };
          }
          final collector = collectorMap[collectorId]!;
          collector['total_collected'] =
              (collector['total_collected'] as double) +
              (p['amount'] as num).toDouble();
          collector['payment_count'] = (collector['payment_count'] as int) + 1;
          if (collector['recent_payment'] == null ||
              (p['paid_at'] as String).compareTo(
                    collector['recent_payment'] as String,
                  ) >
                  0) {
            collector['recent_payment'] = p['paid_at'];
          }
        }
      }

      setState(() {
        _collectors = collectorMap.values.toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E40AF), Color(0xFF3B82F6), Color(0xFFF8FAFC)],
            stops: [0.0, 0.3, 0.3],
          ),
        ),
        child: Column(
          children: [
            // Modern Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                children: [
                  // Top bar with back and refresh
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E40AF).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF1E40AF,
                              ).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Collected from Collectors',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Text(
                              'View collection details',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildModernIconButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      _buildModernIconButton(
                        icon: Icons.refresh_rounded,
                        onTap: _fetchCollectors,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      children: [
                        // Modern Filter Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Filters',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E40AF),
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(
                                            0xFF1E40AF,
                                          ).withValues(alpha: 0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<int?>(
                                          value: _selectedDeceasedId,
                                          hint: const Text('All Deceased'),
                                          isExpanded: true,
                                          style: const TextStyle(
                                            color: Color(0xFF1F2937),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          items: [
                                            const DropdownMenuItem<int?>(
                                              value: null,
                                              child: Text('All Deceased'),
                                            ),
                                            ..._deceasedList.map(
                                              (d) => DropdownMenuItem<int?>(
                                                value: d['id'] as int,
                                                child: Text(
                                                  d['name'] ?? 'Unknown',
                                                ),
                                              ),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedDeceasedId = value;
                                            });
                                            _fetchCollectors();
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF1E40AF,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF1E40AF,
                                        ).withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: IconButton(
                                      onPressed: () async {
                                        final range = await showDateRangePicker(
                                          context: context,
                                          firstDate: DateTime.now().subtract(
                                            const Duration(days: 365),
                                          ),
                                          lastDate: DateTime.now(),
                                        );
                                        if (range != null) {
                                          setState(() {
                                            _selectedDateRange = range;
                                          });
                                          _fetchCollectors();
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.date_range,
                                        color: Color(0xFF1E40AF),
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Collectors List
                        Expanded(
                          child: _loading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF1E40AF),
                                  ),
                                )
                              : _error != null
                              ? Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Colors.red,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _collectors.isEmpty
                              ? Container(
                                  padding: const EdgeInsets.all(40),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.grey.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.people_outline_rounded,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No collectors found',
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.grey,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'No collection data available',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                          fontFamily: 'OpenSans',
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : GridView.builder(
                                  itemCount: _collectors.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        childAspectRatio: 1.1,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 16,
                                      ),
                                  itemBuilder: (context, index) {
                                    final collector = _collectors[index];
                                    return Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(
                                            0xFF1E40AF,
                                          ).withValues(alpha: 0.2),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 15,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      const LinearGradient(
                                                        colors: [
                                                          Color(0xFF1E40AF),
                                                          Color(0xFF3B82F6),
                                                        ],
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(
                                                        0xFF1E40AF,
                                                      ).withValues(alpha: 0.3),
                                                      blurRadius: 8,
                                                      offset: const Offset(
                                                        0,
                                                        4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.person_rounded,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  collector['collector_name'] ??
                                                      'Collector',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1F2937),
                                                    fontFamily: 'Montserrat',
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            '₱${(collector['total_collected'] as double).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF1E40AF),
                                              fontFamily: 'Montserrat',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF10B981,
                                              ).withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFF10B981,
                                                ).withValues(alpha: 0.3),
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              '${collector['payment_count']} payments',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF10B981),
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'Montserrat',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
