import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _isTruthyFlag(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return ['true', '1', 'yes'].contains(value.trim().toLowerCase());
  }
  return false;
}

double calculateCollectorPendingAmount({
  required List<Map<String, dynamic>> paymentRows,
  required String collectorId,
}) {
  double pendingAmount = 0.0;

  for (final row in paymentRows) {
    final rowCollectorId = '${row['collected_by'] ?? ''}'.trim();
    if (rowCollectorId != collectorId) continue;

    if (_isTruthyFlag(row['iscollectedbytreasurer'])) {
      continue;
    }

    pendingAmount += double.tryParse('${row['amount']}') ?? 0.0;
  }

  return pendingAmount;
}

class TreasurerFundConfirmationPage extends StatefulWidget {
  final int dayungUnitId;

  const TreasurerFundConfirmationPage({
    super.key,
    required this.dayungUnitId,
  });

  @override
  State<TreasurerFundConfirmationPage> createState() =>
      _TreasurerFundConfirmationPageState();
}

class _TreasurerFundConfirmationPageState
    extends State<TreasurerFundConfirmationPage> {
  static const Duration _queryTimeout = Duration(seconds: 10);

  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _collectorSummaries = [];
  double _treasurerCollectedTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCollectorTotals();
  }

  Future<void> _loadCollectorTotals() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final collectorRows = List<Map<String, dynamic>>.from(
        await sb
            .from('dayung_collectors')
            .select('user_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .timeout(_queryTimeout),
      );

      final collectorUserIds = collectorRows
          .map((row) => '${row['user_id']}')
          .where((id) => id.isNotEmpty && id != 'null')
          .toSet()
          .toList();

      final namesById = <String, String>{};
      if (collectorUserIds.isNotEmpty) {
        final userRows = List<Map<String, dynamic>>.from(
          await sb
              .from('users')
              .select('id, full_name')
              .inFilter('id', collectorUserIds)
              .timeout(_queryTimeout),
        );

        for (final row in userRows) {
          namesById['${row['id']}'] = ((row['full_name'] ?? 'Collector') as String)
              .trim();
        }
      }

      final rawPaymentRows = List<Map<String, dynamic>>.from(
        await sb
            .from('payments')
            .select(
              'id, amount, collected_by, userdeceased, deceased_name, is_claimed, iscollectedbytreasurer, iscollectedbytreasurer_date',
            )
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('status', 'paid')
            .order('paid_at', ascending: false)
            .timeout(_queryTimeout),
      );

      final paymentRows = rawPaymentRows.where((row) {
        final claimedValue = row['is_claimed'];
        if (claimedValue is bool) return !claimedValue;
        if (claimedValue is num) return claimedValue == 0;
        if (claimedValue is String) {
          final normalized = claimedValue.trim().toLowerCase();
          return normalized != 'TRUE' && normalized != '1' && normalized != 'yes';
        }
        return true;
      }).toList();

      final memberNamesById = <String, String>{};
      final memberIds = paymentRows
          .map((row) => '${row['userdeceased'] ?? ''}')
          .where((id) => id.isNotEmpty && id != 'null')
          .toSet()
          .toList();

      if (memberIds.isNotEmpty) {
        final userRows = List<Map<String, dynamic>>.from(
          await sb
              .from('users')
              .select('id, full_name')
              .inFilter('id', memberIds)
              .timeout(_queryTimeout),
        );

        for (final row in userRows) {
          memberNamesById['${row['id']}'] = ((row['full_name'] ?? 'Member') as String)
              .trim();
        }
      }

      final summaries = <String, Map<String, dynamic>>{};
      for (final collectorId in collectorUserIds) {
        summaries[collectorId] = {
          'id': collectorId,
          'name': namesById[collectorId] ?? 'Collector',
          'amount': 0.0,
          'count': 0,
          'member_totals': <String, dynamic>{},
        };
      }

      for (final row in paymentRows) {
        final collectorId = '${row['collected_by']}';
        final summary = summaries[collectorId];
        if (summary == null) continue;

        final isTreasurerCollected = _isTruthyFlag(row['iscollectedbytreasurer']);
        final amountContribution = isTreasurerCollected ? 0.0 : _asDouble(row['amount']);

        summary['amount'] = _asDouble(summary['amount']) + amountContribution;
        summary['count'] = (summary['count'] as int) + 1;

        final memberId = '${row['userdeceased'] ?? ''}'.trim();
        final memberKey = memberId.isEmpty ? '__unknown__' : memberId;
        final memberTotals = summary['member_totals'] as Map<String, dynamic>;

        final receivedDate = _normalizeReceivedDate(row['iscollectedbytreasurer_date']);

        if (!memberTotals.containsKey(memberKey)) {
          memberTotals[memberKey] = {
            'id': memberId,
            'name': (row['deceased_name'] ?? memberNamesById[memberId] ?? 'Member')
                .toString(),
            'amount': 0.0,
            'payment_ids': <String>[],
            'is_received': isTreasurerCollected,
            'received_date': receivedDate,
          };
        }

        final memberEntry = memberTotals[memberKey] as Map<String, dynamic>;
        memberEntry['amount'] = _asDouble(memberEntry['amount']) + amountContribution;
        memberEntry['is_received'] = (memberEntry['is_received'] as bool? ?? true) && isTreasurerCollected;
        if (isTreasurerCollected && receivedDate != null) {
          memberEntry['received_date'] = receivedDate;
        }

        final paymentId = '${row['id'] ?? ''}'.trim();
        if (paymentId.isNotEmpty) {
          final paymentIds = List<String>.from(memberEntry['payment_ids'] ?? []);
          if (!paymentIds.contains(paymentId)) {
            paymentIds.add(paymentId);
            memberEntry['payment_ids'] = paymentIds;
          }
        }
      }

      final treasurerCollectedTotal = paymentRows.fold<double>(
        0.0,
        (sum, row) {
          final isTreasurerCollected = _isTruthyFlag(row['iscollectedbytreasurer']);
          return isTreasurerCollected
              ? sum + _asDouble(row['amount'])
              : sum;
        },
      );

      final collectorSummaries = summaries.values.toList().map((entry) {
        final memberTotals = <Map<String, dynamic>>[];
        final memberEntries = entry['member_totals'] as Map<String, dynamic>;
        for (final memberEntry in memberEntries.values) {
          memberTotals.add({
            'id': (memberEntry as Map<String, dynamic>)['id'],
            'name': (memberEntry)['name'],
            'amount': _asDouble(memberEntry['amount']),
            'payment_ids': List<String>.from(memberEntry['payment_ids'] ?? []),
            'is_received': (memberEntry)['is_received'] == true,
            'received_date': (memberEntry)['received_date']?.toString(),
          });
        }
        memberTotals.sort((a, b) => _asDouble(b['amount']).compareTo(_asDouble(a['amount'])));

        return {
          'id': entry['id'],
          'name': entry['name'],
          'amount': _asDouble(entry['amount']),
          'count': entry['count'] as int,
          'member_totals': memberTotals,
        };
      }).toList()
        ..sort((a, b) => _asDouble(b['amount']).compareTo(_asDouble(a['amount'])));

      if (!mounted) return;
      setState(() {
        _collectorSummaries = collectorSummaries;
        _treasurerCollectedTotal = treasurerCollectedTotal;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  String? _normalizeReceivedDate(dynamic value) {
    if (value == null || value == '') return null;

    final parsedDate = value is DateTime
        ? value
        : DateTime.tryParse(value.toString());

    if (parsedDate == null) return null;

    final localDate = parsedDate.toLocal();
    final monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${monthNames[localDate.month - 1]} ${localDate.day}, ${localDate.year}';
  }

  String _formatCurrency(double amount) {
    return '₱${amount.toStringAsFixed(2)}';
  }

  Future<void> _markPaymentReceived(
    List<String> paymentIds,
    String memberName,
  ) async {
    if (paymentIds.isEmpty) return;

    try {
      await sb
          .from('payments')
          .update({
            'iscollectedbytreasurer': true,
            'iscollectedbytreasurer_date': DateTime.now().toUtc().toIso8601String(),
          })
          .inFilter('id', paymentIds)
          .timeout(_queryTimeout);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked $memberName as received.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      await _loadCollectorTotals();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update receipt status: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _confirmReceipt(
    Map<String, dynamic> member, {
    VoidCallback? onConfirmed,
  }) async {
    final memberName = member['name']?.toString() ?? 'Member';
    final paymentIds = List<String>.from(member['payment_ids'] ?? []);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Mark payment as received?'),
          content: Text(
            'This will mark the payment for $memberName as received by the treasurer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _markPaymentReceived(paymentIds, memberName);
      onConfirmed?.call();
    }
  }

  void _showCollectorDetailsDialog(Map<String, dynamic> collector) {
    final members = List<Map<String, dynamic>>.from(
      collector['member_totals'] ?? [],
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(collector['name']?.toString() ?? 'Collector'),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${members.length} member${members.length == 1 ? '' : 's'} • ${_formatCurrency(_asDouble(collector['amount']))}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (members.isEmpty)
                      const Text('No member breakdown available yet.')
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: members.map((member) {
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  member['name']?.toString() ?? 'Member',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatCurrency(_asDouble(member['amount'])),
                                      style: const TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (member['is_received'] == true)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Received by treasurer',
                                          style: TextStyle(
                                            color: Color(0xFF10B981),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: TextButton(
                                  onPressed: member['is_received'] == true
                                      ? null
                                      : () async {
                                          await _confirmReceipt(
                                            member,
                                            onConfirmed: () {
                                              setDialogState(() {
                                                final index = members.indexWhere(
                                                  (candidate) =>
                                                      candidate['id'] == member['id'] &&
                                                      candidate['name'] == member['name'],
                                                );

                                                if (index != -1) {
                                                  final updatedMember = Map<String, dynamic>.from(
                                                    members[index],
                                                  );
                                                  updatedMember['is_received'] = true;
                                                  updatedMember['received_date'] =
                                                      _normalizeReceivedDate(DateTime.now());
                                                  members[index] = updatedMember;
                                                }
                                              });
                                            },
                                          );
                                        },
                                  style: TextButton.styleFrom(
                                    foregroundColor: member['is_received'] == true
                                        ? Colors.grey
                                        : const Color(0xFF10B981),
                                  ),
                                  child: Text(
                                    member['is_received'] == true
                                        ? (member['received_date'] != null &&
                                                member['received_date'].toString().isNotEmpty
                                            ? 'Received • ${member['received_date']}'
                                            : 'Received')
                                        : 'Receive',
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCollected = _collectorSummaries.fold<double>(
      0.0,
      (sum, collector) => sum + _asDouble(collector['amount']),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger Balance'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D47A1), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Collector totals',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatCurrency(totalCollected),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total amount collected by each assigned collector',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryCard(
                            title: 'Assigned collectors',
                            value: '${_collectorSummaries.length}',
                            accent: const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _summaryCard(
                            title: 'Total Collected',
                            value: _formatCurrency(_treasurerCollectedTotal),
                            accent: const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Collector totals',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(_error!),
                      )
                    else if (_collectorSummaries.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Text(
                          'No assigned collectors or paid remittances are available yet.',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                      )
                    else
                      ..._collectorSummaries.map((collector) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _showCollectorDetailsDialog(collector),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            collector['name']?.toString() ?? 'Collector',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: Color(0xFF111827),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${collector['count']} paid remittance${collector['count'] == 1 ? '' : 's'} • tap to view members',
                                            style: const TextStyle(
                                              color: Color(0xFF6B7280),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatCurrency(_asDouble(collector['amount'])),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0D47A1),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Collected',
                                        style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
