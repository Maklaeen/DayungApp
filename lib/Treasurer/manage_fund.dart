import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF111827);
const Color kSubtleText = Color(0xFF6B7280);
const Color kCard = Colors.white;

class ManageFundPage extends StatefulWidget {
  final int dayungUnitId;
  const ManageFundPage({super.key, required this.dayungUnitId});

  @override
  State<ManageFundPage> createState() => _ManageFundPageState();
}

class _ManageFundPageState extends State<ManageFundPage> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _funds = [];

  String _search = '';
  String _statusFilter = 'all';
  String _sort = 'date_desc';
  String _typeFilter = 'members';

  double _totalPaid = 0.0;
  double _totalGoal = 0.0;

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
      final res = await sb
          .from('payments')
          .select(
            // include deceased_type so we can separate Members vs Beneficiaries
            'death_notice_id, amount, status, paid_at, notice:death_notices(id,name,date_of_death,deceased_type)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId);

      final rows = List<Map<String, dynamic>>.from(res);

      final byNotice = <int, Map<String, dynamic>>{};
      for (final r in rows) {
        final dnId = r['death_notice_id'] as int?;
        if (dnId == null) continue;

        final notice = (r['notice'] as Map?)?.cast<String, dynamic>();
        final name = (notice?['name'] ?? 'Death Notice').toString();
        final dateStr = (notice?['date_of_death'] ?? '').toString();
        final dtype = (notice?['deceased_type'] ?? '').toString().isEmpty
            ? 'member'
            : (notice?['deceased_type']).toString().toLowerCase().trim();
        final amt = (r['amount'] is num)
            ? (r['amount'] as num).toDouble()
            : double.tryParse('${r['amount']}') ?? 0.0;
        final status = (r['status'] ?? '').toString().toLowerCase();

        final bucket = byNotice.putIfAbsent(dnId, () {
          return {
            'id': dnId,
            'name': name,
            'paid': 0.0,
            'goal': 0.0,
            'deadline': dateStr,
            'status': '', // computed later
            'progress': 0.0, // computed later
            'type': dtype, // NEW: member | beneficiary
          };
        });

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
      double totalPaid = 0, totalGoal = 0;

      for (final f in list) {
        final paid = (f['paid'] as double);
        final goal = (f['goal'] as double);
        final p = goal <= 0 ? 0.0 : (paid / goal).clamp(0.0, 1.0);
        f['progress'] = p;
        f['status'] = (paid >= goal && goal > 0)
            ? 'Completed'
            : 'Still Collecting...';

        totalPaid += paid;
        totalGoal += goal;
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
      if (list.isEmpty) {
        final advanceRes = await sb
            .from('payments')
            .select('amount, status')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .filter('death_notice_id', 'is', null);

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
        });
      }
      // --- END ADVANCE FUND LOGIC ---

      if (!mounted) return;
      setState(() {
        _funds = list;
        _totalPaid = totalPaid;
        _totalGoal = totalGoal;
        _loading = false;
      });
    } on PostgrestException {
      // ...existing code...
    } catch (e) {
      // ...existing code...
    }
  }

  Future<void> _onRefresh() => _load();

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
    return Scaffold(
      backgroundColor: kBg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E40AF),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E40AF).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.track_changes, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              const Text(
                'Manage Funds',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontFamily: 'Montserrat',
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _summaryHeader(),
                  const SizedBox(height: 12),
                  _filtersBar(),
                  const SizedBox(height: 8),
                  if (_visibleFunds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: const [
                          Icon(
                            Icons.inbox_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 10),
                          Text('No matching funds. Try a different filter.'),
                        ],
                      ),
                    )
                  else
                    ...List.generate(
                      _visibleFunds.length,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _fundCard(_visibleFunds[i]),
                      ),
                    ),
                ],
              ),
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
            'Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kSubtleText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _kpi('Collected', _currency(_totalPaid), color: Colors.teal),
              const SizedBox(width: 12),
              _kpi('Goal', _currency(_totalGoal), color: Colors.indigo),
              const SizedBox(width: 12),
              _kpi('Remaining', _currency(remaining), color: Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtersBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search
        TextField(
          decoration: InputDecoration(
            hintText: 'Search...',
            hintStyle: const TextStyle(fontWeight: FontWeight.w500),
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1E40AF)),
            ),
          ),
          onChanged: (v) => setState(() => _search = v.trim()),
        ),
        const SizedBox(height: 10),
        // Status segmented (All | Collecting | Completed)
        Center(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segChip('All', 'all'),
                _segChip('Collecting', 'collecting'),
                _segChip('Completed', 'completed'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Type segmented (Members | Beneficiaries)
        Center(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segChipType('Members', 'members'),
                _segChipType('Beneficiaries', 'beneficiaries'),
              ],
            ),
          ),
        ),
      ],
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

  // NEW: Section builder for grouped lists
  List<Widget> _typeSection({
    required String title,
    required List<Map<String, dynamic>> items,
  }) {
    if (items.isEmpty) return [];
    return [
      Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: kNeutralText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Text(
              '${items.length}',
              style: const TextStyle(
                color: Color(0xFF1E40AF),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...List.generate(
        items.length,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _fundCard(items[i]),
        ),
      ),
    ];
  }

  Widget _fundCard(Map<String, dynamic> fund) {
    final paid = (fund['paid'] as double?) ?? 0.0;
    final goal = (fund['goal'] as double?) ?? 0.0;
    final progress = (fund['progress'] as double?)?.clamp(0.0, 1.0) ?? 0.0;
    final deadline = (fund['deadline'] ?? '').toString();
    final completed = (fund['status'] ?? '').toString() == 'Completed';

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
                              ? Colors.teal.withOpacity(.12)
                              : Colors.orange.withOpacity(.12),
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
          color: color.withOpacity(.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(.9),
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

  Widget _statusChip(String label, String key) {
    final selected = _statusFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      labelStyle: TextStyle(
        color: selected ? Colors.white : kNeutralText,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: kPrimary,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? kPrimary : Colors.grey.shade300),
      onSelected: (_) => setState(() => _statusFilter = key),
    );
  }

  Future<void> _triggerPaymentCollection(
    int deathNoticeId,
    int dayungUnitId,
  ) async {
    // Fetch notice meta (always contains the member/parent user_id snapshot)
    Map<String, dynamic>? dn;
    try {
      final res = await sb
          .from('death_notices')
          .select('id,deceased_type,user_id,beneficiary_id')
          .eq('id', deathNoticeId)
          .single();
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
            .eq('death_notice_id', deathNoticeId)
            .eq('dayung_unit_id', dayungUnitId)
            .eq('user_id', excludedUserId);
      } catch (_) {}
    }

    // Get active members for the dayung
    final appsRes = await sb
        .from('applications')
        .select('user_id')
        .eq('dayung_unit_id', dayungUnitId)
        .eq('status', 'approved');
    final members = List<Map<String, dynamic>>.from(appsRes);

    // Already generated payments for this notice/dayung
    final existingRes = await sb
        .from('payments')
        .select('user_id')
        .eq('death_notice_id', deathNoticeId)
        .eq('dayung_unit_id', dayungUnitId);
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
        'amount': 1,
        'status': 'pending',
        'death_notice_id': deathNoticeId,
        'dayung_unit_id': dayungUnitId,
      });
    }

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new payments to create.')),
      );
      await _fetchAll();
      return;
    }

    try {
      await sb.from('payments').insert(rows);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${rows.length} payment(s).')),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Some payments already existed. New ones added.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
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
      final rows = await sb
          .from('payments')
          .select(
            'id, amount, status, paid_at, collected_by, '
            'user:users!payments_user_id_fkey(full_name), '
            'collector:users!payments_collected_by_fkey(full_name)',
          )
          .eq('death_notice_id', deathNoticeId)
          .eq('dayung_unit_id', dayungUnitId);

      final items = List<Map<String, dynamic>>.from(rows);

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
              .inFilter('id', missingCollectorIds);
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

      int paid = 0, unpaid = 0;
      double paidAmt = 0, totalAmt = 0;
      for (final r in items) {
        final s = (r['status'] ?? '').toString().toLowerCase();
        final amt = (r['amount'] is num)
            ? (r['amount'] as num).toDouble()
            : double.tryParse('${r['amount']}') ?? 0.0;
        totalAmt += amt;
        if (s == 'paid') {
          paid++;
          paidAmt += amt;
        } else {
          unpaid++;
        }
      }

      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ...existing header...
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 460),
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade300),
                        itemBuilder: (_, i) {
                          final r = items[i];
                          final s = (r['status'] ?? '')
                              .toString()
                              .toLowerCase();
                          final amt = (r['amount'] is num)
                              ? (r['amount'] as num).toDouble()
                              : double.tryParse('${r['amount']}') ?? 0.0;

                          final payerName =
                              (((r['user'] as Map?)?['full_name']) ?? '')
                                  .toString();
                          final title = payerName.isNotEmpty
                              ? payerName
                              : 'Payment #${r['id']}';

                          final paidAtStr = _fmtDateTime(r['paid_at']);
                          String collectorName =
                              (((r['collector'] as Map?)?['full_name']) ?? '')
                                  .toString();
                          if (collectorName.isEmpty &&
                              (r['collected_by'] ?? '').toString().isNotEmpty) {
                            collectorName =
                                collectorLookup[(r['collected_by'])
                                    .toString()] ??
                                '';
                          }

                          final subtitleText = s == 'paid'
                              ? 'Collected'
                                    '${paidAtStr.isNotEmpty ? ' on: $paidAtStr' : ''}'
                                    '${collectorName.isNotEmpty ? '\nCollected by: $collectorName' : ''}'
                              : 'Pending';

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: s == 'paid'
                                  ? Colors.green.withOpacity(.15)
                                  : Colors.orange.withOpacity(.15),
                              child: Icon(
                                s == 'paid'
                                    ? Icons.check
                                    : Icons.hourglass_empty,
                                color: s == 'paid'
                                    ? Colors.green[800]
                                    : Colors.orange[800],
                              ),
                            ),
                            title: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: kNeutralText,
                              ),
                            ),
                            subtitle: Text(
                              subtitleText,
                              style: const TextStyle(color: kSubtleText),
                            ),
                            trailing: Text(
                              '₱${amt.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: kNeutralText,
                              ),
                            ),
                          );
                        },
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

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(.95),
              fontWeight: FontWeight.w800,
            ),
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
      ..color = Colors.white.withOpacity(0.14)
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
