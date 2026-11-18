import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentReleaseHistoryPage extends StatefulWidget {
  final int dayungUnitId;

  const PaymentReleaseHistoryPage({super.key, required this.dayungUnitId});

  @override
  State<PaymentReleaseHistoryPage> createState() =>
      _PaymentReleaseHistoryPageState();
}

class _PaymentReleaseHistoryPageState extends State<PaymentReleaseHistoryPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  double _totalReleased = 0;
  List<Map<String, dynamic>> _releases = [];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final paymentRows = List<Map<String, dynamic>>.from(
        await sb
            .from('payments')
            .select('id, amount, claim_id, userdeceased, deceased_name')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('status', 'paid')
            .eq('is_claimed', true),
      );

      final deceasedUserIds = paymentRows
          .map((row) => '${row['userdeceased'] ?? ''}'.trim())
          .where((id) => id.isNotEmpty && id != 'null')
          .toSet()
          .toList();

      final claimsByUserId = <String, Map<String, dynamic>>{};
      if (deceasedUserIds.isNotEmpty) {
        final claimRows = await sb
            .from('claims')
            .select('id, claimedmoney_date, user_id, dayung_unit_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .inFilter('user_id', deceasedUserIds);
        for (final claim in List<Map<String, dynamic>>.from(claimRows)) {
          final userId = '${claim['user_id'] ?? ''}'.trim();
          final existing = claimsByUserId[userId];
          final existingDate = DateTime.tryParse(
            '${existing?['claimedmoney_date'] ?? ''}',
          );
          final claimDate = DateTime.tryParse(
            '${claim['claimedmoney_date'] ?? ''}',
          );
          if (existing == null ||
              (claimDate != null &&
                  (existingDate == null || claimDate.isAfter(existingDate)))) {
            claimsByUserId[userId] = claim;
          }
        }
      }

      double total = 0;
      final releasesByUser = <String, Map<String, dynamic>>{};
      for (final payment in paymentRows) {
        final amount = _asDouble(payment['amount']);
        final userDeceased = '${payment['userdeceased'] ?? ''}'.trim();
        final claim = claimsByUserId[userDeceased];
        final key = userDeceased.isEmpty ? 'Unknown user' : userDeceased;
        total += amount;
        final release = releasesByUser.putIfAbsent(
          key,
          () => {
            'amount': 0.0,
            'date': claim?['claimedmoney_date'],
            'deceased_name': payment['deceased_name'] ?? 'Member',
          },
        );
        release['amount'] = (release['amount'] as double) + amount;

        final currentDate = DateTime.tryParse('${release['date'] ?? ''}');
        final paymentDate = DateTime.tryParse(
          '${claim?['claimedmoney_date'] ?? ''}',
        );
        if (currentDate == null ||
            (paymentDate != null && paymentDate.isAfter(currentDate))) {
          release['date'] = claim?['claimedmoney_date'];
        }
      }

      final releases = releasesByUser.entries
          .map(
            (entry) => {
              'userdeceased': entry.key,
              'deceased_name': entry.value['deceased_name'],
              'amount': entry.value['amount'],
              'date': entry.value['date'],
            },
          )
          .toList();

      releases.sort((a, b) {
        final aDate = DateTime.tryParse('${a['date'] ?? ''}');
        final bDate = DateTime.tryParse('${b['date'] ?? ''}');
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _totalReleased = total;
        _releases = releases;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Unable to load payment release history: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load payment release history.';
        _releases = [];
        _totalReleased = 0;
        _loading = false;
      });
    }
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (date == null) return 'Release date unavailable';
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  String _formatCurrency(double value) => '₱${value.toStringAsFixed(2)}';

  List<Map<String, dynamic>> get _visibleReleases {
    final query = _searchQuery.trim().toLowerCase();
    final visible = _releases.where((release) {
      if (query.isEmpty) return true;
      final name = '${release['deceased_name'] ?? ''}'.toLowerCase();
      final date = _formatDate(release['date']).toLowerCase();
      return name.contains(query) || date.contains(query);
    }).toList();

    visible.sort((a, b) {
      final aDate = DateTime.tryParse('${a['date'] ?? ''}');
      final bDate = DateTime.tryParse('${b['date'] ?? ''}');
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final comparison = bDate.compareTo(aDate);
      return _newestFirst ? comparison : -comparison;
    });
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color: Color(0xFF0D47A1),
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
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Payment Release History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh history',
                    onPressed: _loading ? null : _loadHistory,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadHistory,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _buildSummaryCard(),
                    const SizedBox(height: 12),
                    _buildFilterControls(),
                    const SizedBox(height: 12),
                    if (_loading)
                      const SizedBox(
                        height: 280,
                        child: DayungPageSkeleton(
                          layout: DayungSkeletonLayout.list,
                          padding: EdgeInsets.all(8),
                          itemCount: 2,
                        ),
                      )
                    else if (_error != null)
                      _buildErrorState()
                    else if (_visibleReleases.isEmpty)
                      _buildEmptyState()
                    else
                      _buildReleaseTable(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D9488),
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final amount = _loading ? '—' : _formatCurrency(_totalReleased);
          final releaseCount =
              '${_releases.length} ${_releases.length == 1 ? 'release' : 'releases'}';
          final amountContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Total released',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );
          final countBadge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Text(
                  releaseCount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );

          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [amountContent, const SizedBox(height: 10), countBadge],
            );
          }
          return Row(children: [amountContent, const Spacer(), countBadge]);
        },
      ),
    );
  }

  Widget _buildFilterControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchField = TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          decoration: InputDecoration(
            hintText: 'Search name or date',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
        final sortField = DropdownButtonFormField<bool>(
          initialValue: _newestFirst,
          decoration: InputDecoration(
            labelText: 'Sort by',
            prefixIcon: const Icon(Icons.sort_rounded),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          items: const [
            DropdownMenuItem(value: true, child: Text('Newest first')),
            DropdownMenuItem(value: false, child: Text('Oldest first')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _newestFirst = value);
          },
        );

        if (constraints.maxWidth < 640) {
          return Column(
            children: [searchField, const SizedBox(height: 8), sortField],
          );
        }
        return Row(
          children: [
            Expanded(flex: 7, child: searchField),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: sortField),
          ],
        );
      },
    );
  }

  Widget _buildReleaseTable() {
    return RecordDataTable(
      minWidth: 620,
      headingRowHeight: 48,
      dataRowMinHeight: 64,
      dataRowMaxHeight: 80,
      columnSpacing: 24,
      horizontalMargin: 16,
      columns: const [
        DataColumn(label: Text('Deceased')),
        DataColumn(label: Text('Release date')),
        DataColumn(label: Text('Amount')),
      ],
      rows: _visibleReleases.map((release) {
        return DataRow(
          cells: [
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF0D9488),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${release['deceased_name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            DataCell(Text(_formatDate(release['date']))),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatCurrency(release['amount'] as double),
                  style: const TextStyle(
                    color: Color(0xFF0D9488),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _loadHistory,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final searching = _searchQuery.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.receipt_long_outlined,
            size: 36,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            searching ? 'No matching releases' : 'No releases yet',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (searching) ...[
            const SizedBox(height: 4),
            Text(
              'Try another name or date.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              icon: const Icon(Icons.clear_rounded),
              label: const Text('Clear search'),
            ),
          ],
        ],
      ),
    );
  }
}
