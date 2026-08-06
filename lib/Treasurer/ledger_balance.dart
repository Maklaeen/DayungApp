import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPageBg = Color(0xFFFAFAF7);
const Color _kHeaderGradientStart = Color(0xFF083366);
const Color _kHeaderGradientEnd = Color(0xFF0D47A1);
const Color _kCard = Colors.white;
const Color _kBorder = Color(0xFFE5E7EB);

bool _isTruthyFlag(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return ['true', '1', 'yes'].contains(value.trim().toLowerCase());
  }
  return false;
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

class LedgerBalancePage extends StatefulWidget {
  final int dayungUnitId;

  const LedgerBalancePage({super.key, required this.dayungUnitId});

  @override
  State<LedgerBalancePage> createState() => _LedgerBalancePageState();
}

class _LedgerBalancePageState extends State<LedgerBalancePage> {
  static const Duration _queryTimeout = Duration(seconds: 10);

  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _collectorSummaries = [];
  double _treasurerCollectedTotal = 0.0;
  double _currentCashCollected = 0.0;
  double _totalDeceasedPaymentAmount = 0.0;

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
          namesById['${row['id']}'] =
              ((row['full_name'] ?? 'Collector') as String).trim();
        }
      }

      final currentUserId = sb.auth.currentUser?.id ?? '';
      final rawPaymentRows = List<Map<String, dynamic>>.from(
        await sb
            .from('payments')
            .select(
              'id, amount, collected_by, userdeceased, deceased_name, status, type, is_claimed, iscollectedbytreasurer, iscollectedbytreasurer_date',
            )
            .eq('dayung_unit_id', widget.dayungUnitId)
            .inFilter('status', ['paid', 'unpaid'])
            .order('paid_at', ascending: false)
            .timeout(_queryTimeout),
      );

      final paymentRows = rawPaymentRows.where((row) {
        final claimedValue = row['is_claimed'];
        if (claimedValue is bool) return !claimedValue;
        if (claimedValue is num) return claimedValue == 0;
        if (claimedValue is String) {
          final normalized = claimedValue.trim().toLowerCase();
          return normalized != 'true' &&
              normalized != '1' &&
              normalized != 'yes';
        }
        return true;
      }).toList();

      final totalDeceasedPaymentAmount = paymentRows
          .where((row) {
            if (row['type'] != 'deceased_payment') return false;

            final statusValue = '${row['status'] ?? ''}'.trim().toLowerCase();
            return statusValue == 'paid' || statusValue == 'unpaid';
          })
          .fold<double>(0.0, (sum, row) => sum + _asDouble(row['amount']));

      final currentCashCollected = paymentRows.fold<double>(0.0, (sum, row) {
        final typeValue = row['type']?.toString().toLowerCase();
        final collectedBy = '${row['collected_by'] ?? ''}'.trim();

        if (typeValue != 'deceased_payment' || collectedBy != currentUserId) {
          return sum;
        }

        return sum + _asDouble(row['amount']);
      });

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
          memberNamesById['${row['id']}'] =
              ((row['full_name'] ?? 'Member') as String).trim();
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

      var treasurerCollectedTotal = 0.0;
      for (final row in paymentRows) {
        if (row['type'] != 'deceased_payment') continue;

        final isTreasurerCollected = _isTruthyFlag(
          row['iscollectedbytreasurer'],
        );
        final isClaimed = _isTruthyFlag(row['is_claimed']);
        if (isTreasurerCollected && !isClaimed) {
          treasurerCollectedTotal += _asDouble(row['amount']);
        }

        final collectorId = '${row['collected_by']}';
        final summary = summaries[collectorId];
        if (summary == null) continue;

        final amountContribution = isTreasurerCollected
            ? 0.0
            : _asDouble(row['amount']);

        summary['amount'] = _asDouble(summary['amount']) + amountContribution;
        summary['count'] = (summary['count'] as int) + 1;

        final memberId = '${row['userdeceased'] ?? ''}'.trim();
        final memberKey = memberId.isEmpty ? '__unknown__' : memberId;
        final memberTotals = summary['member_totals'] as Map<String, dynamic>;

        final receivedDate = _normalizeReceivedDate(
          row['iscollectedbytreasurer_date'],
        );

        if (!memberTotals.containsKey(memberKey)) {
          memberTotals[memberKey] = {
            'id': memberId,
            'name':
                (row['deceased_name'] ?? memberNamesById[memberId] ?? 'Member')
                    .toString(),
            'amount': 0.0,
            'payment_ids': <String>[],
            'is_received': isTreasurerCollected,
            'received_date': receivedDate,
          };
        }

        final memberEntry = memberTotals[memberKey] as Map<String, dynamic>;
        memberEntry['amount'] =
            _asDouble(memberEntry['amount']) + amountContribution;
        memberEntry['is_received'] =
            (memberEntry['is_received'] as bool? ?? true) &&
            isTreasurerCollected;
        if (isTreasurerCollected && receivedDate != null) {
          memberEntry['received_date'] = receivedDate;
        }

        final paymentId = '${row['id'] ?? ''}'.trim();
        if (paymentId.isNotEmpty) {
          final paymentIds = List<String>.from(
            memberEntry['payment_ids'] ?? [],
          );
          if (!paymentIds.contains(paymentId)) {
            paymentIds.add(paymentId);
            memberEntry['payment_ids'] = paymentIds;
          }
        }
      }

      final collectorSummaries =
          summaries.values.toList().map((entry) {
            final memberTotals = <Map<String, dynamic>>[];
            final memberEntries =
                entry['member_totals'] as Map<String, dynamic>;
            for (final memberEntry in memberEntries.values) {
              memberTotals.add({
                'id': (memberEntry as Map<String, dynamic>)['id'],
                'name': (memberEntry)['name'],
                'amount': _asDouble(memberEntry['amount']),
                'payment_ids': List<String>.from(
                  memberEntry['payment_ids'] ?? [],
                ),
                'is_received': (memberEntry)['is_received'] == true,
                'received_date': (memberEntry)['received_date']?.toString(),
              });
            }
            memberTotals.sort(
              (a, b) =>
                  _asDouble(b['amount']).compareTo(_asDouble(a['amount'])),
            );

            return {
              'id': entry['id'],
              'name': entry['name'],
              'amount': _asDouble(entry['amount']),
              'count': entry['count'] as int,
              'member_totals': memberTotals,
            };
          }).toList()..sort(
            (a, b) => _asDouble(b['amount']).compareTo(_asDouble(a['amount'])),
          );

      if (!mounted) return;
      setState(() {
        _collectorSummaries = collectorSummaries;
        _treasurerCollectedTotal = treasurerCollectedTotal;
        _currentCashCollected = currentCashCollected;
        _totalDeceasedPaymentAmount = totalDeceasedPaymentAmount;
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

  Future<bool> _markPaymentReceived(
    List<String> paymentIds,
    String memberName,
  ) async {
    if (paymentIds.isEmpty) return false;

    try {
      await sb
          .from('payments')
          .update({
            'iscollectedbytreasurer': true,
            'iscollectedbytreasurer_date': DateTime.now()
                .toUtc()
                .toIso8601String(),
          })
          .inFilter('id', paymentIds)
          .timeout(_queryTimeout);

      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked $memberName as received.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      await _loadCollectorTotals();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update receipt status: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return false;
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
      final updated = await _markPaymentReceived(paymentIds, memberName);
      if (updated) onConfirmed?.call();
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
                                      _formatCurrency(
                                        _asDouble(member['amount']),
                                      ),
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
                                          style: TextStyle(fontSize: 11),
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
                                              member['is_received'] = true;
                                              member['received_date'] =
                                                  _normalizeReceivedDate(
                                                    DateTime.now(),
                                                  );
                                              setDialogState(() {});
                                            },
                                          );
                                        },
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        member['is_received'] == true
                                        ? Colors.grey
                                        : const Color(0xFF10B981),
                                  ),
                                  child: Text(
                                    member['is_received'] == true
                                        ? (member['received_date'] != null &&
                                                  member['received_date']
                                                      .toString()
                                                      .isNotEmpty
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

  Widget _summaryCard({
    required String title,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
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

  @override
  Widget build(BuildContext context) {
    final totalCollected = _treasurerCollectedTotal + _currentCashCollected;

    return Scaffold(
      backgroundColor: _kPageBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kHeaderGradientStart, _kHeaderGradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22083366),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Ledger Balance',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            // SizedBox(height: 6),
                            // Text(
                            //   'Confirm remitted funds before posting to the ledger.',
                            //   style: TextStyle(
                            //     color: Colors.white70,
                            //     fontSize: 13,
                            //     height: 1.5,
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          title: 'Number of Userdeceased',
                          value: '${_collectorSummaries.length}',
                          accent: const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryCard(
                          title: 'Total Collected',
                          value: _formatCurrency(totalCollected),
                          accent: const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryCard(
                          title: 'Current Cash',
                          value: _formatCurrency(_currentCashCollected),
                          accent: const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryCard(
                          title: 'Ledger Balance',
                          value: _formatCurrency(_totalDeceasedPaymentAmount),
                          accent: const Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _loadCollectorTotals,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCollectorTotals,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            const Text(
                              'Collector totals',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_collectorSummaries.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: _kCard,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _kBorder),
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
                                    color: _kCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _kBorder),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () =>
                                              _showCollectorDetailsDialog(
                                                collector,
                                              ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                collector['name']?.toString() ??
                                                    'Collector',
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
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _formatCurrency(
                                              _asDouble(collector['amount']),
                                            ),
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
                                );
                              }),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
