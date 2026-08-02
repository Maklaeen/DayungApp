import 'dart:math';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF111827);
const Color kSubtleText = Color(0xFF6B7280);
const Color kCard = Colors.white;
const Color kBorder = Color(0xFFE5E7EB);
const Color kSurface = Color(0xFFF8FAFC);

class ManageFundPage extends StatefulWidget {
  final int dayungUnitId;
  const ManageFundPage({super.key, required this.dayungUnitId});

  @override
  State<ManageFundPage> createState() => _ManageFundPageState();
}

class _ManageFundPageState extends State<ManageFundPage> {
  static const Duration _queryTimeout = Duration(seconds: 10);

  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _funds = [];

  String _search = '';
  String _statusFilter = 'all';
  final String _sort = 'date_desc';
  String _typeFilter = 'members';

  double _totalPaid = 0.0;
  double _totalGoal = 0.0;
  int _approvedMemberCount = 0;

  bool get _hasActiveFilters {
    return _search.isNotEmpty ||
        _statusFilter != 'all' ||
        _typeFilter != 'members';
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final approvedResFuture = sb
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved')
          .timeout(_queryTimeout);
      final noticeResFuture = sb
          .from('death_notices')
          .select('id, name, date_of_death, deceased_type, user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('date_of_death', ascending: false)
          .timeout(_queryTimeout);
      final paymentResFuture = sb
          .from('payments')
          .select('amount, status, paid_at, user_id, collected_by, is_claimed')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .timeout(_queryTimeout);

      final results = await Future.wait([
        approvedResFuture,
        noticeResFuture,
        paymentResFuture,
      ]);

      final approvedRes = results[0];
      final approvedUserIds = {
        for (final row in List<Map<String, dynamic>>.from(approvedRes))
          (row['user_id'] ?? '').toString(),
      }..remove('');

      final noticeRes = results[1];
      final paymentRes = results[2];

      final rows = List<Map<String, dynamic>>.from(paymentRes);
      final currentUserId = sb.auth.currentUser?.id;
      double treasurerCollected = 0.0;
      for (final row in rows) {
        final collectedBy = (row['collected_by'] ?? '').toString();
        final status = (row['status'] ?? '').toString().toLowerCase();
        if (currentUserId != null &&
            collectedBy == currentUserId &&
            status == 'paid' &&
            row['is_claimed'] != true) {
          treasurerCollected += _asDouble(row['amount']);
        }
      }

      final noticeLookup = <int, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(noticeRes)) {
        final id = int.tryParse('${row['id']}');
        if (id != null) {
          noticeLookup[id] = row;
        }
      }

      final byNotice = <int, Map<String, dynamic>>{};
      for (final entry in noticeLookup.entries) {
        final notice = entry.value;
        final excludedUserId = (notice['user_id'] ?? '').toString();
        final expectedMembers = approvedUserIds
            .where((userId) => userId != excludedUserId)
            .length;

        byNotice[entry.key] = {
          'id': entry.key,
          'name': (notice['name'] ?? 'Death Notice').toString(),
          'paid': 0.0,
          'goal': 0.0,
          'deadline': (notice['date_of_death'] ?? '').toString(),
          'status': '',
          'progress': 0.0,
          'type': (notice['deceased_type'] ?? 'member').toString(),
          'expectedMembers': expectedMembers,
          'recordedMembers': 0,
          'missingMembers': expectedMembers,
          'excludedUserId': excludedUserId,
          'rowUserIds': <String>{},
        };
      }

      for (final r in rows) {
        final dnId = int.tryParse('${r[''] ?? ''}');
        if (dnId == null) continue;

        final notice = noticeLookup[dnId];
        final name = (notice?['name'] ?? 'Death Notice').toString();
        final dateStr = (notice?['date_of_death'] ?? '').toString();
        final dtype = (notice?['deceased_type'] ?? '').toString().isEmpty
            ? 'member'
            : (notice?['deceased_type']).toString().toLowerCase().trim();
        final amt = _asDouble(r['amount']);
        final status = (r['status'] ?? '').toString().toLowerCase();
        final rowUserId = (r['user_id'] ?? '').toString();

        final bucket = byNotice.putIfAbsent(dnId, () {
          final excludedUserId = (notice?['user_id'] ?? '').toString();
          final expectedMembers = approvedUserIds
              .where((userId) => userId != excludedUserId)
              .length;
          return {
            'id': dnId,
            'name': name,
            'paid': 0.0,
            'goal': 0.0,
            'deadline': dateStr,
            'status': '',
            'progress': 0.0,
            'type': dtype,
            'expectedMembers': expectedMembers,
            'recordedMembers': 0,
            'missingMembers': expectedMembers,
            'excludedUserId': excludedUserId,
            'rowUserIds': <String>{},
          };
        });

        final rowUserIds = bucket['rowUserIds'] as Set<String>;
        if (rowUserId.isNotEmpty && approvedUserIds.contains(rowUserId)) {
          rowUserIds.add(rowUserId);
        }

        bucket['goal'] = (bucket['goal'] as double) + amt;
        if (status == 'paid') {
          bucket['paid'] = (bucket['paid'] as double) + amt;
        }

        // Keep latest label fields
        bucket['name'] = name;
        bucket['deadline'] = dateStr;
        bucket['type'] = dtype;
      }

      final list = byNotice.values.toList();

      for (final f in list) {
        final expectedMembers = (f['expectedMembers'] as int?) ?? 0;
        final rowUserIds = (f['rowUserIds'] as Set<String>? ?? <String>{});
        final recordedMembers = rowUserIds.length;
        final missingMembers = max(0, expectedMembers - recordedMembers);
        final paid = (f['paid'] as double);
        final storedGoal = (f['goal'] as double);
        final goal = max(storedGoal, expectedMembers.toDouble());
        final p = goal <= 0 ? 0.0 : (paid / goal).clamp(0.0, 1.0);
        f['goal'] = goal;
        f['progress'] = p;
        f['recordedMembers'] = recordedMembers;
        f['missingMembers'] = missingMembers;
        f['status'] = (paid >= goal && goal > 0)
            ? 'Completed'
            : 'Still Collecting...';
        f.remove('rowUserIds');
      }

      // Default sort: latest date first
      list.sort((a, b) {
        final ad = DateTime.tryParse((a['deadline'] ?? '').toString());
        final bd = DateTime.tryParse((b['deadline'] ?? '').toString());
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      // --- ADVANCE FUND LOGIC ---
      final advanceRes = await sb
          .from('payments')
          .select('amount, status')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('type', 'deceased_payment')
          .neq('is_claimed', true)
          .timeout(_queryTimeout);

      double advancePaid = 0.0;
      double advanceGoal = 0.0;
      for (final r in List<Map<String, dynamic>>.from(advanceRes)) {
        final amt = (r['amount'] is num)
            ? (r['amount'] as num).toDouble()
            : double.tryParse('${r['amount']}') ?? 0.0;
        final status = (r['status'] ?? '').toString().toLowerCase();
        advanceGoal += amt;
        if (status == 'paid') advancePaid += amt;
      }

      if (advanceGoal > 0 || advancePaid > 0) {
        list.add({
          'id': 0,
          'name': 'Advance Fund',
          'paid': advancePaid,
          'goal': advanceGoal,
          'deadline': '',
          'status': (advancePaid >= advanceGoal && advanceGoal > 0)
              ? 'Completed'
              : 'Still Collecting...',
          'progress': advanceGoal <= 0
              ? 0.0
              : (advancePaid / advanceGoal).clamp(0.0, 1.0),
          'type': 'member', // default bucket
          'expectedMembers': approvedUserIds.length,
          'recordedMembers': 0,
          'missingMembers': 0,
        });
      }
      // --- END ADVANCE FUND LOGIC ---

      double totalGoal = 0.0;
      for (final fund in list) {
        totalGoal += _asDouble(fund['goal']);
      }

      if (!mounted) return;
      setState(() {
        _funds = list;
        _totalPaid = treasurerCollected;
        _totalGoal = totalGoal;
        _approvedMemberCount = approvedUserIds.length;
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _funds = [];
        _totalPaid = 0.0;
        _totalGoal = 0.0;
        _approvedMemberCount = 0;
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _funds = [];
        _totalPaid = 0.0;
        _totalGoal = 0.0;
        _approvedMemberCount = 0;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _onRefresh() => _load();

  void _resetFilters() {
    setState(() {
      _search = '';
      _statusFilter = 'all';
      _typeFilter = 'members';
    });
  }

  List<Map<String, dynamic>> get _visibleFunds {
    List<Map<String, dynamic>> list = _funds;

    // Filter by status
    if (_statusFilter == 'collecting') {
      list = list
          .where((f) => (f['status'] ?? '').toString() != 'Completed')
          .toList();
    } else if (_statusFilter == 'completed') {
      list = list
          .where((f) => (f['status'] ?? '').toString() == 'Completed')
          .toList();
    }

    // Search by name
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((f) => (f['name'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }

    // Type filter: Members | Beneficiaries
    bool isMember(Map f) =>
        (f['type'] ?? 'member').toString().toLowerCase().contains('member');
    bool isBeneficiary(Map f) =>
        (f['type'] ?? '').toString().toLowerCase().contains('benefic');

    if (_typeFilter == 'members') {
      list = list.where(isMember).toList();
    } else if (_typeFilter == 'beneficiaries') {
      list = list.where(isBeneficiary).toList();
    }

    // Sort
    int cmpDate(a, b, {bool desc = true}) {
      final ad = DateTime.tryParse((a['deadline'] ?? '').toString());
      final bd = DateTime.tryParse((b['deadline'] ?? '').toString());
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return desc ? bd.compareTo(ad) : ad.compareTo(bd);
    }

    switch (_sort) {
      case 'date_asc':
        list.sort((a, b) => cmpDate(a, b, desc: false));
        break;
      case 'progress_desc':
        list.sort((a, b) {
          final pa = ((a['progress'] ?? 0.0) as double);
          final pb = ((b['progress'] ?? 0.0) as double);
          return pb.compareTo(pa);
        });
        break;
      case 'date_desc':
      default:
        list.sort((a, b) => cmpDate(a, b, desc: true));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildPageHeader(isWide),
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
                      ? const DayungPageSkeleton(
                          layout: DayungSkeletonLayout.dashboard,
                          itemCount: 4,
                        )
                      : _error != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _onRefresh,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: [
                              _summaryHeader(),
                              const SizedBox(height: 12),
                              _filtersBar(),
                              const SizedBox(height: 10),
                              if (_visibleFunds.isEmpty)
                                _buildEmptyState()
                              else
                                ...List.generate(
                                  _visibleFunds.length,
                                  (i) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: _fundCard(_visibleFunds[i]),
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

  Widget _buildPageHeader(bool isWide) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        isWide ? 36 : 28,
        isWide ? 24 : 16,
        isWide ? 32 : 24,
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
                  'Manage Funds',
                  style: TextStyle(
                    fontSize: isWide ? 24 : 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                // Text(
                //   'Track collection progress, missing fund rows, and member payment status.',
                //   style: TextStyle(
                //     fontSize: isWide ? 14 : 13,
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
                      icon: Icons.groups_rounded,
                      label: '$_approvedMemberCount active members',
                    ),
                    _headerPill(
                      icon: Icons.receipt_long_rounded,
                      label: '${_visibleFunds.length} visible funds',
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

  Widget _buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
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
                      'Could not load fund records',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kNeutralText,
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
                  color: kSubtleText,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _onRefresh,
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
    return Container(
      margin: const EdgeInsets.only(top: 28),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 32,
              color: kPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No matching funds found',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kNeutralText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _hasActiveFilters
                ? 'Try a different search term or reset the current filters.'
                : 'No fund records are available for this unit yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kSubtleText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
            ),
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _resetFilters,
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

  Widget _summaryHeader() {
    final remaining = (_totalGoal - _totalPaid).clamp(0.0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fund Overview',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kNeutralText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Review all active death notices, check missing funds, and generate any pending member fund rows that still need to be created.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: kSubtleText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoBadge(
                icon: Icons.groups_rounded,
                label: '$_approvedMemberCount approved members',
                color: const Color(0xFF1E40AF),
              ),
              _infoBadge(
                icon: Icons.rule_folder_rounded,
                label: '${_funds.length} total fund buckets',
                color: const Color(0xFF0F766E),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              if (compact) {
                return Column(
                  children: [
                    Row(
                      children: [
                        _kpi(
                          'Collected',
                          _currency(_totalPaid),
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 12),
                        _kpi(
                          'Goal',
                          _currency(_totalGoal),
                          color: Colors.indigo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _kpi(
                          'Remaining',
                          _currency(remaining),
                          color: Colors.orange,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  _kpi(
                    'Own Collected',
                    _currency(_totalPaid),
                    color: Colors.teal,
                  ),
                  const SizedBox(width: 12),
                  _kpi('Goal', _currency(_totalGoal), color: Colors.indigo),
                  const SizedBox(width: 12),
                  _kpi('Remaining', _currency(remaining), color: Colors.orange),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filtersBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
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
              color: kNeutralText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Search by deceased name or narrow the list by collection status and notice type.',
            style: TextStyle(
              fontSize: 13,
              color: kSubtleText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search deceased name',
              hintStyle: const TextStyle(fontWeight: FontWeight.w500),
              prefixIcon: const Icon(Icons.search),
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
                borderSide: const BorderSide(color: Color(0xFF1E40AF)),
              ),
            ),
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _segmentedGroup(
              children: [
                _segChip('All', 'all'),
                _segChip('Collecting', 'collecting'),
                _segChip('Completed', 'completed'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _segmentedGroup(
              children: [
                _segChipType('Members', 'members'),
                _segChipType('Beneficiaries', 'beneficiaries'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentedGroup({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Wrap(spacing: 2, runSpacing: 2, children: children),
    );
  }

  Widget _infoBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _segChip(String label, String key) {
    final selected = _statusFilter == key;
    return GestureDetector(
      onTap: selected ? null : () => setState(() => _statusFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E40AF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF1E40AF),
          ),
        ),
      ),
    );
  }

  // NEW: Type segmented chip
  Widget _segChipType(String label, String key) {
    final selected = _typeFilter == key;
    return GestureDetector(
      onTap: selected ? null : () => setState(() => _typeFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E40AF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF1E40AF),
          ),
        ),
      ),
    );
  }

  Widget _fundCard(Map<String, dynamic> fund) {
    final paid = (fund['paid'] as double?) ?? 0.0;
    final goal = (fund['goal'] as double?) ?? 0.0;
    final progress = (fund['progress'] as double?)?.clamp(0.0, 1.0) ?? 0.0;
    final deadline = (fund['deadline'] ?? '').toString();
    final completed = (fund['status'] ?? '').toString() == 'Completed';
    final recordedMembers = (fund['recordedMembers'] as int?) ?? 0;
    final missingMembers = (fund['missingMembers'] as int?) ?? 0;
    final expectedMembers = (fund['expectedMembers'] as int?) ?? 0;
    final noticeId = fund['id'] is int
        ? fund['id'] as int
        : int.tryParse('${fund['id']}') ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _jarIcon(progress: progress),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metricPill(
                        icon: Icons.groups_rounded,
                        label: '$expectedMembers members',
                        color: const Color(0xFF1E40AF),
                      ),
                      _metricPill(
                        icon: Icons.receipt_long_rounded,
                        label: '$recordedMembers with fund',
                        color: const Color(0xFF10B981),
                      ),
                      if (missingMembers > 0)
                        _metricPill(
                          icon: Icons.warning_amber_rounded,
                          label: '$missingMembers missing fund',
                          color: const Color(0xFFF59E0B),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Title + pill
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (fund['name'] ?? 'Death Notice').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: kNeutralText,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: completed
                              ? Colors.teal.withValues(alpha: .12)
                              : Colors.orange.withValues(alpha: .12),
                          border: Border.all(
                            color: completed ? Colors.teal : Colors.orange,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          completed ? 'Completed' : 'Collecting',
                          style: TextStyle(
                            color: completed
                                ? Colors.teal[800]
                                : Colors.orange[800],
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Amounts
                  Text(
                    '₱${paid.toStringAsFixed(2)} / ₱${goal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: kNeutralText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Progress
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: const Color(0xFFE5E7EB),
                            valueColor: AlwaysStoppedAnimation(
                              completed
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Date of death
                  Row(
                    children: [
                      const Icon(
                        Icons.event_rounded,
                        size: 16,
                        color: kSubtleText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Date of Death: ${deadline.isEmpty ? '—' : deadline}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: kSubtleText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 430;
                      final buttons = [
                        SizedBox(
                          width: compact ? double.infinity : null,
                          child: OutlinedButton.icon(
                            onPressed: noticeId <= 0
                                ? null
                                : () => _showPaymentStatusSheet(
                                    noticeId,
                                    widget.dayungUnitId,
                                  ),
                            icon: const Icon(
                              Icons.people_alt_rounded,
                              size: 20,
                            ),
                            label: const Text('View Members'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: compact ? double.infinity : null,
                          child: ElevatedButton.icon(
                            onPressed: noticeId <= 0 || completed
                                ? null
                                : () => _triggerPaymentCollection(
                                    noticeId,
                                    widget.dayungUnitId,
                                  ),
                            icon: const Icon(Icons.campaign_rounded, size: 20),
                            label: Text(
                              missingMembers > 0
                                  ? 'Create Missing Funds'
                                  : 'Collect',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E40AF),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ];

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buttons[0],
                            const SizedBox(height: 10),
                            buttons[1],
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: buttons[0]),
                          const SizedBox(width: 10),
                          Expanded(child: buttons[1]),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, {required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label == 'Goal')
              Text(
                '$_approvedMemberCount active members',
                style: TextStyle(
                  color: color.withValues(alpha: .7),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              )
            else
              const SizedBox(height: 0),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: .9),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color.darken(),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerPaymentCollection(
    int deathNoticeId,
    int dayungUnitId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final createdAt = DateTime.now().toUtc().toIso8601String();

    // Fetch notice meta (always contains the member/parent user_id snapshot)
    Map<String, dynamic>? dn;
    try {
      final res = await sb
          .from('death_notices')
          .select('id,deceased_type,user_id,beneficiary_id')
          .eq('id', deathNoticeId)
          .single()
          .timeout(_queryTimeout);
      dn = Map<String, dynamic>.from(res);
    } catch (_) {}

    // Exclude this user from billing (self for member, parent for beneficiary)
    final String? excludedUserId = (dn?['user_id'] ?? '').toString().isNotEmpty
        ? (dn!['user_id']).toString()
        : null;

    // Cleanup: remove any existing payment row for the excluded user (if any)
    if (excludedUserId != null && excludedUserId.isNotEmpty) {
      try {
        await sb
            .from('payments')
            .delete()
            .eq('dayung_unit_id', dayungUnitId)
            .eq('user_id', excludedUserId);
      } catch (_) {}
    }

    // Get active members for the dayung
    final appsRes = await sb
        .from('applications')
        .select('user_id')
        .eq('dayung_unit_id', dayungUnitId)
        .eq('status', 'approved')
        .timeout(_queryTimeout);
    final members = List<Map<String, dynamic>>.from(appsRes);

    // Already generated payments for this notice/dayung
    final existingRes = await sb
        .from('payments')
        .select('user_id')
        .eq('dayung_unit_id', dayungUnitId)
        .timeout(_queryTimeout);
    final existingIds = {
      for (final r in List<Map<String, dynamic>>.from(existingRes))
        (r['user_id'] ?? '').toString(),
    };

    // Prepare new rows
    final rows = <Map<String, dynamic>>[];
    for (final u in members) {
      final uid = (u['user_id'] ?? '').toString(); // CHANGED from u['id']
      if (uid.isEmpty) continue;
      if (excludedUserId != null && uid == excludedUserId) continue;
      if (existingIds.contains(uid)) continue;
      rows.add({
        'user_id': uid,
        'amount': '1',
        'status': 'pending',

        'dayung_unit_id': dayungUnitId,
        'created_at': createdAt,
      });
    }

    if (rows.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No new payments to create.')),
      );
      await _fetchAll();
      return;
    }

    try {
      await sb.from('payments').insert(rows);
      messenger.showSnackBar(
        SnackBar(content: Text('Created ${rows.length} payment(s).')),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Some payments already existed. New ones added.'),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to create payments: ${e.message}')),
        );
      }
    }

    await _fetchAll();
  }

  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load();
  }

  Future<void> _showPaymentStatusSheet(
    int deathNoticeId,
    int dayungUnitId,
  ) async {
    try {
      final noticeRes = await sb
          .from('death_notices')
          .select('id, name, user_id')
          .eq('id', deathNoticeId)
          .maybeSingle()
          .timeout(_queryTimeout);
      final excludedUserId = (noticeRes?['user_id'] ?? '').toString();

      final approvedRes = await sb
          .from('applications')
          .select('user_id, user:users!applications_user_id_fkey(full_name)')
          .eq('dayung_unit_id', dayungUnitId)
          .eq('status', 'approved')
          .timeout(_queryTimeout);

      final rows = await sb
          .from('payments')
          .select(
            'id, user_id, amount, status, paid_at, collected_by, '
            'user:users!payments_user_id_fkey(full_name), '
            'collector:users!payments_collected_by_fkey(full_name)',
          )
          .eq('dayung_unit_id', dayungUnitId)
          .timeout(_queryTimeout);

      final items = List<Map<String, dynamic>>.from(rows);
      final existingUserIds = {
        for (final row in items) (row['user_id'] ?? '').toString(),
      };

      for (final row in List<Map<String, dynamic>>.from(approvedRes)) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty || userId == excludedUserId) continue;
        if (existingUserIds.contains(userId)) continue;

        items.add({
          'id': 'virtual_$userId',
          'user_id': userId,
          'amount': '1',
          'status': 'pending',
          'paid_at': null,
          'collected_by': null,
          'user': row['user'],
          'collector': null,
          'is_virtual_pending': true,
        });
      }

      // Fallback fetch for missing collector names
      final missingCollectorIds = <String>{
        for (final r in items)
          if ((r['collected_by'] ?? '').toString().isNotEmpty &&
              ((((r['collector'] as Map?)?['full_name']) ?? '')
                  .toString()
                  .isEmpty))
            (r['collected_by']).toString(),
      }.toList();

      final collectorLookup = <String, String>{};
      if (missingCollectorIds.isNotEmpty) {
        try {
          final u = await sb
              .from('users')
              .select('id, full_name')
              .inFilter('id', missingCollectorIds)
              .timeout(_queryTimeout);
          for (final m in List<Map<String, dynamic>>.from(u)) {
            collectorLookup[(m['id'] ?? '').toString()] =
                (m['full_name'] ?? 'Collector').toString();
          }
        } catch (_) {}
      }

      // Sort by payer name
      items.sort((a, b) {
        final an = (((a['user'] as Map?)?['full_name']) ?? '')
            .toString()
            .toLowerCase();
        final bn = (((b['user'] as Map?)?['full_name']) ?? '')
            .toString()
            .toLowerCase();
        if (an.isEmpty && bn.isEmpty) return 0;
        if (an.isEmpty) return 1;
        if (bn.isEmpty) return -1;
        return an.compareTo(bn);
      });

      if (!mounted) return;
      final paidItems = items
          .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'paid')
          .toList();
      final pendingItems = items
          .where((r) => (r['status'] ?? '').toString().toLowerCase() != 'paid')
          .toList();
      final virtualPendingCount = pendingItems
          .where((r) => r['is_virtual_pending'] == true)
          .length;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) {
          final noticeName = (noticeRes?['name'] ?? 'Fund members').toString();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 56,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    noticeName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: kPrimaryDark,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Review who already has a fund and who still needs one.',
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: kSubtleText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _sheetStatCard(
                          label: 'With Fund',
                          value: '${items.length - virtualPendingCount}',
                          icon: Icons.receipt_long_rounded,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _sheetStatCard(
                          label: 'Missing Fund',
                          value: '$virtualPendingCount',
                          icon: Icons.warning_amber_rounded,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 460),
                      child: ListView(
                        children: [
                          if (paidItems.isNotEmpty) ...[
                            _sectionLabel('Paid Members'),
                            ...paidItems.map(
                              (row) => _buildPaymentTile(
                                row,
                                collectorLookup: collectorLookup,
                              ),
                            ),
                          ],
                          if (pendingItems.isNotEmpty) ...[
                            if (paidItems.isNotEmpty)
                              const SizedBox(height: 12),
                            _sectionLabel('Pending Members'),
                            ...pendingItems.map(
                              (row) => _buildPaymentTile(
                                row,
                                collectorLookup: collectorLookup,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load payments: $e')));
    }
  }

  String _fmtDateTime(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    DateTime? dt = DateTime.tryParse(s);
    if (dt == null) return '';
    dt = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _metricPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: .95),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kNeutralText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kSubtleText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: kPrimaryDark,
          fontFamily: 'Montserrat',
        ),
      ),
    );
  }

  Widget _buildPaymentTile(
    Map<String, dynamic> row, {
    required Map<String, String> collectorLookup,
  }) {
    final status = (row['status'] ?? '').toString().toLowerCase();
    final isPaid = status == 'paid';
    final isVirtualPending = row['is_virtual_pending'] == true;
    final payerName = (((row['user'] as Map?)?['full_name']) ?? '').toString();
    final title = payerName.isNotEmpty ? payerName : 'Payment #${row['id']}';
    final amt = _asDouble(row['amount'], fallback: 1.0);
    final paidAtStr = _fmtDateTime(row['paid_at']);
    final directCollectorName =
        (((row['collector'] as Map?)?['full_name']) ?? '').toString();
    final collectorName = directCollectorName.isNotEmpty
        ? directCollectorName
        : (collectorLookup[(row['collected_by'] ?? '').toString()] ?? '');

    final subtitle = isPaid
        ? 'Collected${paidAtStr.isNotEmpty ? ' on: $paidAtStr' : ''}${collectorName.isNotEmpty ? '\nCollected by: $collectorName' : ''}'
        : isVirtualPending
        ? 'No fund created yet for this member.'
        : 'Fund created, waiting for payment.';

    final accent = isPaid
        ? const Color(0xFF10B981)
        : isVirtualPending
        ? const Color(0xFFF59E0B)
        : const Color(0xFF3B82F6);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: accent.withValues(alpha: 0.12),
            child: Icon(
              isPaid
                  ? Icons.check_circle_rounded
                  : isVirtualPending
                  ? Icons.warning_amber_rounded
                  : Icons.receipt_long_rounded,
              color: accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kNeutralText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kSubtleText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${amt.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: kNeutralText,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isPaid
                      ? 'Paid'
                      : isVirtualPending
                      ? 'No Fund Yet'
                      : 'Pending',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Animated, asset-free “jar” indicator
  Widget _jarIcon({double progress = 0.0}) {
    final clamped = progress.clamp(0.0, 1.0);

    return SizedBox(
      width: 56,
      height: 86,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Jar neck
          Positioned(
            top: 0,
            child: Container(
              width: 20,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          // Jar body outline
          Positioned(
            top: 10,
            left: 6,
            right: 6,
            bottom: 6,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Liquid fill with animation
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: clamped),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final height = 60 * value;
                return Container(
                  height: height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.teal.shade400, Colors.teal.shade200],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CustomPaint(
                    painter: _WavePainter(amplitude: 3, phase: 0.0),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _currency(double n) {
    return '₱${n.toStringAsFixed(2)}';
  }
}

// Subtle wave overlay inside the liquid
class _WavePainter extends CustomPainter {
  final double amplitude;
  final double phase;
  _WavePainter({this.amplitude = 3, this.phase = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;

    final path = Path();
    final midY = size.height * 0.25;

    path.moveTo(0, midY);
    for (double x = 0; x <= size.width; x++) {
      final y = midY + amplitude * sin(0.5 * (x / size.width * 6.283 + phase));
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.amplitude != amplitude;
  }
}

extension _ColorX on Color {
  Color darken([double amount = .2]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final h = hsl.hue,
        s = hsl.saturation,
        l = (hsl.lightness - amount).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(hsl.alpha, h, s, l).toColor();
  }
}
