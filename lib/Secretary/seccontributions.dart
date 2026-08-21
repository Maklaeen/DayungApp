import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/Secretary/secretary_payment_page.dart';
import 'package:capstone_app/utils/theme_surface.dart';

// Additional colors for secretary contributions specific styling (new UI)
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kDanger = Color(0xFFEF4444);
const kPaid = Color(0xFF2E7D32);
const kPending = Color(0xFFF57C00);
const double kEdge = 16;

class SecretaryContributionsPage extends StatefulWidget {
  final int dayungUnitId;
  const SecretaryContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<SecretaryContributionsPage> createState() =>
      _SecretaryContributionsPageState();
}

class _SecretaryContributionsPageState
    extends State<SecretaryContributionsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic> _users = {};

  @override
  void initState() {
    super.initState();
    _fetchContributions();
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

  Future<void> _fetchContributions() async {
    if (mounted) setState(() => _loading = true);
    final sb = Supabase.instance.client;
    try {
      final currentUser = sb.auth.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        setState(() {
          _payments = [];
          _users = {};
          _loading = false;
        });
        return;
      }

      final payments = await sb
          .from('payments')
          .select(
            'id, user_id, amount, status, paid_at, collected_by, userdeceased, deceased_name, '
            'collector:users!payments_collected_by_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('user_id', currentUser.id)
          .order('paid_at', ascending: false);

      final deceasedIds = payments
          .map((p) => p['userdeceased'])
          .where((v) => v != null && v.toString().isNotEmpty)
          .map((v) => v.toString())
          .toSet()
          .toList();

      final usersRes = deceasedIds.isEmpty
          ? <dynamic>[]
          : await sb
                .from('users')
                .select('id, full_name')
                .inFilter('id', deceasedIds);

      final usersMap = <String, dynamic>{
        for (var u in usersRes) u['id'].toString(): u['full_name'] ?? 'Unknown',
      };

      if (!mounted) return;
      setState(() {
        _payments = List<Map<String, dynamic>>.from(payments);
        _users = usersMap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading contributions: $e')),
      );
    }
  }

  int _countByStatus(String status) {
    return _payments.where((p) {
      final value = p['status']?.toString().toLowerCase() ?? '';
      if (status.toLowerCase() == 'pending') {
        return value == 'pending' || value == 'unpaid';
      }
      return value == status.toLowerCase();
    }).length;
  }

  // Widget _paymentShortcutCard() {
  //   return Container(
  //     margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
  //     padding: const EdgeInsets.all(18),
  //     decoration: BoxDecoration(
  //       gradient: const LinearGradient(
  //         colors: [Color(0xFF083366), Color(0xFF0D47A1)],
  //         begin: Alignment.topLeft,
  //         end: Alignment.bottomRight,
  //       ),
  //       borderRadius: BorderRadius.circular(18),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         const SizedBox(height: 8),
  //         const Text(
  //           'Open your payment page to review your pending records and choose cash or GCash.',
  //           style: TextStyle(
  //             color: Colors.white70,
  //             fontSize: 14,
  //             fontWeight: FontWeight.w600,
  //           ),
  //         ),
  //         const SizedBox(height: 14),
  //         ElevatedButton.icon(
  //           onPressed: () {
  //             Navigator.push(
  //               context,
  //               MaterialPageRoute(
  //                 builder: (_) =>
  //                     SecretaryPaymentPage(dayungUnitId: widget.dayungUnitId),
  //               ),
  //             ).then((_) => _fetchContributions());
  //           },
  //           icon: const Icon(Icons.arrow_forward_rounded),
  //           label: const Text('Open Payment Page'),
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.white,
  //             foregroundColor: kPrimary,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [dayungPageBackground(context), dayungSoftSurface(context)],
          ),
        ),
        child: Column(
          children: [
            // _paymentShortcutCard(),
            // Stats Overview Cards (new UI)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: kSuccess.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: kSuccess,
                              size: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Paid',
                            style: TextStyle(
                              color: kSubText,
                              fontSize: 10,
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${_countByStatus('paid')}',
                            style: const TextStyle(
                              color: kText,
                              fontSize: 14,
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: kPending.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              color: kPending,
                              size: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Pending',
                            style: TextStyle(
                              color: kSubText,
                              fontSize: 10,
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${_countByStatus('pending')}',
                            style: const TextStyle(
                              color: kText,
                              fontSize: 14,
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _loading
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: kBorderColor, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: kPrimary,
                              strokeWidth: 3,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Loading contributions...',
                              style: TextStyle(
                                color: kSubText,
                                fontSize: 16,
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : (_payments.isEmpty
                        ? Center(
                            child: Container(
                              margin: const EdgeInsets.all(20),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: kCardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: kBorderColor,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 15,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_rounded,
                                    size: 48,
                                    color: kSubText,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No contributions found',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: kText,
                                      fontFamily: 'Montserrat',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'No contributions have been made yet',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: kSubText,
                                      fontFamily: 'OpenSans',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: RefreshIndicator(
                              onRefresh: _fetchContributions,
                              child: ListView.separated(
                                itemCount: _payments.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final p = _payments[i];
                                  final userDeceasedId =
                                      (p['userdeceased'] ?? '').toString();
                                  final userDeceased =
                                      (p['deceased_name']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true)
                                      ? p['deceased_name'].toString()
                                      : (userDeceasedId.isNotEmpty
                                            ? _users[userDeceasedId] ??
                                                  userDeceasedId
                                            : 'Membership Payment');
                                  final paidAtStr = _fmtDateTime(p['paid_at']);
                                  final paid =
                                      (p['status']?.toString().toLowerCase() ==
                                      'paid');

                                  return Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: kCardBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: kBorderColor,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.03,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: paid
                                                    ? kPaid.withValues(
                                                        alpha: 0.1,
                                                      )
                                                    : kPending.withValues(
                                                        alpha: 0.1,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                paid
                                                    ? Icons.check_circle_rounded
                                                    : Icons.schedule_rounded,
                                                color: paid ? kPaid : kPending,
                                                size: 18,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    userDeceased,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: kText,
                                                      fontFamily: 'Montserrat',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: paid
                                                    ? kPaid.withValues(
                                                        alpha: 0.1,
                                                      )
                                                    : kPending.withValues(
                                                        alpha: 0.1,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: paid
                                                      ? kPaid
                                                      : kPending,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                paid ? 'PAID' : 'PENDING',
                                                style: TextStyle(
                                                  color: paid
                                                      ? kPaid
                                                      : kPending,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 10,
                                                  letterSpacing: 0.5,
                                                  fontFamily: 'Montserrat',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Amount: ₱${p['amount']}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: paid ? kPaid : kPending,
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'Montserrat',
                                              ),
                                            ),
                                            if (paidAtStr.isNotEmpty)
                                              Text(
                                                'Paid: $paidAtStr',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: kSubText,
                                                  fontFamily: 'OpenSans',
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          )),
            ),
          ],
        ),
      ),
    );
  }
}
