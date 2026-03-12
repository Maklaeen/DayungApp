import 'package:capstone_app/President/president_payment_page.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
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
  Map<String, String> _userNames = {};

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

    final contributions = List<Map<String, dynamic>>.from(rows);
    final userIds = contributions
        .map((row) => (row['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final userNames = <String, String>{};
    if (userIds.isNotEmpty) {
      final users = await _sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', userIds);
      for (final user in List<Map<String, dynamic>>.from(users)) {
        final id = (user['id'] ?? '').toString();
        final fullName = (user['full_name'] ?? '').toString().trim();
        if (id.isNotEmpty && fullName.isNotEmpty) {
          userNames[id] = fullName;
        }
      }
    }

    setState(() {
      _contributions = contributions;
      _userNames = userNames;
      _loading = false;
    });
  }

  Widget _paymentShortcutCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF083366), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
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
                      PresidentPaymentPage(dayungUnitId: widget.dayungUnitId),
                ),
              ).then((_) => _loadContributions());
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Open Payment Page'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kPrimaryLight,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
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
                  if (_contributions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 80),
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
                      ),
                    )
                  else
                    ..._contributions.map((contrib) {
                      final paidAt =
                          contrib['paid_at']?.toString().split('T').first ?? '';
                      final status = contrib['status']?.toString() ?? '';
                      final amount = contrib['amount']?.toString() ?? '';
                      final userId = contrib['user_id']?.toString() ?? '';
                      final memberName = _userNames[userId] ?? 'Unknown member';
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
                                      'Member: $memberName',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: kText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'Date',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: kSubText,
                                    ),
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
                    }),
                ],
              ),
            ),
    );
  }
}
