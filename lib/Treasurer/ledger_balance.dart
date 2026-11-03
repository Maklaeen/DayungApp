import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPageBg = Color(0xFFFAFAF7);
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

double calculateDeceasedPaymentLedgerBalance(
  Iterable<Map<String, dynamic>> paymentRows,
) {
  return paymentRows
      .where((row) => row['type'] == 'deceased_payment')
      .fold<double>(0.0, (balance, row) {
        final received = _isTruthyFlag(row['iscollectedbytreasurer']);
        final claimed = _isTruthyFlag(row['is_claimed']);

        if (!received || claimed) return balance;
        return balance + _asDouble(row['amount']);
      });
}

List<Map<String, dynamic>> filterCollectorsCollectedPayments(
  Iterable<Map<String, dynamic>> paymentRows,
) {
  return paymentRows.where((row) {
    final typeValue = row['type']?.toString().toLowerCase();
    final statusValue = '${row['status'] ?? ''}'.trim().toLowerCase();
    final collectedBy = '${row['collected_by'] ?? ''}'.trim();

    return typeValue == 'deceased_payment' &&
        statusValue == 'paid' &&
        collectedBy.isNotEmpty &&
        _isTruthyFlag(row['iscollectedbytreasurer']);
  }).toList();
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
  double _collectedCollectedTotal = 0.0;
  bool _hasCollectorsCollectedPayments = false;
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
              'id, amount, collected_by, user_id, userdeceased, deceased_name, status, type, is_claimed, iscollectedbytreasurer, iscollectedbytreasurer_date',
            )
            .eq('dayung_unit_id', widget.dayungUnitId)
            .inFilter('status', ['paid', 'unpaid'])
            .order('paid_at', ascending: false)
            .timeout(_queryTimeout),
      );

      if (kDebugMode) {
        final deceasedPaymentRows = rawPaymentRows
            .where((row) => row['type'] == 'deceased_payment')
            .toList();
        final collectedRows = deceasedPaymentRows
            .where((row) => _isTruthyFlag(row['iscollectedbytreasurer']))
            .toList();
        final collectedRowsWithDate = collectedRows.where((row) {
          final date = row['iscollectedbytreasurer_date'];
          return date != null && date.toString().isNotEmpty;
        }).length;
        debugPrint(
          '[LedgerBalance] payments=${rawPaymentRows.length}, '
          'deceasedPayments=${deceasedPaymentRows.length}, '
          'treasurerCollected=${collectedRows.length}, '
          'collectedWithDate=$collectedRowsWithDate',
        );
      }

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

      final totalDeceasedPaymentAmount = calculateDeceasedPaymentLedgerBalance(
        rawPaymentRows,
      );

      final currentCashCollected = paymentRows.fold<double>(0.0, (sum, row) {
        final typeValue = row['type']?.toString().toLowerCase();
        final collectedBy = '${row['collected_by'] ?? ''}'.trim();

        if (typeValue != 'deceased_payment' || collectedBy != currentUserId) {
          return sum;
        }

        return sum + _asDouble(row['amount']);
      });

      final collectedPayments = filterCollectorsCollectedPayments(paymentRows);

      final collectedCollectedTotal = collectedPayments.fold<double>(
        0.0,
        (sum, row) => sum + _asDouble(row['amount']),
      );

      final memberNamesById = <String, String>{};
      final memberIds = paymentRows
          .expand(
            (row) => [
              '${row['userdeceased'] ?? ''}',
              '${row['user_id'] ?? ''}',
            ],
          )
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
        final noticeId = '${row['death_notice_id'] ?? ''}'.trim();
        final memberKey = noticeId.isNotEmpty
            ? 'notice:$noticeId'
            : memberId.isEmpty
            ? '__unknown__'
            : 'member:$memberId';
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
            'contributors': <String, Map<String, dynamic>>{},
            'is_received': isTreasurerCollected,
            'received_date': receivedDate,
          };
        }

        final memberEntry = memberTotals[memberKey] as Map<String, dynamic>;
        memberEntry['amount'] =
            _asDouble(memberEntry['amount']) + _asDouble(row['amount']);
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

        final contributorId = '${row['user_id'] ?? ''}'.trim();
        final contributorKey = contributorId.isNotEmpty
            ? contributorId
            : 'unknown:$paymentId';
        final contributors =
            memberEntry['contributors'] as Map<String, Map<String, dynamic>>;
        contributors.putIfAbsent(
          contributorKey,
          () => {
            'name': contributorId.isEmpty
                ? 'Unknown contributor'
                : memberNamesById[contributorId] ?? 'Unknown contributor',
            'amount': 0.0,
            'payment_count': 0,
            'collected_payment_count': 0,
            'received_at': null,
          },
        );
        final contributor = contributors[contributorKey]!;
        contributor['amount'] =
            _asDouble(contributor['amount']) + _asDouble(row['amount']);
        contributor['payment_count'] =
            (contributor['payment_count'] as int) + 1;
        final collectedAtValue = isTreasurerCollected
            ? row['iscollectedbytreasurer_date']
            : null;
        final collectedAt = collectedAtValue == null
            ? null
            : collectedAtValue is DateTime
            ? collectedAtValue
            : DateTime.tryParse(collectedAtValue.toString());
        final previousCollectedAt = contributor['received_at'] as DateTime?;
        if (collectedAt != null &&
            (previousCollectedAt == null ||
                collectedAt.isAfter(previousCollectedAt))) {
          contributor['received_at'] = collectedAt;
        }
        if (isTreasurerCollected) {
          contributor['collected_payment_count'] =
              (contributor['collected_payment_count'] as int) + 1;
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
                'contributors':
                    (memberEntry['contributors']
                            as Map<String, Map<String, dynamic>>)
                        .values
                        .toList(),
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
        _collectedCollectedTotal = collectedCollectedTotal;
        _hasCollectorsCollectedPayments = collectedPayments.isNotEmpty;
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
      final now = DateTime.now().toUtc().toIso8601String();
      final pendingPayments =
          List<Map<String, dynamic>>.from(
            await sb
                .from('payments')
                .select('id, user_id, amount, iscollectedbytreasurer')
                .inFilter('id', paymentIds)
                .timeout(_queryTimeout),
          ).where((payment) {
            return !_isTruthyFlag(payment['iscollectedbytreasurer']);
          }).toList();
      final pendingPaymentIds = pendingPayments
          .map((payment) => '${payment['id'] ?? ''}')
          .where((id) => id.isNotEmpty && id != 'null')
          .toList();
      var newlyReceivedPayments = <Map<String, dynamic>>[];

      if (pendingPaymentIds.isNotEmpty) {
        final updatedPayments = List<Map<String, dynamic>>.from(
          await sb
              .from('payments')
              .update({
                'iscollectedbytreasurer': true,
                'iscollectedbytreasurer_date': now,
              })
              .inFilter('id', pendingPaymentIds)
              .select('id')
              .timeout(_queryTimeout),
        );
        final updatedIds = updatedPayments
            .map((payment) => '${payment['id']}')
            .toSet();
        newlyReceivedPayments = pendingPayments
            .where((payment) => updatedIds.contains('${payment['id']}'))
            .toList();
      }

      String? notificationError;
      if (newlyReceivedPayments.isNotEmpty) {
        try {
          final treasurerId = sb.auth.currentUser?.id;
          if (treasurerId == null) {
            throw StateError(
              'The signed-in treasurer could not be identified.',
            );
          }

          final treasurer = await sb
              .from('users')
              .select('full_name')
              .eq('id', treasurerId)
              .maybeSingle()
              .timeout(_queryTimeout);
          final treasurerName = (treasurer?['full_name'] ?? '')
              .toString()
              .trim();
          final senderName = treasurerName.isEmpty
              ? 'Treasurer'
              : treasurerName;
          final amountsByContributor = <String, double>{};

          for (final payment in newlyReceivedPayments) {
            final contributorId = '${payment['user_id'] ?? ''}'.trim();
            if (contributorId.isEmpty || contributorId == 'null') {
              throw StateError(
                'A contributor could not be identified for a receipt notification.',
              );
            }
            amountsByContributor[contributorId] =
                (amountsByContributor[contributorId] ?? 0) +
                _asDouble(payment['amount']);
          }

          await sb
              .from('notifications')
              .insert(
                amountsByContributor.entries.map((entry) {
                  return {
                    'recipient_id': entry.key,
                    'sender_id': treasurerId,
                    'dayung_unit_id': widget.dayungUnitId,
                    'type': 'announcement',
                    'title': 'Collection Successfully Received',
                    'body':
                        '$senderName has received ${_formatCurrency(entry.value)} '
                        'from your collected contributions.',
                    'announcement_id': null,
                    'read_at': null,
                    'created_at': now,
                  };
                }).toList(),
              )
              .timeout(_queryTimeout);
        } catch (e) {
          notificationError = e.toString();
        }
      }

      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked $memberName as received.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      if (notificationError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Receipt marked, but notification could not be sent: $notificationError',
            ),
          ),
        );
      }

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
    final screenSize = MediaQuery.sizeOf(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: screenSize.width < 1050 ? screenSize.width - 32 : 1000,
              height: screenSize.height * 0.8,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            collector['name']?.toString() ?? 'Collector',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close details',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      '${members.length} member${members.length == 1 ? '' : 's'} · Current Collected: ${_formatCurrency(_asDouble(collector['amount']))}',
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: members.isEmpty
                          ? const Center(
                              child: Text('No member available yet.'),
                            )
                          : Scrollbar(
                              child: SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: 960,
                                    ),
                                    child: DataTable(
                                      showCheckboxColumn: false,
                                      headingRowColor: WidgetStateProperty.all(
                                        const Color(0xFFF9FAFB),
                                      ),
                                      columns: const [
                                        DataColumn(
                                          label: Text('Deceased Member'),
                                        ),
                                        DataColumn(label: Text('Contributors')),
                                        DataColumn(label: Text('Total')),
                                        DataColumn(label: Text('Members')),
                                        DataColumn(label: Text('Action')),
                                        DataColumn(label: Text('Status')),
                                        DataColumn(
                                          label: Text('Date Collected'),
                                        ),
                                      ],
                                      rows: members.map((member) {
                                        final contributors =
                                            List<Map<String, dynamic>>.from(
                                              member['contributors'] ?? [],
                                            );
                                        final contributorsToCollect =
                                            contributors.where((contributor) {
                                              final paymentCount =
                                                  contributor['payment_count']
                                                      as int? ??
                                                  0;
                                              final collectedPaymentCount =
                                                  contributor['collected_payment_count']
                                                      as int? ??
                                                  0;
                                              return collectedPaymentCount <
                                                  paymentCount;
                                            }).length;
                                        final isReceived =
                                            member['is_received'] == true;
                                        final isCollecting =
                                            member['is_collecting'] == true;
                                        final receivedDate =
                                            member['received_date']?.toString();

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              SizedBox(
                                                width: 160,
                                                child: Text(
                                                  member['name']?.toString() ??
                                                      'Member',
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text('${contributors.length}'),
                                            ),
                                            DataCell(
                                              Text(
                                                _formatCurrency(
                                                  _asDouble(member['amount']),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              TextButton(
                                                onPressed: () =>
                                                    _showContributorDetails(
                                                      member,
                                                    ),
                                                child: const Text(
                                                  'View Details',
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              FilledButton(
                                                onPressed:
                                                    isReceived ||
                                                        isCollecting ||
                                                        contributorsToCollect ==
                                                            0
                                                    ? null
                                                    : () async {
                                                        setDialogState(() {
                                                          member['is_collecting'] =
                                                              true;
                                                        });
                                                        await _confirmReceipt(
                                                          member,
                                                          onConfirmed: () {
                                                            member['is_received'] =
                                                                true;
                                                            member['received_date'] =
                                                                _normalizeReceivedDate(
                                                                  DateTime.now(),
                                                                );
                                                          },
                                                        );
                                                        setDialogState(() {
                                                          member.remove(
                                                            'is_collecting',
                                                          );
                                                        });
                                                      },
                                                child: Text(
                                                  isCollecting
                                                      ? 'Collecting...'
                                                      : isReceived
                                                      ? 'Collected'
                                                      : 'Collect $contributorsToCollect ${contributorsToCollect == 1 ? 'Member' : 'Members'}',
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                isReceived
                                                    ? 'Received'
                                                    : 'Pending',
                                                style: TextStyle(
                                                  color: isReceived
                                                      ? const Color(0xFF15803D)
                                                      : const Color(0xFFB45309),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                isReceived &&
                                                        receivedDate != null
                                                    ? receivedDate
                                                    : '—',
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showContributorDetails(Map<String, dynamic> member) {
    final contributors = List<Map<String, dynamic>>.from(
      member['contributors'] ?? [],
    );
    var searchQuery = '';

    if (kDebugMode) {
      debugPrint(
        '[LedgerBalance] Opening contributor table: '
        'rows=${contributors.length}, columns=4, '
        'viewportWidth=${MediaQuery.sizeOf(context).width}',
      );
      for (var index = 0; index < contributors.length; index++) {
        final contributor = contributors[index];
        final rawDate = contributor['received_at'];
        final displayedDate = _normalizeReceivedDate(rawDate) ?? '—';
        debugPrint(
          '[LedgerBalance] row[$index]: '
          'collectedPayments=${contributor['collected_payment_count']}, '
          'totalPayments=${contributor['payment_count']}, '
          'received_at=$rawDate, displayedDate=$displayedDate',
        );
      }
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredContributors = contributors.where((contributor) {
            final name =
                contributor['name']?.toString() ?? 'Unknown contributor';
            return name.toLowerCase().contains(
              searchQuery.trim().toLowerCase(),
            );
          }).toList();

          final screenWidth = MediaQuery.sizeOf(context).width;

          return AlertDialog(
            title: Text(member['name']?.toString() ?? 'Member details'),
            content: SizedBox(
              width: screenWidth < 760 ? screenWidth - 80 : 680,
              child: contributors.isEmpty
                  ? const Text('No contributor details are available.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search contributors',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (value) {
                            setDialogState(() => searchQuery = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                          ),
                          child: filteredContributors.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'No contributors match your search.',
                                  ),
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SingleChildScrollView(
                                    child: DataTable(
                                      headingRowHeight: 40,
                                      dataRowMinHeight: 44,
                                      dataRowMaxHeight: 52,
                                      columns: const [
                                        DataColumn(label: Text('Contributor')),
                                        DataColumn(label: Text('Status')),
                                        DataColumn(
                                          label: Text('Date Collected'),
                                        ),
                                        DataColumn(
                                          label: Text('Amount'),
                                          numeric: true,
                                        ),
                                      ],
                                      rows: filteredContributors.map((
                                        contributor,
                                      ) {
                                        final paymentCount =
                                            contributor['payment_count']
                                                as int? ??
                                            0;
                                        final collectedPaymentCount =
                                            contributor['collected_payment_count']
                                                as int? ??
                                            0;
                                        final isCollected =
                                            paymentCount > 0 &&
                                            collectedPaymentCount ==
                                                paymentCount;
                                        final hasCollectedPayments =
                                            collectedPaymentCount > 0;
                                        final receivedDate =
                                            _normalizeReceivedDate(
                                              contributor['received_at'],
                                            );
                                        final status = isCollected
                                            ? 'Collected'
                                            : hasCollectedPayments
                                            ? 'Partially collected'
                                            : 'Pending';
                                        final statusColor = isCollected
                                            ? const Color(0xFF15803D)
                                            : hasCollectedPayments
                                            ? const Color(0xFF1D4ED8)
                                            : const Color(0xFFB45309);

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Text(
                                                contributor['name']
                                                        ?.toString() ??
                                                    'Unknown contributor',
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                status,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            DataCell(Text(receivedDate ?? '—')),
                                            DataCell(
                                              Text(
                                                _formatCurrency(
                                                  _asDouble(
                                                    contributor['amount'],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
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

  Widget _collectorTableCell(
    String text, {
    bool isHeader = false,
    TextAlign align = TextAlign.left,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        textAlign: align,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isHeader ? const Color(0xFF6B7280) : const Color(0xFF111827),
          fontSize: isHeader ? 12 : 13,
          fontWeight: isHeader ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCollected = _treasurerCollectedTotal > _currentCashCollected
        ? _treasurerCollectedTotal - _currentCashCollected
        : 0.0;

    return Scaffold(
      backgroundColor: _kPageBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: _kHeaderGradientEnd,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF1E40AF),
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
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: IconButton(
                          tooltip: 'Back',
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
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
                ],
              ),
            ),
            Expanded(
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
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _kCard,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: _kBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _summaryCard(
                                      title: 'Number of Collectors',
                                      value: '${_collectorSummaries.length}',
                                      accent: const Color(0xFFF59E0B),
                                    ),
                                    if (_hasCollectorsCollectedPayments)
                                      _summaryCard(
                                        title: 'Collectors Collected',
                                        value: _formatCurrency(
                                          _collectedCollectedTotal,
                                        ),
                                        accent: const Color(0xFF10B981),
                                      ),
                                    _summaryCard(
                                      title: 'Total Collected',
                                      value: _formatCurrency(totalCollected),
                                      accent: const Color(0xFF10B981),
                                    ),
                                    _summaryCard(
                                      title: 'Current Cash Holdings',
                                      value: _formatCurrency(
                                        _currentCashCollected,
                                      ),
                                      accent: const Color(0xFF10B981),
                                    ),
                                    _summaryCard(
                                      title: 'Ledger Balance',
                                      value: _formatCurrency(
                                        _totalDeceasedPaymentAmount,
                                      ),
                                      accent: const Color(0xFF3B82F6),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
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
                            Container(
                              decoration: BoxDecoration(
                                color: _kCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _kBorder),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(1.5),
                                  1: FlexColumnWidth(1.35),
                                  2: FixedColumnWidth(56),
                                },
                                border: const TableBorder(
                                  horizontalInside: BorderSide(color: _kBorder),
                                ),
                                children: [
                                  TableRow(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF9FAFB),
                                    ),
                                    children: [
                                      _collectorTableCell(
                                        'Collector',
                                        isHeader: true,
                                      ),
                                      _collectorTableCell(
                                        'Total Collected',
                                        isHeader: true,
                                        align: TextAlign.right,
                                      ),
                                      _collectorTableCell(
                                        'Actions',
                                        isHeader: true,
                                        align: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  ..._collectorSummaries.map((collector) {
                                    return TableRow(
                                      children: [
                                        _collectorTableCell(
                                          collector['name']?.toString() ??
                                              'Collector',
                                        ),
                                        _collectorTableCell(
                                          _formatCurrency(
                                            _asDouble(collector['amount']),
                                          ),
                                          align: TextAlign.right,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: IconButton(
                                            tooltip: 'View collector details',
                                            onPressed: () =>
                                                _showCollectorDetailsDialog(
                                                  collector,
                                                ),
                                            icon: const Icon(
                                              Icons.visibility_outlined,
                                              size: 20,
                                            ),
                                            color: const Color(0xFF0D47A1),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
