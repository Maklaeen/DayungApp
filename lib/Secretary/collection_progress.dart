import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/utils/theme_surface.dart';

class CollectionProgress extends StatefulWidget {
  final int dayungUnitId;
  const CollectionProgress({required this.dayungUnitId, super.key});

  @override
  State<CollectionProgress> createState() => _CollectionProgressState();
}

class _CollectionProgressState extends State<CollectionProgress> {
  double _paid = 0.0;
  double _total = 0.0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchSums();
  }

  Future<void> _fetchSums() async {
    setState(() => _loading = true);
    try {
      final sb = Supabase.instance.client;
      if (widget.dayungUnitId == 0) {
        setState(() {
          _paid = 0;
          _total = 0;
          _loading = false;
        });
        return;
      }

      final rows = await sb
          .from('claims')
          .select('total_paid_amount,total_payment_amount')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .ilike('status', 'approved');

      double paid = 0.0;
      double total = 0.0;
      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;
        final paidVal = m['total_paid_amount'];
        final totalVal = m['total_payment_amount'];
        if (paidVal is num) paid += paidVal.toDouble();
        if (totalVal is num) total += totalVal.toDouble();
      }

      setState(() {
        _paid = paid;
        _total = total;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _paid = 0;
          _total = 0;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_total > 0) ? (_paid / _total).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dayungSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dayungBorder(context)),
      ),
      child: _loading
          ? SizedBox(
              height: 64,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _total <= 0
                      ? 'No collection data'
                      : '${(pct * 100).toStringAsFixed(0)}% collected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: pct,
                  minHeight: 10,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.06),
                ),
                const SizedBox(height: 8),
                Text(
                  '₱${_paid.toStringAsFixed(0)} / ₱${_total.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }
}
