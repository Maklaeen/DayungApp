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

      // 4. Aggregate per collector
      final collectors = <String, Map<String, dynamic>>{};
      for (final id in collectorIds) {
        collectors[id] = {
          'name': userMap[id] ?? 'Collector',
          'amount': 0.0,
          'members': <String>{},
        };
      }
      for (final p in payments) {
        final collectorId = p['collected_by'];
        if (collectorId == null) continue;
        if (!collectors.containsKey(collectorId)) {
          // In case collector was removed from dayung_collectors but has collection
          collectors[collectorId] = {
            'name': userMap[collectorId] ?? 'Collector',
            'amount': 0.0,
            'members': <String>{},
          };
        }
        collectors[collectorId]!['amount'] += (p['amount'] as num).toDouble();
        collectors[collectorId]!['members'].add(p['user_id']);
      }

      final collectorList = collectors.entries.map((e) {
        return {
          'name': e.value['name'],
          'amount': e.value['amount'],
          'members': (e.value['members'] as Set).length,
        };
      }).toList();

      setState(() {
        _collectors = collectorList;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _selectedDateRange,
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(primary: kPrimaryDark),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _fetchCollectors();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedDeceasedId = null;
      _selectedDateRange = null;
    });
    _fetchCollectors();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimaryDark, size: 28),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text(
          'Collected',
          style: TextStyle(
            color: kPrimaryDark,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            fontFamily: 'Montserrat',
            letterSpacing: .2,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kPrimaryDark),
            onPressed: _fetchCollectors,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          children: [
            // Filter Row
            Row(
              children: [
                // Deceased filter
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedDeceasedId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'By Deceased',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('All Deceased'),
                      ),
                      ..._deceasedList.map(
                        (d) => DropdownMenuItem<int>(
                          value: d['id'] as int,
                          child: Text(
                            '${d['name']} (${d['date_of_death'] ?? ''})',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedDeceasedId = v;
                      });
                      _fetchCollectors();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Date filter
                ElevatedButton.icon(
                  icon: const Icon(Icons.date_range, size: 20),
                  label: Text(
                    _selectedDateRange == null
                        ? 'By Date'
                        : '${_selectedDateRange!.start.month}/${_selectedDateRange!.start.day} - ${_selectedDateRange!.end.month}/${_selectedDateRange!.end.day}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onPressed: _pickDateRange,
                ),
                if (_selectedDeceasedId != null || _selectedDateRange != null)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.red),
                    tooltip: 'Clear Filters',
                    onPressed: _clearFilters,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 18),
                      ),
                    )
                  : _collectors.isEmpty
                  ? const Center(
                      child: Text(
                        'No collectors found.',
                        style: TextStyle(
                          fontSize: 20,
                          color: kSubtleText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : GridView.builder(
                      itemCount: _collectors.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 18,
                            crossAxisSpacing: 18,
                            childAspectRatio: 1.1,
                          ),
                      itemBuilder: (context, i) {
                        final c = _collectors[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 10,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                c['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  fontFamily: 'Montserrat',
                                  color: kNeutralText,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '₱ ${c['amount'].toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 22,
                                  fontFamily: 'Montserrat',
                                  color: kNeutralText,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${c['members']} collected\nfrom members',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'OpenSans',
                                  color: kSubtleText,
                                  height: 1.3,
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
    );
  }
}
