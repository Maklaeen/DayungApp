import 'package:capstone_app/shared/treasurer_report_header.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _CollectionRecord {
  final String memberName;
  final String deceasedId;
  final String deceasedName;
  final double amount;
  final String date;
  final DateTime sortDate;
  final String paymentMethod;
  final String status;
  final String receivedBy;
  final double? claimAmount;

  const _CollectionRecord({
    required this.memberName,
    required this.deceasedId,
    required this.deceasedName,
    required this.amount,
    required this.date,
    required this.sortDate,
    required this.paymentMethod,
    required this.status,
    required this.receivedBy,
    this.claimAmount,
  });
}

class _AdvanceRecord {
  final String memberName;
  final double amount;
  final String date;
  final String paymentMethod;

  const _AdvanceRecord({
    required this.memberName,
    required this.amount,
    required this.date,
    required this.paymentMethod,
  });
}

class _UnpaidContributionRecord {
  final String memberName;
  final String deceasedName;
  final double amountDue;

  const _UnpaidContributionRecord({
    required this.memberName,
    required this.deceasedName,
    required this.amountDue,
  });
}

class CollectorOverallReportsPage extends StatefulWidget {
  final int dayungUnitId;

  const CollectorOverallReportsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectorOverallReportsPage> createState() =>
      _CollectorOverallReportsPageState();
}

class _CollectorOverallReportsPageState
    extends State<CollectorOverallReportsPage> {
  static const int _recordsPageSize = 20;

  List<_CollectionRecord> _collectionRecords = const [];
  List<_CollectionRecord> _memberCollectionRecords = const [];
  List<_AdvanceRecord> _advanceRecords = const [];
  List<_UnpaidContributionRecord> _unpaidContributions = const [];
  Map<String, String> _deceasedNames = const {};
  String? _selectedDeceasedId;
  int _collectionRecordsPage = 0;
  int _memberRecordsPage = 0;
  int _advanceRecordsPage = 0;
  int _unpaidContributionsPage = 0;
  String _collectionSearchQuery = '';
  String _memberSearchQuery = '';
  String _advanceSearchQuery = '';
  final Set<String> _selectedMethods = {};
  final Set<String> _selectedStatuses = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _loading = true;
      _error = null;
      _collectionRecordsPage = 0;
      _memberRecordsPage = 0;
      _advanceRecordsPage = 0;
      _unpaidContributionsPage = 0;
    });

    try {
      final client = Supabase.instance.client;
      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId == null) {
        throw StateError('No signed-in collector found.');
      }

      final collectorRows = List<Map<String, dynamic>>.from(
        await client
            .from('dayung_collectors')
            .select('collectors_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('user_id', currentUserId)
            .limit(1),
      );
      if (collectorRows.isEmpty) {
        throw StateError('This user is not assigned as a collector.');
      }

      final collectorId = (collectorRows.first['collectors_id'] ?? '')
          .toString();
      final applicationRows = List<Map<String, dynamic>>.from(
        await client
            .from('applications')
            .select('user_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('status', 'approved')
            .eq('assigned_collector', collectorId),
      );
      final memberIds = applicationRows
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (memberIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _collectionRecords = const [];
          _memberCollectionRecords = const [];
          _advanceRecords = const [];
          _unpaidContributions = const [];
          _deceasedNames = const {};
          _selectedDeceasedId = null;
          _loading = false;
        });
        return;
      }

      final paymentRows = List<Map<String, dynamic>>.from(
        await client
            .from('payments')
            .select(
              'user_id, userdeceased, deceased_name, amount, status, is_due, is_claimed, '
              'paid_at, created_at, collected_by',
            )
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('type', 'deceased_payment')
            .inFilter('user_id', memberIds)
            .order('created_at', ascending: false),
      );
      final gcashRows = List<Map<String, dynamic>>.from(
        await client
            .from('gcash_qr_codes')
            .select(
              'id, uploaded_by, userdeceased, amount, status, created_at, '
              'dayung_unit_id, payment_purpose, type, refno',
            )
            .eq('dayung_unit_id', widget.dayungUnitId)
            .inFilter('uploaded_by', memberIds)
            .order('created_at', ascending: false),
      );
      final advanceRows = List<Map<String, dynamic>>.from(
        await client
            .from('advance_payments')
            .select('user_id, amount, type, created_at')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .inFilter('user_id', memberIds)
            .order('created_at', ascending: false),
      );

      final unclaimedPaymentRows = paymentRows
          .where(
            (row) =>
                row['is_claimed'] == false &&
                (row['userdeceased'] ?? '').toString().isNotEmpty,
          )
          .toList();
      final unclaimedDeceasedIds = unclaimedPaymentRows
          .map((row) => row['userdeceased'].toString())
          .toSet()
          .toList();
      final claimRows = unclaimedDeceasedIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await client
                  .from('claims')
                  .select('user_id, amount')
                  .eq('dayung_unit_id', widget.dayungUnitId)
                  .inFilter('user_id', unclaimedDeceasedIds),
            );
      final claimAmountsByDeceased = <String, double>{};
      for (final row in claimRows) {
        final deceasedId = (row['user_id'] ?? '').toString();
        if (deceasedId.isEmpty) continue;
        claimAmountsByDeceased[deceasedId] =
            (claimAmountsByDeceased[deceasedId] ?? 0) +
            _toDouble(row['amount']);
      }

      final deceasedIds = <String>{
        for (final row in paymentRows)
          if ((row['userdeceased'] ?? '').toString().isNotEmpty)
            (row['userdeceased']).toString(),
        for (final row in gcashRows)
          if ((row['userdeceased'] ?? '').toString().isNotEmpty)
            (row['userdeceased']).toString(),
      };
      final userIds = <String>{
        ...memberIds,
        ...deceasedIds,
        for (final row in paymentRows)
          if ((row['collected_by'] ?? '').toString().isNotEmpty)
            (row['collected_by']).toString(),
        for (final row in gcashRows)
          for (final collectorId in [row['collected_by'], row['approved_by']])
            if ((collectorId ?? '').toString().isNotEmpty)
              collectorId.toString(),
      };
      final userRows = userIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await client
                  .from('users')
                  .select('id, full_name')
                  .inFilter('id', userIds.toList()),
            );
      final userNames = {
        for (final row in userRows)
          (row['id'] ?? '').toString(): (row['full_name'] ?? '').toString(),
      };

      final unpaidContributionsByPair = <String, _UnpaidContributionRecord>{};
      for (final row in paymentRows) {
        final status = (row['status'] ?? '').toString().toLowerCase();
        final memberId = (row['user_id'] ?? '').toString();
        final deceasedId = (row['userdeceased'] ?? '').toString();
        if ((status != 'pending' && status != 'unpaid') ||
            !_isTrueFlag(row['is_due']) ||
            memberId.isEmpty ||
            deceasedId.isEmpty) {
          continue;
        }

        final deceasedName = (row['deceased_name'] ?? '').toString().trim();
        final pairKey = '$memberId|$deceasedId';
        final previous = unpaidContributionsByPair[pairKey];
        unpaidContributionsByPair[pairKey] = _UnpaidContributionRecord(
          memberName: userNames[memberId]?.trim().isNotEmpty == true
              ? userNames[memberId]!.trim()
              : 'Member',
          deceasedName: deceasedName.isNotEmpty
              ? deceasedName
              : userNames[deceasedId]?.trim().isNotEmpty == true
              ? userNames[deceasedId]!.trim()
              : 'Deceased member',
          amountDue: (previous?.amountDue ?? 0) + _toDouble(row['amount']),
        );
      }

      final memberCollectionRecords = <_CollectionRecord>[
        for (final row in unclaimedPaymentRows)
          if (claimAmountsByDeceased.containsKey(
            (row['userdeceased'] ?? '').toString(),
          ))
            _recordFromPayment(
              row,
              userNames: userNames,
              method: 'Cash',
              defaultStatus: 'unpaid',
              claimAmount:
                  claimAmountsByDeceased[(row['userdeceased'] ?? '')
                      .toString()],
            ),
      ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));

      final collectionRecords = <_CollectionRecord>[
        for (final row in paymentRows)
          _recordFromPayment(
            row,
            userNames: userNames,
            method: 'Cash',
            defaultStatus: 'unpaid',
          ),
        for (final row in gcashRows)
          if ((row['userdeceased'] ?? '').toString().isNotEmpty)
            _recordFromPayment(
              row,
              userNames: userNames,
              method: 'GCash',
              defaultStatus: 'paid',
              memberId: (row['user_id'] ?? row['uploaded_by'] ?? '').toString(),
            ),
      ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));

      final deceasedNames = <String, String>{};
      for (final row in [...paymentRows, ...gcashRows]) {
        final id = (row['userdeceased'] ?? '').toString();
        final name = (row['deceased_name'] ?? '').toString().trim();
        if (id.isNotEmpty && name.isNotEmpty) deceasedNames[id] = name;
      }
      for (final id in deceasedIds) {
        deceasedNames.putIfAbsent(
          id,
          () => userNames[id]?.trim().isNotEmpty == true
              ? userNames[id]!.trim()
              : 'Deceased member',
        );
      }

      final advances = advanceRows.map((row) {
        final type = (row['type'] ?? '').toString().trim().toLowerCase();
        return _AdvanceRecord(
          memberName: userNames[(row['user_id'] ?? '').toString()] ?? 'Member',
          amount: _toDouble(row['amount']),
          date: _formatDate(row['created_at']),
          paymentMethod: type.isEmpty
              ? '—'
              : type == 'gcash'
              ? 'GCash'
              : type[0].toUpperCase() + type.substring(1),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _collectionRecords = collectionRecords;
        _memberCollectionRecords = memberCollectionRecords;
        _advanceRecords = advances;
        _unpaidContributions = unpaidContributionsByPair.values.toList()
          ..sort(
            (a, b) => a.memberName.toLowerCase().compareTo(
              b.memberName.toLowerCase(),
            ),
          );
        _deceasedNames = deceasedNames;
        if (_selectedDeceasedId != null &&
            !deceasedNames.containsKey(_selectedDeceasedId)) {
          _selectedDeceasedId = null;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load collection records: $error';
      });
    }
  }

  _CollectionRecord _recordFromPayment(
    Map<String, dynamic> row, {
    required Map<String, String> userNames,
    required String method,
    required String defaultStatus,
    String? memberId,
    double? claimAmount,
  }) {
    final actualMemberId =
        memberId ?? (row['user_id'] ?? row['uploaded_by'] ?? '').toString();
    final deceasedId = (row['userdeceased'] ?? '').toString();
    final deceasedName = (row['deceased_name'] ?? '').toString().trim();
    final status = (row['status'] ?? defaultStatus).toString().toLowerCase();
    final collectorId = (row['collected_by'] ?? '').toString();
    return _CollectionRecord(
      memberName: userNames[actualMemberId] ?? 'Member',
      deceasedId: deceasedId,
      deceasedName: deceasedName.isNotEmpty
          ? deceasedName
          : userNames[deceasedId]?.trim().isNotEmpty == true
          ? userNames[deceasedId]!.trim()
          : 'Deceased member',
      amount: _toDouble(row['amount']),
      date: _formatDate(row['paid_at'] ?? row['created_at']),
      sortDate:
          DateTime.tryParse(
            (row['paid_at'] ?? row['created_at'] ?? '').toString(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      paymentMethod: method,
      status: status == 'paid' ? 'Paid' : 'Unpaid',
      claimAmount: claimAmount,
      receivedBy: userNames[collectorId]?.trim().isNotEmpty == true
          ? userNames[collectorId]!.trim()
          : '—',
    );
  }

  List<_CollectionRecord> get _filteredMemberRecords {
    final query = _memberSearchQuery.trim().toLowerCase();
    return _memberCollectionRecords.where((record) {
      if (_selectedDeceasedId != null &&
          record.deceasedId != _selectedDeceasedId) {
        return false;
      }
      if (_selectedMethods.isNotEmpty &&
          !_selectedMethods.contains(record.paymentMethod)) {
        return false;
      }
      if (_selectedStatuses.isNotEmpty &&
          !_selectedStatuses.contains(record.status)) {
        return false;
      }
      if (query.isNotEmpty &&
          !record.memberName.toLowerCase().contains(query) &&
          !record.deceasedName.toLowerCase().contains(query) &&
          !_formatMemberAmount(record).toLowerCase().contains(query) &&
          !record.date.toLowerCase().contains(query) &&
          !record.paymentMethod.toLowerCase().contains(query) &&
          !record.status.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<_CollectionRecord> get _filteredCollectionRecords {
    final query = _collectionSearchQuery.trim().toLowerCase();
    return _collectionRecords.where((record) {
      if (_selectedDeceasedId != null &&
          record.deceasedId != _selectedDeceasedId) {
        return false;
      }
      if (query.isEmpty) return true;
      return record.deceasedName.toLowerCase().contains(query) ||
          _formatAmount(record.amount).toLowerCase().contains(query) ||
          record.receivedBy.toLowerCase().contains(query) ||
          record.date.toLowerCase().contains(query);
    }).toList();
  }

  List<_AdvanceRecord> get _filteredAdvanceRecords {
    final query = _advanceSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _advanceRecords;

    return _advanceRecords.where((record) {
      return record.memberName.toLowerCase().contains(query) ||
          _formatAmount(record.amount).toLowerCase().contains(query) ||
          record.date.toLowerCase().contains(query) ||
          record.paymentMethod.toLowerCase().contains(query);
    }).toList();
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static bool _isTrueFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  static String _formatDate(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString());
    if (date == null) return '—';
    return DateFormat('MMM d, yyyy • h:mm a').format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            TreasurerReportHeader(
              title: 'Collector Overall Reports',
              onRefresh: _loadRecords,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                      children: [
                        _sectionTitle('Unpaid Contributions'),
                        const SizedBox(height: 4),
                        const Text(
                          "Members who haven't paid for previous deceased members.",
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontFamily: 'OpenSans',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _paginatedRecordsTable(
                          columns: const [
                            'Member',
                            'Deceased Member',
                            'Amount Due',
                          ],
                          rows: _unpaidContributions
                              .map(
                                (record) => [
                                  record.memberName,
                                  record.deceasedName,
                                  _formatAmount(record.amountDue),
                                ],
                              )
                              .toList(),
                          emptyMessage: 'No unpaid contributions found.',
                          pageIndex: _unpaidContributionsPage,
                          onPageChanged: (page) =>
                              setState(() => _unpaidContributionsPage = page),
                        ),
                        const SizedBox(height: 26),
                        _sectionTitle('Collector Collection Records'),
                        const SizedBox(height: 12),
                        _deceasedSelector(),
                        const SizedBox(height: 10),
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Search collection records',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                          ),
                          onChanged: (value) => setState(() {
                            _collectionSearchQuery = value;
                            _collectionRecordsPage = 0;
                          }),
                        ),
                        const SizedBox(height: 10),
                        _collectionRecordsTable(),
                        const SizedBox(height: 26),
                        _sectionTitle('Individual Member Collection Records'),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Search member collection records',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                          ),
                          onChanged: (value) => setState(() {
                            _memberSearchQuery = value;
                            _memberRecordsPage = 0;
                          }),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _filterChip(
                              label: 'Cash',
                              selected: _selectedMethods.contains('Cash'),
                              onSelected: (selected) => _toggleFilter(
                                _selectedMethods,
                                'Cash',
                                selected,
                              ),
                            ),
                            _filterChip(
                              label: 'GCash',
                              selected: _selectedMethods.contains('GCash'),
                              onSelected: (selected) => _toggleFilter(
                                _selectedMethods,
                                'GCash',
                                selected,
                              ),
                            ),
                            _filterChip(
                              label: 'Paid',
                              selected: _selectedStatuses.contains('Paid'),
                              onSelected: (selected) => _toggleFilter(
                                _selectedStatuses,
                                'Paid',
                                selected,
                              ),
                            ),
                            _filterChip(
                              label: 'Unpaid',
                              selected: _selectedStatuses.contains('Unpaid'),
                              onSelected: (selected) => _toggleFilter(
                                _selectedStatuses,
                                'Unpaid',
                                selected,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _paginatedRecordsTable(
                          columns: const [
                            'Member',
                            'Deceased Member',
                            'Amount',
                            'Date',
                            'Payment Method',
                            'Status',
                          ],
                          rows: _filteredMemberRecords
                              .map(
                                (record) => [
                                  record.memberName,
                                  record.deceasedName,
                                  _formatMemberAmount(record),
                                  record.date,
                                  record.paymentMethod,
                                  record.status,
                                ],
                              )
                              .toList(),
                          emptyMessage: 'No member collection records found.',
                          pageIndex: _memberRecordsPage,
                          onPageChanged: (page) =>
                              setState(() => _memberRecordsPage = page),
                        ),
                        const SizedBox(height: 26),
                        _sectionTitle('Advance Payment'),
                        const SizedBox(height: 10),
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Search advance payments',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                          ),
                          onChanged: (value) => setState(() {
                            _advanceSearchQuery = value;
                            _advanceRecordsPage = 0;
                          }),
                        ),
                        const SizedBox(height: 10),
                        _paginatedRecordsTable(
                          columns: const [
                            'Member',
                            'Amount',
                            'Date',
                            'Payment Method',
                            'Status',
                          ],
                          rows: _filteredAdvanceRecords
                              .map(
                                (record) => [
                                  record.memberName,
                                  _formatAmount(record.amount),
                                  record.date,
                                  record.paymentMethod,
                                  'Paid',
                                ],
                              )
                              .toList(),
                          emptyMessage: 'No advance payment records found.',
                          pageIndex: _advanceRecordsPage,
                          onPageChanged: (page) =>
                              setState(() => _advanceRecordsPage = page),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deceasedSelector() {
    final deceasedIds = _deceasedNames.keys.toList()
      ..sort(
        (a, b) => _deceasedNames[a]!.toLowerCase().compareTo(
          _deceasedNames[b]!.toLowerCase(),
        ),
      );
    return DropdownButtonFormField<String>(
      initialValue: _selectedDeceasedId ?? '',
      decoration: InputDecoration(
        labelText: 'Deceased Member',
        prefixIcon: const Icon(Icons.person_search_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('All deceased members')),
        for (final id in deceasedIds)
          DropdownMenuItem(value: id, child: Text(_deceasedNames[id]!)),
      ],
      onChanged: (value) => setState(() {
        _selectedDeceasedId = value == null || value.isEmpty ? null : value;
        _collectionRecordsPage = 0;
        _memberRecordsPage = 0;
      }),
    );
  }

  Widget _collectionRecordsTable() {
    final records = _filteredCollectionRecords;
    return _paginatedRecordsTable(
      columns: const ['Deceased Member', 'Amount', 'Receive By', 'Date'],
      rows: records
          .map(
            (record) => [
              record.deceasedName,
              _formatAmount(record.amount),
              record.receivedBy,
              record.date,
            ],
          )
          .toList(),
      emptyMessage: 'No collection records found.',
      pageIndex: _collectionRecordsPage,
      onPageChanged: (page) => setState(() => _collectionRecordsPage = page),
    );
  }

  Widget _paginatedRecordsTable({
    required List<String> columns,
    required List<List<String>> rows,
    required String emptyMessage,
    required int pageIndex,
    required ValueChanged<int> onPageChanged,
  }) {
    final pageCount = (rows.length / _recordsPageSize).ceil();
    final currentPage = pageCount == 0
        ? 0
        : pageIndex < pageCount
        ? pageIndex
        : pageCount - 1;
    final startIndex = currentPage * _recordsPageSize;
    final visibleRows = rows.skip(startIndex).take(_recordsPageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _recordsTable(
          columns: columns,
          rows: visibleRows,
          emptyMessage: emptyMessage,
        ),
        if (rows.length > _recordsPageSize)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Showing ${startIndex + 1}–${startIndex + visibleRows.length} of ${rows.length}',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontFamily: 'OpenSans',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: currentPage > 0
                      ? () => onPageChanged(currentPage - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                TextButton(
                  onPressed: currentPage + 1 < pageCount
                      ? () => onPageChanged(currentPage + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: const Color(0xFFDCEBFA),
      checkmarkColor: const Color(0xFF0D47A1),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF0D47A1) : const Color(0xFF374151),
        fontWeight: FontWeight.w700,
      ),
      side: const BorderSide(color: Color(0xFFD1D5DB)),
    );
  }

  void _toggleFilter(Set<String> filters, String value, bool selected) {
    setState(() {
      if (selected) {
        filters.add(value);
      } else {
        filters.remove(value);
      }
      _memberRecordsPage = 0;
    });
  }

  Widget _recordsTable({
    required List<String> columns,
    required List<List<String>> rows,
    required String emptyMessage,
  }) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _tableDecoration(),
        child: Text(
          emptyMessage,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontFamily: 'OpenSans',
          ),
        ),
      );
    }

    return RecordDataTable(
      minWidth: 680,
      showCheckboxColumn: false,
      headingRowColor: const Color(0xFFEAF1F8),
      dataRowMinHeight: 48,
      dataRowMaxHeight: 64,
      columnSpacing: 22,
      columns: [
        for (final column in columns)
          DataColumn(
            label: Text(
              column,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              for (final value in row)
                DataCell(
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontFamily: 'OpenSans',
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  BoxDecoration _tableDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF111827),
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w800,
        fontSize: 20,
      ),
    );
  }

  static String _formatAmount(double amount) =>
      'PHP ${amount.toStringAsFixed(2)}';

  static String _formatMemberAmount(_CollectionRecord record) {
    final paymentAmount = _formatAmount(record.amount);
    final claimAmount = record.claimAmount;
    return claimAmount == null
        ? paymentAmount
        : '$paymentAmount / ${_formatAmount(claimAmount)}';
  }
}
