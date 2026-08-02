import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPrimary = Color(0xFF0D47A1);
const Color _kPrimaryDark = Color(0xFF083366);
const Color _kNeutralText = Color(0xFF1F2937);
const Color _kSubText = Color(0xFF4B5563);
const Color _kSuccess = Color(0xFF10B981);
const Color _kWarn = Color(0xFFF59E0B);
const Color _kPurple = Color(0xFF7C3AED);

class CollectorProgressPage extends StatefulWidget {
  final int dayungUnitId;

  const CollectorProgressPage({super.key, required this.dayungUnitId});

  @override
  State<CollectorProgressPage> createState() => _CollectorProgressPageState();
}

class _CollectorProgressPageState extends State<CollectorProgressPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  final List<_CollectorProgressItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final rows = await _sb
          .from('payments')
          .select('user_id, userdeceased, deceased_name, status, created_at')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('type', 'deceased_payment')
          .order('created_at', ascending: false);

      final payments = List<Map<String, dynamic>>.from(rows);
      final deceasedIds = <String>{};
      for (final row in payments) {
        final deceasedId = (row['userdeceased'] ?? '').toString().trim();
        if (deceasedId.isNotEmpty) deceasedIds.add(deceasedId);
      }

      final userNames = <String, String>{};
      if (deceasedIds.isNotEmpty) {
        for (final deceasedId in deceasedIds) {
          final usersRows = await _sb
              .from('users')
              .select('id, full_name')
              .eq('id', deceasedId)
              .limit(1);
          for (final row in List<Map<String, dynamic>>.from(usersRows)) {
            final id = (row['id'] ?? '').toString().trim();
            final fullName = (row['full_name'] ?? '').toString().trim();
            if (id.isNotEmpty && fullName.isNotEmpty) {
              userNames[id] = fullName;
            }
          }
        }
      }

      final grouped = <String, _CollectorProgressBucket>{};

      for (final row in payments) {
        final deceasedId = (row['userdeceased'] ?? '').toString().trim();
        final deceasedName = (row['deceased_name'] ?? '').toString().trim();
        final memberId = (row['user_id'] ?? '').toString().trim();
        final status = (row['status'] ?? '').toString().toLowerCase();

        final bucketKey = deceasedId.isNotEmpty ? deceasedId : deceasedName;
        if (bucketKey.isEmpty || memberId.isEmpty) continue;

        final resolvedName = userNames[deceasedId] ?? deceasedName;
        final bucket = grouped.putIfAbsent(
          bucketKey,
          () => _CollectorProgressBucket(
            name: resolvedName.isNotEmpty ? resolvedName : 'Deceased',
          ),
        );

        if (bucket.name == 'Deceased' && resolvedName.isNotEmpty) {
          bucket.name = resolvedName;
        }

        bucket.expectedMemberIds.add(memberId);
        if (status == 'paid') {
          bucket.paidMemberIds.add(memberId);
        }
      }

      final items =
          grouped.entries
              .map(
                (entry) => _CollectorProgressItem(
                  name: entry.value.name,
                  paid: entry.value.paidMemberIds.length.toDouble(),
                  goal: entry.value.expectedMemberIds.length.toDouble(),
                ),
              )
              .where((item) => item.goal > 0)
              .toList()
            ..sort((a, b) {
              final progressDiff = (a.progress.compareTo(b.progress));
              if (progressDiff != 0) return progressDiff;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });

      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(items);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _items.clear();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _items.where((item) => item.isComplete).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Collector Progress'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _summaryTile(
                              label: 'Collections',
                              value: '${_items.length}',
                              color: _kPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _summaryTile(
                              label: 'Completed',
                              value: '$completedCount',
                              color: _kSuccess,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Shows how many members have paid for each deceased member.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _kSubText,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_items.isEmpty)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Center(
                            child: Text(
                              'No collection data found.',
                              style: TextStyle(
                                color: _kSubText,
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: _kPurple.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.local_florist_rounded,
                                          color: _kPurple,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: _kNeutralText,
                                            fontFamily: 'Montserrat',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: item.isComplete
                                              ? _kSuccess.withValues(
                                                  alpha: 0.12,
                                                )
                                              : _kWarn.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          item.isComplete
                                              ? 'Completed'
                                              : 'In progress',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: item.isComplete
                                                ? _kSuccess
                                                : _kWarn,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: item.progress,
                                      minHeight: 10,
                                      backgroundColor: Colors.grey.shade100,
                                      valueColor: AlwaysStoppedAnimation(
                                        item.isComplete ? _kSuccess : _kPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${item.paid.toStringAsFixed(0)} of ${item.goal.toStringAsFixed(0)} members paid',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _kSuccess,
                                          fontFamily: 'OpenSans',
                                        ),
                                      ),
                                      Text(
                                        '${(item.goal - item.paid).toStringAsFixed(0)} remaining',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _kSubText,
                                          fontFamily: 'OpenSans',
                                        ),
                                      ),
                                    ],
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
    );
  }

  Widget _summaryTile({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
              fontFamily: 'OpenSans',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectorProgressItem {
  final String name;
  final double paid;
  final double goal;

  const _CollectorProgressItem({
    required this.name,
    required this.paid,
    required this.goal,
  });

  double get progress => goal > 0 ? (paid / goal).clamp(0.0, 1.0) : 0.0;
  bool get isComplete => goal > 0 && paid >= goal;
}

class _CollectorProgressBucket {
  String name;
  final Set<String> expectedMemberIds = <String>{};
  final Set<String> paidMemberIds = <String>{};

  _CollectorProgressBucket({required this.name});
}
