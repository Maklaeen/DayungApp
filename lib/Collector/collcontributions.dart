import 'package:capstone_app/Collector/collector_payment_page.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CollectorContributionsPage extends StatefulWidget {
  final int dayungUnitId;
  const CollectorContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectorContributionsPage> createState() =>
      _CollectorContributionsPageState();
}

class _CollectorContributionsPageState
    extends State<CollectorContributionsPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _rows = [];
          _total = 0;
          _loading = false;
        });
        return;
      }

      final res = await sb
          .from('payments')
          .select(
            'id, amount, status, paid_at, created_at, user_id, dayung_unit_id, collected_by, death_notice_id, deceased_name',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'paid')
          .eq('collected_by', uid)
          .order('paid_at', ascending: false)
          .limit(200);

      final rows = List<Map<String, dynamic>>.from(res);
      double total = 0;
      for (final r in rows) {
        final a = r['amount'];
        total += a is num ? a.toDouble() : double.tryParse('$a') ?? 0.0;
      }
      setState(() {
        _rows = rows;
        _total = total;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _rows = [];
        _total = 0;
        _loading = false;
      });
    }
  }

  double _amountOf(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0.0;
  }

  String _dateOf(Map<String, dynamic> row) {
    final raw = (row['paid_at'] ?? row['created_at'] ?? '').toString();
    if (raw.isEmpty) return 'No date';
    return raw.split('T').first;
  }

  String _deceasedNameOf(Map<String, dynamic> row) {
    final name = (row['deceased_name'] ?? '').toString().trim();
    return name.isEmpty ? 'No deceased name' : name;
  }

  Widget _shortcutCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF083366), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Need to settle your own contribution?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
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
                      CollectorPaymentPage(dayungUnitId: widget.dayungUnitId),
                ),
              ).then((_) => _load());
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Open Payment Page'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0D47A1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> row) {
    final amount = _amountOf(row['amount']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _deceasedNameOf(row),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'PAID',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Date paid: ${_dateOf(row)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D47A1).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.payments_rounded,
              color: Color(0xFF0D47A1),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₱${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_rows.length} paid payment${_rows.length == 1 ? '' : 's'} in this dayung unit',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: Color(0xFF4B5563),
          ),
          SizedBox(height: 12),
          Text(
            'No paid payments collected by this account in the selected dayung unit.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: _loading
          ? const DayungPageSkeleton(
              layout: DayungSkeletonLayout.dashboard,
              itemCount: 4,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _shortcutCard(),
                  const SizedBox(height: 16),
                  _summaryCard(),
                  const SizedBox(height: 16),
                  if (_rows.isEmpty)
                    _emptyState()
                  else
                    ..._rows.map(_paymentTile),
                ],
              ),
            ),
    );
  }
}
