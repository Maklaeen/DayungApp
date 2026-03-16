import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/utils/theme_surface.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kAccentDark = Color(0xFF083366);
const kBorder = Color(0xFFE5E7EB);
const kSurface = Color(0xFFF8FAFC);
const kSuccess = Color(0xFF10B981);
const kWarn = Color(0xFFF59E0B);

class MembersPage extends StatefulWidget {
  final int? dayungUnitId;

  const MembersPage({super.key, this.dayungUnitId});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  static const int _pageSize = 50;
  static const Duration _queryTimeout = Duration(seconds: 10);

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  int _currentPage = 0;
  bool _hasMore = false;
  String _searchQuery = '';
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadPayments();
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

  Future<void> _loadPayments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      dynamic query = Supabase.instance.client
          .from('payments')
          .select(
            'id, user_id, amount, status, created_at, paid_at, collected_by, dayung_unit_id, '
            'users!payments_user_id_fkey(full_name), '
            'collector:users!payments_collected_by_fkey(full_name)',
          );

      if (widget.dayungUnitId != null) {
        query = query.eq('dayung_unit_id', widget.dayungUnitId as Object);
      }

      final rows = List<Map<String, dynamic>>.from(
        await query
            .order('created_at', ascending: false)
            .range(
              _currentPage * _pageSize,
              (_currentPage * _pageSize) + _pageSize,
            )
            .timeout(_queryTimeout),
      );

      final hasMore = rows.length > _pageSize;
      final pageItems = hasMore ? rows.take(_pageSize).toList() : rows;

      if (!mounted) return;
      setState(() {
        _payments = pageItems
            .map(
              (item) => {
                'id': item['id'],
                'user_id': (item['user_id'] ?? '').toString(),
                'amount': item['amount'],
                'status': (item['status'] ?? 'pending').toString(),
                'full_name':
                    (item['users'] as Map?)?['full_name']?.toString() ??
                    'Unknown member',
                'created_at': (item['created_at'] ?? '').toString(),
                'paid_at': (item['paid_at'] ?? '').toString(),
                'collected_by': (item['collected_by'] ?? '').toString(),
                'collector_full_name':
                    (item['collector'] as Map?)?['full_name']?.toString() ??
                    'Not assigned',
              },
            )
            .toList();
        _hasMore = hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load member payments: $e';
        _loading = false;
      });
    }
  }

  Future<void> _goToNextPage() async {
    if (!_hasMore) return;
    setState(() => _currentPage++);
    await _loadPayments();
  }

  Future<void> _goToPreviousPage() async {
    if (_currentPage == 0) return;
    setState(() => _currentPage--);
    await _loadPayments();
  }

  List<Map<String, dynamic>> get _visiblePayments {
    final query = _searchQuery.toLowerCase();
    return _payments.where((payment) {
      final matchesStatus =
          _statusFilter == 'all' ||
          (payment['status'] ?? '').toString().toLowerCase() == _statusFilter;
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      final amountText = '${payment['amount'] ?? ''}'.toLowerCase();
      final memberName = (payment['full_name'] ?? '').toString().toLowerCase();
      final collectorName = (payment['collector_full_name'] ?? '')
          .toString()
          .toLowerCase();
      return amountText.contains(query) ||
          memberName.contains(query) ||
          collectorName.contains(query);
    }).toList();
  }

  int get _paidCount {
    return _payments
        .where(
          (payment) =>
              (payment['status'] ?? '').toString().toLowerCase() == 'paid',
        )
        .length;
  }

  int get _pendingCount => _payments.length - _paidCount;

  String _formatAmount(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse('${value ?? ''}') ?? 0.0;
    return 'PHP ${amount.toStringAsFixed(2)}';
  }

  String _formatDate(String value) {
    if (value.isEmpty) return 'Not available';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
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
    return '$month ${parsed.day}, ${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 860;

    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(wide),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: dayungSurface(context),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [dayungTopShadow(context)],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: kAccent),
                        )
                      : _error != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          color: kAccent,
                          onRefresh: _loadPayments,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            children: [
                              _buildOverviewCard(),
                              const SizedBox(height: 18),
                              _buildSearchAndFilterCard(),
                              const SizedBox(height: 18),
                              if (_visiblePayments.isEmpty)
                                _buildEmptyState()
                              else
                                ..._visiblePayments.map(_buildPaymentCard),
                              const SizedBox(height: 20),
                              _buildPaginationBar(),
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
                  'Members',
                  style: TextStyle(
                    fontSize: wide ? 24 : 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Review member payment activity, who collected it, and the current status of each record.',
                  style: TextStyle(
                    fontSize: wide ? 14 : 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _headerPill(
                      icon: Icons.payments_rounded,
                      label: '${_payments.length} loaded records',
                    ),
                    _headerPill(
                      icon: Icons.filter_list_rounded,
                      label: widget.dayungUnitId == null
                          ? 'All units'
                          : 'Dayung ${widget.dayungUnitId}',
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
        icon: Icons.receipt_long_rounded,
        label: 'Page Records',
        value: '${_payments.length}',
        tone: const Color(0xFF1E40AF),
      ),
      _statCard(
        icon: Icons.check_circle_rounded,
        label: 'Paid',
        value: '$_paidCount',
        tone: kSuccess,
      ),
      _statCard(
        icon: Icons.pending_actions_rounded,
        label: 'Pending',
        value: '$_pendingCount',
        tone: kWarn,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
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
            'Member Payment Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Track which members already paid, which payments are still pending, and who recorded each collection.',
            style: TextStyle(
              fontSize: 13,
              color: kSubText,
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
                    color: kSubText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kText,
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

  Widget _buildSearchAndFilterCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
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
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Search by member, amount, or collector name, then narrow the list by payment status.',
            style: TextStyle(
              fontSize: 13,
              color: kSubText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by member, amount, or collector',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: kSurface,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kAccent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip('All', 'all'),
              _filterChip('Paid', 'paid'),
              _filterChip('Pending', 'pending'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String key) {
    final selected = _statusFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kAccent : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? kAccent : kAccent.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : kAccentDark,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    final status = (payment['status'] ?? 'pending').toString().toLowerCase();
    final isPaid = status == 'paid';
    final tone = isPaid ? kSuccess : kWarn;
    final dateValue = isPaid
        ? (payment['paid_at'] ?? '').toString()
        : (payment['created_at'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tone.withValues(alpha: 0.16)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: tone.withValues(alpha: 0.12),
                  child: Icon(
                    isPaid
                        ? Icons.check_circle_rounded
                        : Icons.pending_actions_rounded,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (payment['full_name'] ?? 'Member').toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: kText,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatAmount(payment['amount']),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: tone,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isPaid ? 'Paid' : 'Pending',
                    style: TextStyle(color: tone, fontWeight: FontWeight.w800),
                  ),
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
                      'Collector: ${(payment['collector_full_name'] ?? 'Not assigned').toString()}',
                  color: const Color(0xFF1E40AF),
                  background: const Color(0xFFEFF6FF),
                ),
                _detailChip(
                  icon: Icons.schedule_rounded,
                  label: _formatDate(dateValue),
                  color: isPaid ? kSuccess : kWarn,
                  background: isPaid
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFFFBEB),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  Widget _buildPaginationBar() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _currentPage == 0 ? null : _goToPreviousPage,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Previous'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'Page ${_currentPage + 1}',
            style: const TextStyle(
              color: kAccentDark,
              fontWeight: FontWeight.w800,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _hasMore ? _goToNextPage : null,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E7EB),
              disabledForegroundColor: const Color(0xFF6B7280),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
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
                      'Could not load member payments',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kText,
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
                  color: kSubText,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadPayments,
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
    final hasFilters = _searchQuery.isNotEmpty || _statusFilter != 'all';
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.people_alt_rounded,
              size: 32,
              color: kAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters ? 'No matching payments found' : 'No payments found',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilters
                ? 'Try another search term or reset the current status filter.'
                : 'Payment records will appear here once members start paying.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: kSubText,
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
                  _statusFilter = 'all';
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
