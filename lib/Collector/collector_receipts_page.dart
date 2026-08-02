import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:photo_view/photo_view.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kReceiptsBg = Color(0xFFFAFAF7);
const kReceiptsText = Color(0xFF1F2937);
const kReceiptsSubText = Color(0xFF4B5563);
const kReceiptsAccent = Color(0xFF0D47A1);
const kReceiptsAccentDark = Color(0xFF083366);
const kReceiptsBorder = Color(0xFFE5E7EB);
const kReceiptsSurface = Color(0xFFF8FAFC);
const kReceiptsSuccess = Color(0xFF10B981);
const kReceiptsWarn = Color(0xFFF59E0B);

class CollectorReceiptsPage extends StatefulWidget {
  final int? dayungUnitId;

  const CollectorReceiptsPage({super.key, this.dayungUnitId});

  @override
  State<CollectorReceiptsPage> createState() => _CollectorReceiptsPageState();
}

class _CollectorReceiptsPageState extends State<CollectorReceiptsPage> {
  static const Duration _queryTimeout = Duration(seconds: 12);

  final SupabaseClient _sb = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String _sourceFilter = 'all';
  bool _usingGcashFallback = false;
  List<Map<String, dynamic>> _receipts = [];
  pw.ThemeData? _pdfTheme;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadReceipts();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text.trim();
    if (_searchQuery == nextQuery) return;
    setState(() {
      _searchQuery = nextQuery;
    });
  }

  Future<void> _loadReceipts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final gcashResult = await _loadGcashReceipts();
      final gcashRows = gcashResult.rows;
      final gcashKeys = gcashRows.map(_receiptKey).toSet();
      final cashRows = await _loadCashReceipts(gcashKeys: gcashKeys);
      final combined = [...gcashRows, ...cashRows]
        ..sort(
          (a, b) =>
              _parseDate(b['sort_date']).compareTo(_parseDate(a['sort_date'])),
        );

      if (!mounted) return;
      setState(() {
        _receipts = combined;
        _usingGcashFallback = gcashResult.usedFallback;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load receipts: $error';
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadCashReceipts({
    required Set<String> gcashKeys,
  }) async {
    dynamic query = _sb
        .from('payments')
        .select(
          'id, user_id, amount, status, paid_at, created_at, collected_by, '
          ' userdeceased, dayung_unit_id, '
          'users!payments_user_id_fkey(full_name), '
          'collector:users!payments_collected_by_fkey(full_name)',
        )
        .eq('status', 'paid');

    if (widget.dayungUnitId != null) {
      query = query.eq('dayung_unit_id', widget.dayungUnitId as Object);
    }

    final rows = List<Map<String, dynamic>>.from(
      await query.order('paid_at', ascending: false).timeout(_queryTimeout),
    );

    return rows
        .map((row) {
          final dateValue = (row['paid_at'] ?? row['created_at'] ?? '')
              .toString();
          return {
            'id': 'cash-${row['id']}',
            'receipt_id': row['id']?.toString() ?? 'N/A',
            'source': 'cash',
            'source_label': 'Cash',
            'member_id': (row['user_id'] ?? '').toString(),
            'member_name':
                (row['users'] as Map?)?['full_name']?.toString() ??
                'Unknown member',
            'collector_name':
                (row['collector'] as Map?)?['full_name']?.toString() ??
                'Collector not set',
            'amount': row['amount'],
            'status': (row['status'] ?? 'paid').toString(),
            'reference': '',
            'proof_image_url': '',
            'deceased_id': (row['userdeceased'] ?? '').toString(),

            'sort_date': dateValue,
            'display_date': dateValue,
            'supporting_text': 'Recorded as a completed cash payment.',
          };
        })
        .where((row) => !gcashKeys.contains(_receiptKey(row)))
        .toList();
  }

  Future<_GcashLoadResult> _loadGcashReceipts() async {
    try {
      dynamic query = _sb.from('gcash_payments').select('*');
      if (widget.dayungUnitId != null) {
        query = query.eq('dayung_unit_id', widget.dayungUnitId as Object);
      }

      final rows = List<Map<String, dynamic>>.from(
        await query
            .order('created_at', ascending: false)
            .timeout(_queryTimeout),
      );
      final mapped = await _mapGcashPaymentsRows(rows);
      return _GcashLoadResult(rows: mapped, usedFallback: false);
    } catch (_) {
      final rows = await _loadGcashFallbackReceipts();
      return _GcashLoadResult(rows: rows, usedFallback: true);
    }
  }

  Future<List<Map<String, dynamic>>> _mapGcashPaymentsRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final userIds = <String>{};
    final collectorIds = <String>{};
    for (final row in rows) {
      for (final candidate in [row['user_id'], row['uploaded_by']]) {
        final value = (candidate ?? '').toString();
        if (value.isNotEmpty) userIds.add(value);
      }
      for (final candidate in [row['collected_by'], row['approved_by']]) {
        final value = (candidate ?? '').toString();
        if (value.isNotEmpty) collectorIds.add(value);
      }
    }

    final userMap = await _userNameMap({...userIds, ...collectorIds});

    return rows.map((row) {
      final memberId = (row['user_id'] ?? row['uploaded_by'] ?? '').toString();
      final collectorId = (row['collected_by'] ?? row['approved_by'] ?? '')
          .toString();
      final dateValue = (row['paid_at'] ?? row['created_at'] ?? '').toString();
      final status = (row['status'] ?? 'paid').toString();
      final refValue = (row['reference_no'] ?? row['refno'] ?? '').toString();
      final proofImageUrl =
          (row['image_url'] ?? row['proof_image_url'] ?? row['proof_url'] ?? '')
              .toString();
      return {
        'id':
            'gcash-${row['id'] ?? row['reference_no'] ?? row['refno'] ?? memberId}',
        'receipt_id': row['id']?.toString() ?? refValue,
        'source': 'gcash',
        'source_label': 'GCash',
        'member_id': memberId,
        'member_name': userMap[memberId] ?? 'Unknown member',
        'collector_name': collectorId.isEmpty
            ? 'Collector not set'
            : (userMap[collectorId] ?? 'Collector not set'),
        'amount': row['amount'],
        'status': status,
        'reference': refValue,
        'proof_image_url': proofImageUrl,
        'deceased_id': (row['userdeceased'] ?? '').toString(),

        'sort_date': dateValue,
        'display_date': dateValue,
        'supporting_text': status.toLowerCase() == 'paid'
            ? 'Approved GCash payment.'
            : 'GCash submission receipt.',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadGcashFallbackReceipts() async {
    dynamic query = _sb
        .from('gcash_qr_codes')
        .select(
          'id, image_url, uploaded_by, created_at, userdeceased, dayung_unit_id, '
          'amount, refno',
        );
    if (widget.dayungUnitId != null) {
      query = query.eq('dayung_unit_id', widget.dayungUnitId as Object);
    }

    final rows = List<Map<String, dynamic>>.from(
      await query.order('created_at', ascending: false).timeout(_queryTimeout),
    );

    final userIds = <String>{};
    final noticeIds = <String>{};
    final deceasedIds = <String>{};
    for (final row in rows) {
      final uploadedBy = (row['uploaded_by'] ?? '').toString();
      final deceasedId = (row['userdeceased'] ?? '').toString();

      if (uploadedBy.isNotEmpty) userIds.add(uploadedBy);
      if (deceasedId.isNotEmpty) userIds.add(deceasedId);

      if (deceasedId.isNotEmpty) deceasedIds.add(deceasedId);
    }

    final userMap = await _userNameMap(userIds);
    final paidKeys = await _paidGcashKeys(
      noticeIds: noticeIds,
      deceasedIds: deceasedIds,
    );

    return rows.map((row) {
      final uploadedBy = (row['uploaded_by'] ?? '').toString();
      final key = _receiptKey({
        'member_id': uploadedBy,
        'deceased_id': (row['userdeceased'] ?? '').toString(),

        'amount': row['amount'],
      });
      final isPaid = paidKeys.contains(key);
      final dateValue = (row['created_at'] ?? '').toString();
      return {
        'id': 'gcash-proof-${row['id'] ?? row['refno'] ?? uploadedBy}',
        'receipt_id':
            row['id']?.toString() ?? (row['refno'] ?? 'N/A').toString(),
        'source': 'gcash',
        'source_label': 'GCash',
        'member_id': uploadedBy,
        'member_name': userMap[uploadedBy] ?? 'Unknown member',
        'collector_name': isPaid
            ? 'Approved through collector review'
            : 'Awaiting review',
        'amount': row['amount'],

        'reference': (row['refno'] ?? '').toString(),
        'proof_image_url': (row['image_url'] ?? '').toString(),
        'deceased_id': (row['userdeceased'] ?? '').toString(),

        'sort_date': dateValue,
        'display_date': dateValue,
        'supporting_text': isPaid
            ? 'Proof submitted through GCash and already posted to payments.'
            : 'GCash proof submitted and waiting for approval.',
      };
    }).toList();
  }

  Future<Set<String>> _paidGcashKeys({
    required Set<String> noticeIds,
    required Set<String> deceasedIds,
  }) async {
    final keys = <String>{};

    if (noticeIds.isNotEmpty) {
      dynamic noticeQuery = _sb
          .from('payments')
          .select('user_id, userdeceased, amount')
          .eq('status', 'paid')
          .inFilter('userdeceased', noticeIds.toList());
      if (widget.dayungUnitId != null) {
        noticeQuery = noticeQuery.eq(
          'dayung_unit_id',
          widget.dayungUnitId as Object,
        );
      }
      final noticePayments = List<Map<String, dynamic>>.from(
        await noticeQuery.timeout(_queryTimeout),
      );
      for (final payment in noticePayments) {
        keys.add(
          _receiptKey({
            'member_id': (payment['user_id'] ?? '').toString(),
            'deceased_id': (payment['userdeceased'] ?? '').toString(),

            'amount': payment['amount'],
          }),
        );
      }
    }

    if (deceasedIds.isNotEmpty) {
      dynamic deceasedQuery = _sb
          .from('payments')
          .select('user_id, userdeceased, amount')
          .eq('status', 'paid')
          .isFilter('user_id', null)
          .inFilter('userdeceased', deceasedIds.toList());
      if (widget.dayungUnitId != null) {
        deceasedQuery = deceasedQuery.eq(
          'dayung_unit_id',
          widget.dayungUnitId as Object,
        );
      }
      final deceasedPayments = List<Map<String, dynamic>>.from(
        await deceasedQuery.timeout(_queryTimeout),
      );
      for (final payment in deceasedPayments) {
        keys.add(
          _receiptKey({
            'member_id': (payment['user_id'] ?? '').toString(),
            'deceased_id': (payment['userdeceased'] ?? '').toString(),

            'amount': payment['amount'],
          }),
        );
      }
    }

    return keys;
  }

  Future<Map<String, String>> _userNameMap(Set<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows = List<Map<String, dynamic>>.from(
      await _sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', userIds.toList())
          .timeout(_queryTimeout),
    );
    return {
      for (final row in rows)
        (row['id'] ?? '').toString(): (row['full_name'] ?? 'Member').toString(),
    };
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _receiptKey(Map<String, dynamic> row) {
    final amount = _formatAmountNumber(row['amount']);
    return [
      (row['member_id'] ?? '').toString(),
      (row['deceased_id'] ?? '').toString(),

      amount,
    ].join('|');
  }

  String _formatAmountNumber(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse('${value ?? ''}') ?? 0.0;
    return amount.toStringAsFixed(2);
  }

  String _formatAmount(dynamic value) => 'PHP ${_formatAmountNumber(value)}';

  String _formatDate(dynamic value) {
    final parsed = _parseDate(value).toLocal();
    if (parsed.year == 1970) return 'Not available';
    final month = <String>[
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
    ][parsed.month - 1];
    final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final minute = parsed.minute.toString().padLeft(2, '0');
    final suffix = parsed.hour >= 12 ? 'PM' : 'AM';
    return '$month ${parsed.day}, ${parsed.year} - $hour:$minute $suffix';
  }

  Future<pw.ThemeData> _getPdfTheme() async {
    if (_pdfTheme != null) return _pdfTheme!;

    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/OpenSans-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/OpenSans-Bold.ttf'),
    );
    _pdfTheme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);
    return _pdfTheme!;
  }

  List<Map<String, dynamic>> get _visibleReceipts {
    final query = _searchQuery.toLowerCase();
    return _receipts.where((receipt) {
      final source = (receipt['source'] ?? '').toString().toLowerCase();
      final matchesSource = _sourceFilter == 'all' || source == _sourceFilter;
      if (!matchesSource) return false;
      if (query.isEmpty) return true;

      final memberName = (receipt['member_name'] ?? '')
          .toString()
          .toLowerCase();
      final collectorName = (receipt['collector_name'] ?? '')
          .toString()
          .toLowerCase();
      final reference = (receipt['reference'] ?? '').toString().toLowerCase();
      final amount = _formatAmount(receipt['amount']).toLowerCase();
      return memberName.contains(query) ||
          collectorName.contains(query) ||
          reference.contains(query) ||
          amount.contains(query);
    }).toList();
  }

  int _countBySource(String source) {
    return _receipts.where((row) => (row['source'] ?? '') == source).length;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 860;

    return Scaffold(
      backgroundColor: kReceiptsBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(wide),
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
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: kReceiptsAccent,
                          ),
                        )
                      : _error != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          color: kReceiptsAccent,
                          onRefresh: _loadReceipts,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            children: [
                              _buildOverviewCard(),
                              const SizedBox(height: 18),
                              _buildFilterCard(),
                              const SizedBox(height: 18),
                              if (_visibleReceipts.isEmpty)
                                _buildEmptyState()
                              else
                                ..._visibleReceipts.map(_buildReceiptCard),
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

  Widget _buildHeader(bool wide) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        wide ? 36 : 28,
        wide ? 24 : 16,
        wide ? 32 : 24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF083366), Color(0xFF0D47A1)],
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              children: [
                Text(
                  'Receipts',
                  style: TextStyle(
                    fontSize: wide ? 24 : 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                // Text(
                //   'Review completed cash receipts and GCash submissions in one collector-facing history view.',
                //   style: TextStyle(
                //     fontSize: wide ? 14 : 13,
                //     height: 1.35,
                //     fontWeight: FontWeight.w600,
                //     color: Colors.white70,
                //     fontFamily: 'OpenSans',
                //   ),
                // ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _headerPill(
                      icon: Icons.receipt_long_rounded,
                      label: '${_receipts.length} total receipts',
                    ),
                    _headerPill(
                      icon: Icons.account_tree_rounded,
                      label: widget.dayungUnitId == null
                          ? 'All units'
                          : 'Dayung ${widget.dayungUnitId}',
                    ),
                    if (_usingGcashFallback)
                      _headerPill(
                        icon: Icons.sync_problem_rounded,
                        label: 'GCash via active proof table',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    final cards = [
      _statCard(
        icon: Icons.receipt_rounded,
        label: 'All Receipts',
        value: '${_receipts.length}',
        tone: const Color(0xFF1E40AF),
      ),
      _statCard(
        icon: Icons.payments_rounded,
        label: 'Cash',
        value: '${_countBySource('cash')}',
        tone: kReceiptsSuccess,
      ),
      _statCard(
        icon: Icons.phone_iphone_rounded,
        label: 'GCash',
        value: '${_countBySource('gcash')}',
        tone: kReceiptsWarn,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kReceiptsBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Receipt Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kReceiptsText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _usingGcashFallback
                ? 'GCash receipts are currently sourced from the active proof uploads table because gcash_payments was not available.'
                : 'Cash and GCash receipts are merged here so collectors can review both payment channels without switching screens.',
            style: const TextStyle(
              fontSize: 13,
              color: kReceiptsSubText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Row(
                  children: [
                    for (int index = 0; index < cards.length; index++) ...[
                      Expanded(child: cards[index]),
                      if (index != cards.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (int index = 0; index < cards.length; index++) ...[
                    cards[index],
                    if (index != cards.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kReceiptsSubText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kReceiptsText,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kReceiptsBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search and Filter',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kReceiptsText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Search by member, collector, reference number, or amount, then narrow the receipt list by payment source.',
            style: TextStyle(
              fontSize: 13,
              color: kReceiptsSubText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by member, collector, reference, or amount',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: kReceiptsSurface,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kReceiptsBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kReceiptsBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kReceiptsAccent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip('All', 'all'),
              _filterChip('Cash', 'cash'),
              _filterChip('GCash', 'gcash'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String key) {
    final selected = _sourceFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _sourceFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kReceiptsAccent : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? kReceiptsAccent
                : kReceiptsAccent.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : kReceiptsAccentDark,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard(Map<String, dynamic> receipt) {
    final source = (receipt['source'] ?? 'cash').toString().toLowerCase();
    final sourceTone = source == 'gcash' ? kReceiptsWarn : kReceiptsSuccess;

    final hasProofImage = (receipt['proof_image_url'] ?? '')
        .toString()
        .isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: sourceTone.withValues(alpha: 0.16)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showReceiptDetails(receipt),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: sourceTone.withValues(alpha: 0.12),
                    child: Icon(
                      source == 'gcash'
                          ? Icons.phone_iphone_rounded
                          : Icons.payments_rounded,
                      color: sourceTone,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (receipt['member_name'] ?? 'Member').toString(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kReceiptsText,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatAmount(receipt['amount']),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: sourceTone,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _statusChip(
                        receipt['source_label'].toString(),
                        sourceTone,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _detailChip(
                    icon: Icons.person_outline_rounded,
                    label:
                        'Collector: ${(receipt['collector_name'] ?? 'Not assigned').toString()}',
                    color: const Color(0xFF1E40AF),
                    background: const Color(0xFFEFF6FF),
                  ),
                  _detailChip(
                    icon: Icons.schedule_rounded,
                    label: _formatDate(receipt['display_date']),
                    color: sourceTone,
                    background: source == 'gcash'
                        ? const Color(0xFFFFFBEB)
                        : const Color(0xFFECFDF5),
                  ),
                  if ((receipt['reference'] ?? '').toString().isNotEmpty)
                    _detailChip(
                      icon: Icons.tag_rounded,
                      label: 'Ref: ${receipt['reference']}',
                      color: kReceiptsAccentDark,
                      background: const Color(0xFFEEF2FF),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                (receipt['supporting_text'] ?? '').toString(),
                style: const TextStyle(
                  fontSize: 13,
                  color: kReceiptsSubText,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                ),
              ),
              if (hasProofImage) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _showProofPreview(receipt),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Preview GCash proof'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          fontFamily: 'Montserrat',
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'approved':
        return kReceiptsSuccess;
      case 'submitted':
      case 'pending':
        return kReceiptsWarn;
      default:
        return kReceiptsAccent;
    }
  }

  Widget _detailChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReceiptDetails(Map<String, dynamic> receipt) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final hasProofImage = (receipt['proof_image_url'] ?? '')
            .toString()
            .isNotEmpty;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Receipt Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kReceiptsText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sheetReceiptCard(receipt),
                    const SizedBox(height: 16),
                    if (hasProofImage)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showProofPreview(receipt),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Preview GCash proof'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    if (hasProofImage) const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _printReceipt(receipt),
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Print receipt details'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kReceiptsAccent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheetReceiptCard(Map<String, dynamic> receipt) {
    final source = (receipt['source'] ?? '').toString().toLowerCase();
    final sourceTone = source == 'gcash' ? kReceiptsWarn : kReceiptsSuccess;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kReceiptsSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sourceTone.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (receipt['member_name'] ?? 'Unknown member').toString(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: kReceiptsText,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
              _statusChip(
                (receipt['source_label'] ?? 'Receipt').toString(),
                sourceTone,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatAmount(receipt['amount']),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: sourceTone,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 16),
          _sheetRow(
            'Member',
            (receipt['member_name'] ?? 'Unknown member').toString(),
          ),
          _sheetRow('Amount', _formatAmount(receipt['amount'])),
          _sheetRow('Source', (receipt['source_label'] ?? '').toString()),
          _sheetRow('Status', (receipt['status'] ?? '').toString()),
          _sheetRow(
            'Collector',
            (receipt['collector_name'] ?? 'Collector not set').toString(),
          ),
          _sheetRow(
            'Reference',
            (receipt['reference'] ?? '').toString().isEmpty
                ? 'N/A'
                : receipt['reference'].toString(),
          ),
          _sheetRow('Receipt ID', (receipt['receipt_id'] ?? 'N/A').toString()),
          _sheetRow('Date', _formatDate(receipt['display_date'])),
          const SizedBox(height: 6),
          Text(
            (receipt['supporting_text'] ?? '').toString(),
            style: const TextStyle(
              fontSize: 13,
              color: kReceiptsSubText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProofPreview(Map<String, dynamic> receipt) async {
    final proofImageUrl = (receipt['proof_image_url'] ?? '').toString();
    if (proofImageUrl.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReceiptProofPreviewPage(
          memberName: (receipt['member_name'] ?? 'Member').toString(),
          reference: (receipt['reference'] ?? '').toString(),
          imageUrl: proofImageUrl,
        ),
      ),
    );
  }

  Future<void> _printReceipt(Map<String, dynamic> receipt) async {
    final proofImageUrl = (receipt['proof_image_url'] ?? '').toString();

    try {
      final pdfTheme = await _getPdfTheme();
      final document = pw.Document();
      pw.ImageProvider? proofImage;
      if (proofImageUrl.isNotEmpty) {
        try {
          proofImage = await networkImage(proofImageUrl);
        } catch (_) {
          proofImage = null;
        }
      }

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pdfTheme,
          build: (_) => [
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB)),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Dayung Receipt',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text('Printed: ${DateTime.now().toLocal()}'),
                  pw.SizedBox(height: 18),
                  _pdfLine(
                    'Member',
                    (receipt['member_name'] ?? 'Unknown member').toString(),
                  ),
                  _pdfLine('Amount', _formatAmount(receipt['amount'])),
                  _pdfLine(
                    'Source',
                    (receipt['source_label'] ?? '').toString(),
                  ),
                  _pdfLine('Status', (receipt['status'] ?? '').toString()),
                  _pdfLine(
                    'Collector',
                    (receipt['collector_name'] ?? 'Collector not set')
                        .toString(),
                  ),
                  _pdfLine(
                    'Reference',
                    (receipt['reference'] ?? '').toString().isEmpty
                        ? 'N/A'
                        : receipt['reference'].toString(),
                  ),
                  _pdfLine(
                    'Receipt ID',
                    (receipt['receipt_id'] ?? 'N/A').toString(),
                  ),
                  _pdfLine('Date', _formatDate(receipt['display_date'])),
                  pw.SizedBox(height: 12),
                  pw.Text((receipt['supporting_text'] ?? '').toString()),
                ],
              ),
            ),
            if (proofImage != null) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                'GCash Proof',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Image(proofImage, fit: pw.BoxFit.contain, height: 320),
            ],
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (_) async => document.save());
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Printing was added recently. Stop the app and run it again, then try printing once more.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to print receipt: $error')),
      );
    }
  }

  pw.Widget _pdfLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 88,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  Widget _sheetRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: kReceiptsSubText,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kReceiptsText,
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Color(0xFFB45309)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Could not load receipts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kReceiptsText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _error ?? 'Unknown error',
                style: const TextStyle(
                  color: kReceiptsSubText,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadReceipts,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry fetch'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final hasFilters = _searchQuery.isNotEmpty || _sourceFilter != 'all';
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: kReceiptsSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kReceiptsBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kReceiptsAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 32,
              color: kReceiptsAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters ? 'No matching receipts found' : 'No receipts found yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kReceiptsText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilters
                ? 'Try another search term or switch the source filter back to all.'
                : 'Receipt history will appear here once payments are recorded or GCash proofs are submitted.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: kReceiptsSubText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _sourceFilter = 'all';
                });
              },
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Reset filters'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GcashLoadResult {
  final List<Map<String, dynamic>> rows;
  final bool usedFallback;

  const _GcashLoadResult({required this.rows, required this.usedFallback});
}

class _ReceiptProofPreviewPage extends StatelessWidget {
  final String memberName;
  final String reference;
  final String imageUrl;

  const _ReceiptProofPreviewPage({
    required this.memberName,
    required this.reference,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(memberName),
            if (reference.isNotEmpty)
              Text(
                'Ref: $reference',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: PhotoView(
        imageProvider: NetworkImage(imageUrl),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Unable to load the GCash proof image.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
        loadingBuilder: (context, event) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
      ),
    );
  }
}
