import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Color palette (from dashboard.dart)
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);

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
  List<Map<String, dynamic>> _contributions = [];

  @override
  void initState() {
    super.initState();
    _loadContributions();
  }

  Future<void> _loadContributions() async {
    setState(() => _loading = true);
    final rows = await _sb
        .from('payments')
        .select()
        .eq('dayung_unit_id', widget.dayungUnitId)
        .order('paid_at', ascending: false);
    setState(() {
      _contributions = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryLight))
          : _contributions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: kSubText, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'No contributions found.',
                    style: TextStyle(color: kSubText, fontSize: 18),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _contributions.length,
              itemBuilder: (context, idx) {
                final contrib = _contributions[idx];
                final paidAt =
                    contrib['paid_at']?.toString().split('T').first ?? '';
                final status = contrib['status']?.toString() ?? '';
                final amount = contrib['amount']?.toString() ?? '';
                final userId = contrib['user_id']?.toString() ?? '';
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 2,
                  color: kCardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: [
                        // Amount and Status
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '₱$amount',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: kPrimaryLight,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Status: $status',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: status == 'paid'
                                      ? kAccentDark
                                      : kSubText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'By: $userId',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: kText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Date
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Date',
                              style: TextStyle(fontSize: 13, color: kSubText),
                            ),
                            Text(
                              paidAt,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kPrimaryLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
