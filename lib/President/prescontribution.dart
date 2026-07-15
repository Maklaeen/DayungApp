import 'package:capstone_app/President/president_payment_page.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBg = Color(0xFFF8FAFC);
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryDark = Color(0xFF083366);
const kAccentDark = Color(0xFF059669);
const kWarn = Color(0xFFF59E0B);
const kDanger = Color(0xFFEF4444);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);

class PresidentContributionsPage extends StatefulWidget {
  final int dayungUnitId;

  const PresidentContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<PresidentContributionsPage> createState() =>
      _PresidentContributionsPageState();
}

class _PresidentContributionsPageState
    extends State<PresidentContributionsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String _search = '';
  List<Map<String, dynamic>> _payments = [];
  Map<String, String> _userNames = {};
  Map<String, Map<String, dynamic>> _claims = {};
  double _paidTotal = 0;
  double _pendingTotal = 0;
  int _paidCount = 0;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadContributions();
  }

  Future<void> _loadContributions() async {
    setState(() => _loading = true);

    try {
      final rows = await _sb
          .from('payments')
          .select(
            'id, user_id, userdeceased, claim_id, amount, status, created_at, paid_at, collected_by',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('created_at', ascending: false)
          .limit(300);

      final payments = List<Map<String, dynamic>>.from(rows);
      final userIds = <String>{};
      final claimIds = <String>{};

      for (final payment in payments) {
        final userId = (payment['user_id'] ?? '').toString();
        final collectorId = (payment['collected_by'] ?? '').toString();
        final deceasedId = (payment['userdeceased'] ?? '').toString();
        final claimId = (payment['claim_id'] ?? '').toString();
        if (userId.isNotEmpty) userIds.add(userId);
        if (collectorId.isNotEmpty) userIds.add(collectorId);
        if (deceasedId.isNotEmpty) userIds.add(deceasedId);
        if (claimId.isNotEmpty) claimIds.add(claimId);
      }

      final userNames = <String, String>{};
      if (userIds.isNotEmpty) {
        final users = await _sb
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds.toList());

        for (final user in List<Map<String, dynamic>>.from(users)) {
          final id = (user['id'] ?? '').toString();
          final name = (user['full_name'] ?? '').toString().trim();
          if (id.isNotEmpty && name.isNotEmpty) {
            userNames[id] = name;
          }
        }
      }

      final claims = <String, Map<String, dynamic>>{};
      if (claimIds.isNotEmpty) {
        final notices = await _sb
            .from('claims')
            .select('id, user_id, title, date_of_death, status')
            .inFilter('id', claimIds.toList());

        for (final notice in List<Map<String, dynamic>>.from(notices)) {
          final id = (notice['id'] ?? '').toString();
          if (id.isNotEmpty) {
            claims[id] = notice;
          }
        }
      }

      double paidTotal = 0;
      double pendingTotal = 0;
      int paidCount = 0;
      int pendingCount = 0;

      for (final payment in payments) {
        final amount = _amountOf(payment);
        final status = (payment['status'] ?? '').toString().toLowerCase();
        if (status == 'paid') {
          paidTotal += amount;
          paidCount++;
        } else {
          pendingTotal += amount;
          pendingCount++;
        }
      }

      if (!mounted) return;
      setState(() {
        _payments = payments;
        _userNames = userNames;
        _claims = claims;
        _paidTotal = paidTotal;
        _pendingTotal = pendingTotal;
        _paidCount = paidCount;
        _pendingCount = pendingCount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load contributions: $e')),
      );
    }
  }

  double _amountOf(Map<String, dynamic> payment) {
    final value = payment['amount'];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String _memberName(Map<String, dynamic> payment) {
    final userId = (payment['user_id'] ?? '').toString();
    return _userNames[userId] ?? 'Unknown member';
  }

  String _collectorName(Map<String, dynamic> payment) {
    final collectorId = (payment['collected_by'] ?? '').toString();
    if (collectorId.isEmpty) return 'Not assigned';
    return _userNames[collectorId] ?? 'Unknown collector';
  }

  String _deceasedName(Map<String, dynamic> payment) {
    final claimId = (payment['claim_id'] ?? '').toString();
    final deceasedId = (payment['userdeceased'] ?? '').toString();
    if (claimId.isNotEmpty && _claims.containsKey(claimId)) {
      final claim = _claims[claimId]!;
      final claimName = (claim['title'] ?? '').toString().trim();
      if (claimName.isNotEmpty) return claimName;
    }
    if (deceasedId.isNotEmpty) {
      return _userNames[deceasedId] ?? 'Unknown deceased';
    }
    return 'No deceased linked';
  }

  String _dateOf(Map<String, dynamic> payment) {
    final raw = (payment['paid_at'] ?? payment['created_at'] ?? '').toString();
    if (raw.isEmpty) return 'No date';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.split('T').first;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return kAccentDark;
      case 'pending':
      case 'unpaid':
        return kWarn;
      default:
        return kDanger;
    }
  }

  List<Map<String, dynamic>> get _filteredPayments {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _payments;

    return _payments.where((payment) {
      return _memberName(payment).toLowerCase().contains(query) ||
          _collectorName(payment).toLowerCase().contains(query) ||
          _deceasedName(payment).toLowerCase().contains(query) ||
          (payment['status'] ?? '').toString().toLowerCase().contains(query) ||
          _dateOf(payment).toLowerCase().contains(query);
    }).toList();
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: kText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kSubText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentShortcutCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryDark, kPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contribution Overview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open your payment page to review your pending records and choose cash or GCash.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PresidentPaymentPage(dayungUnitId: widget.dayungUnitId),
                ),
              ).then((_) => _loadContributions());
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Open Payment Page'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kText,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: dayungPageBackground(context),
      child: _loading
          ? const DayungPageSkeleton(
              layout: DayungSkeletonLayout.list,
              itemCount: 5,
            )
          : RefreshIndicator(
              onRefresh: _loadContributions,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                children: [
                  _paymentShortcutCard(),
                  Row(
                    children: [
                      _summaryCard(
                        title: 'Paid',
                        value: '₱${_paidTotal.toStringAsFixed(0)}',
                        subtitle: '$_paidCount records',
                        color: kAccentDark,
                        icon: Icons.check_circle_rounded,
                      ),
                      const SizedBox(width: 12),
                      _summaryCard(
                        title: 'Pending',
                        value: '₱${_pendingTotal.toStringAsFixed(0)}',
                        subtitle: '$_pendingCount records',
                        color: kWarn,
                        icon: Icons.schedule_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search member, deceased, collector, or status',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                  const SizedBox(height: 16),
                  if (_filteredPayments.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: kSubText,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _payments.isEmpty
                                  ? 'No contributions found.'
                                  : 'No contribution matches your search.',
                              style: const TextStyle(
                                color: kSubText,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._filteredPayments.map((payment) {
                      final status = (payment['status'] ?? 'unknown')
                          .toString();
                      final amount = _amountOf(payment);

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 1,
                        color: kCardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: _statusColor(
                                        status,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      status.toLowerCase() == 'paid'
                                          ? Icons.check_circle_rounded
                                          : Icons.pending_actions_rounded,
                                      color: _statusColor(status),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '₱${amount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            color: kPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _memberName(payment),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: kText,
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
                                      color: _statusColor(
                                        status,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        color: _statusColor(status),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _infoChip(
                                    Icons.person_rounded,
                                    'Member: ${_memberName(payment)}',
                                  ),
                                  _infoChip(
                                    Icons.volunteer_activism_rounded,
                                    'Deceased: ${_deceasedName(payment)}',
                                  ),
                                  _infoChip(
                                    Icons.badge_rounded,
                                    'Collector: ${_collectorName(payment)}',
                                  ),
                                  _infoChip(
                                    Icons.calendar_today_rounded,
                                    _dateOf(payment),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
