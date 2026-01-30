// filepath: lib/Collector/collect_cash.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);

class CollectCashPage extends StatefulWidget {
  final int dayungUnitId;
  const CollectCashPage({super.key, required this.dayungUnitId});

  @override
  State<CollectCashPage> createState() => _CollectCashPageState();
}

class _CollectCashPageState extends State<CollectCashPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _approvedMembers = [];
  List<Map<String, dynamic>> _setAmounts = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _deceasedUsers = [];
  Map<String, dynamic>? _selectedDeceased;
  String _memberSearch = '';
  String _deceasedSearch = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadSetAmounts();
    _loadPayments();
  }

  Future<void> _loadSetAmounts() async {
    try {
      final res = await sb
          .from('set_amount')
          .select('id, userdeceased, amount')
          .eq('dayung_unit_id', widget.dayungUnitId);
      setState(() {
        _setAmounts = List<Map<String, dynamic>>.from(res);
      });
      await _loadDeceasedUsers();
    } catch (e) {}
  }

  Future<void> _loadDeceasedUsers() async {
    try {
      final ids = _setAmounts
          .map((a) => a['userdeceased'])
          .where((id) => id != null)
          .toSet()
          .toList();
      if (ids.isEmpty) {
        setState(() {
          _deceasedUsers = [];
        });
        return;
      }
      final usersRes =
          await sb.from('users').select('id, full_name').inFilter('id', ids);
      setState(() {
        _deceasedUsers = List<Map<String, dynamic>>.from(usersRes);
      });
    } catch (e) {}
  }

  Future<void> _loadPayments() async {
    try {
      final res = await sb
          .from('payments')
          .select('*')
          .eq('dayung_unit_id', widget.dayungUnitId);
      setState(() {
        _payments = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appsRes = await sb
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');
      final userIds = List<Map<String, dynamic>>.from(appsRes)
          .map((a) => a['user_id'])
          .toList();

      List<Map<String, dynamic>> members = [];
      if (userIds.isNotEmpty) {
        final usersRes = await sb
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds);
        members = List<Map<String, dynamic>>.from(usersRes);
      }

      setState(() {
        _approvedMembers = members;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }
// ...existing code...
  Future<void> _savePayment(
    String userId,
    double amount,
    String setAmountId,
  ) async {
    try {
      final collectorId = sb.auth.currentUser?.id;
      if (collectorId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not logged in as collector.')),
        );
        return;
      }

      final setAmount = _setAmounts.firstWhere(
        (a) => a['id'].toString() == setAmountId,
        orElse: () => <String, dynamic>{},
      );

      final userDeceased = setAmount['userdeceased'].toString();
      final now = DateTime.now().toUtc().toIso8601String();

      // DEBUG: Print all payment records and filter values
      print('DEBUG: userId: $userId');
      print('DEBUG: userDeceased: $userDeceased');
      print('DEBUG: dayungUnitId: ${widget.dayungUnitId}');
      print('DEBUG: Payments list:');
      print('DEBUG: setAmount: $setAmount');
print('DEBUG: _selectedDeceased: $_selectedDeceased');
      for (var p in _payments) {
        print('  id=${p['id']}, user_id=${p['user_id']}, userdeceased=${p['userdeceased']}, dayung_unit_id=${p['dayung_unit_id']}, status=${p['status']}');
      }

      // Make sure all comparisons are string-based
      final unpaidPayments = _payments.where(
        (p) =>
            p['user_id'].toString() == userId.toString() &&
            p['userdeceased'].toString() == userDeceased &&
            p['dayung_unit_id'].toString() == widget.dayungUnitId.toString() &&
            p['status'].toString() != 'paid',
      ).toList();

      print('DEBUG: unpaidPayments found: ${unpaidPayments.length}');

      final payment = unpaidPayments.isNotEmpty ? unpaidPayments.first : null;

      if (payment == null) {
        print('DEBUG: No unpaid payment found for this member.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No unpaid payment found for this member.')),
        );
        return;
      }

      // Update the payment record
      await sb.from('payments').update({
        'status': 'paid',
        'paid_at': now,
        'collected_by': collectorId,
        'datepaidamount': now,
      }).eq('id', payment['id']);

      await _loadPayments();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment updated to paid!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update payment: $e')),
      );
    }
  }
// ...existing code...



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_selectedDeceased != null) {
                          _selectedDeceased = null;
                        } else {
                          Navigator.of(context).pop();
                        }
                      });
                    },
                  ),
                  const Icon(
                    Icons.payments_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Collect Cash Payments',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: kAccent),
                    )
                  : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style:
                                const TextStyle(color: Colors.red, fontSize: 18),
                          ),
                        )
                      : _selectedDeceased == null
                          // STEP 1: choose deceased
                          ? (_deceasedUsers.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.info_outline,
                                          color: kSubText, size: 48),
                                      SizedBox(height: 16),
                                      Text(
                                        'No set amounts created.',
                                        style: TextStyle(
                                          fontSize: 22,
                                          color: kSubText,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: ListView(
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(
                                            bottom: 12.0, left: 4.0),
                                        child: Text(
                                          'USER DECEASED',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: kAccent,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        decoration: const InputDecoration(
                                          hintText: 'SEARCH',
                                          prefixIcon: Icon(Icons.search),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(
                                                  vertical: 12,
                                                  horizontal: 16),
                                        ),
                                        onChanged: (value) {
                                          setState(() {
                                            _deceasedSearch = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      Builder(
                                        builder: (context) {
                                          final filteredDeceased = _deceasedUsers.where((d) {
                                            if (_deceasedSearch.isEmpty) return true;
                                            final name = (d['full_name'] ?? '').toString().toLowerCase();
                                            return name.contains(_deceasedSearch.toLowerCase());
                                          }).toList();

                                          return Column(
                                            children: [
                                              ...filteredDeceased.map((d) {
                                                final sa = _setAmounts.firstWhere(
                                                  (a) => a['userdeceased'] == d['id'],
                                                  orElse: () => <String, dynamic>{},
                                                );
                                                return Card(
                                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                                  elevation: 2,
                                                  color: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(16),
                                                    side: BorderSide(
                                                      color: kAccent.withOpacity(0.10),
                                                    ),
                                                  ),
                                                  child: ListTile(
                                                    title: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            d['full_name'] ?? 'Unknown',
                                                            style: const TextStyle(
                                                              fontSize: 20,
                                                              fontWeight: FontWeight.w800,
                                                              color: kText,
                                                            ),
                                                          ),
                                                        ),
                                                        Builder(
                                                          builder: (context) {
                                                            final totalMembers = _approvedMembers.length;
                                                            final paidCount = _payments.where((p) =>
                                                              p['userdeceased'] == d['id'] && p['status'] == 'paid'
                                                            ).length;
                                                            if (totalMembers == 0) {
                                                              return const SizedBox();
                                                            }
                                                            if (paidCount == totalMembers) {
                                                              return Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.green[100],
                                                                  borderRadius: BorderRadius.circular(12),
                                                                ),
                                                                child: const Text(
                                                                  'PAID',
                                                                  style: TextStyle(
                                                                    color: Colors.green,
                                                                    fontWeight: FontWeight.bold,
                                                                    fontSize: 14,
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                            return Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                              decoration: BoxDecoration(
                                                                color: kAccent.withOpacity(0.08),
                                                                borderRadius: BorderRadius.circular(12),
                                                              ),
                                                              child: Text(
                                                                '$paidCount/$totalMembers',
                                                                style: const TextStyle(
                                                                  color: kAccent,
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 14,
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                    subtitle: sa.isNotEmpty
                                                        ? Text(
                                                            'Required: ₱${sa['amount']}',
                                                            style: const TextStyle(color: kSubText),
                                                          )
                                                        : const Text(
                                                            'No amount set',
                                                            style: TextStyle(color: kSubText),
                                                          ),
                                                    trailing: const Icon(
                                                      Icons.arrow_forward_ios,
                                                      color: kAccent,
                                                    ),
                                                    onTap: () {
                                                      setState(() {
                                                        _selectedDeceased = d;
                                                      });
                                                    },
                                                  ),
                                                );
                                              }),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ))
                          // STEP 2: members for selected deceased
                          : (_approvedMembers.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.info_outline,
                                          color: kSubText, size: 48),
                                      SizedBox(height: 16),
                                      Text(
                                        'No approved members assigned.',
                                        style: TextStyle(
                                          fontSize: 22,
                                          color: kSubText,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Deceased Member: ${_selectedDeceased?['full_name'] ?? 'Deceased'}',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: kAccent,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      // Search
                                      TextField(
                                        decoration: const InputDecoration(
                                          hintText: 'SEARCH',
                                          prefixIcon: Icon(Icons.search),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(
                                                  vertical: 12,
                                                  horizontal: 16),
                                        ),
                                        onChanged: (value) {
                                          setState(() {
                                            _memberSearch = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      Expanded(
                                        child: ListView(
                                          children: [
                                            Builder(
                                              builder: (context) {
                                                // filter by search
                                                final filteredMembers =
                                                    _approvedMembers
                                                        .where((member) =>
                                                            _memberSearch
                                                                .isEmpty ||
                                                            (member['full_name'] ??
                                                                    '')
                                                                .toLowerCase()
                                                                .contains(_memberSearch
                                                                    .toLowerCase()))
                                                        .toList();

                                                // sort: unpaid first, then paid, then by name
                                                filteredMembers
                                                    .sort((a, b) {
                                                  final aPaid =
                                                      _payments.any((p) =>
                                                          p['user_id'] ==
                                                              a['id'] &&
                                                          p['userdeceased'] ==
                                                              _selectedDeceased?[
                                                                  'id'] &&
                                                          p['status'] ==
                                                              'paid');
                                                  final bPaid =
                                                      _payments.any((p) =>
                                                          p['user_id'] ==
                                                              b['id'] &&
                                                          p['userdeceased'] ==
                                                              _selectedDeceased?[
                                                                  'id'] &&
                                                          p['status'] ==
                                                              'paid');

                                                  if (aPaid != bPaid) {
                                                    // unpaid (false) first
                                                    return aPaid ? 1 : -1;
                                                  }
                                                  return (a['full_name'] ?? '')
                                                      .toString()
                                                      .toLowerCase()
                                                      .compareTo(
                                                          (b['full_name'] ?? '')
                                                              .toString()
                                                              .toLowerCase());
                                                });

                                                return Column(
                                                  children: [
                                                    ...filteredMembers.map(
                                                        (member) {
                                                      final sa = _setAmounts
                                                          .firstWhere(
                                                        (a) =>
                                                            a['userdeceased'] ==
                                                            _selectedDeceased?[
                                                                'id'],
                                                        orElse: () =>
                                                            <String,
                                                                dynamic>{},
                                                      );
                                                      final isPaid =
                                                          _payments.any((p) =>
                                                              p['user_id'] ==
                                                                  member[
                                                                      'id'] &&
                                                              p['userdeceased'] ==
                                                                  _selectedDeceased?[
                                                                      'id'] &&
                                                              p['status'] ==
                                                                  'paid');

                                                      return Card(
                                                        margin: const EdgeInsets
                                                            .symmetric(
                                                                vertical: 8),
                                                        elevation: 2,
                                                        color: Colors.white,
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      16),
                                                          side: BorderSide(
                                                            color: kAccent
                                                                .withOpacity(
                                                                    0.10),
                                                          ),
                                                        ),
                                                        child: ListTile(
                                                          title: Text(
                                                            member['full_name'] ??
                                                                'Member',
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 20,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: kText,
                                                            ),
                                                          ),
                                                          subtitle: isPaid
                                                              ? const Text(
                                                                  'Paid',
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .green,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                )
                                                              : Text(
                                                                  sa.isNotEmpty
                                                                      ? 'Required: ₱${sa['amount']}'
                                                                      : 'No amount set',
                                                                  style: const TextStyle(
                                                                      color:
                                                                          kSubText),
                                                              
      ),
                                                          onTap: isPaid ||
                                                                  sa.isEmpty
                                                              ? null
                                                              : () async {
                                                                  final controller =
                                                                      TextEditingController();
                                                                  String?
                                                                      errorText;
                                                                  final requiredAmount = (sa['amount']
                                                                              is int)
                                                                      ? (sa['amount']
                                                                              as int)
                                                                          .toDouble()
                                                                      : (sa['amount']
                                                                              is double)
                                                                          ? sa['amount']
                                                                              as double
                                                                          : double.tryParse(sa['amount']
                                                                                  .toString()) ??
                                                                              0.0;

                                                                  double?
                                                                      amount =
                                                                      await showDialog<
                                                                          double>(
                                                                    context:
                                                                        context,
                                                                    builder:
                                                                        (context) {
                                                                      return StatefulBuilder(
                                                                        builder: (context,
                                                                                setState) =>
                                                                            AlertDialog(
                                                                          title:
                                                                              Text('Set Amount for ${member['full_name']}'),
                                                                          content:
                                                                              Column(
                                                                            mainAxisSize:
                                                                                MainAxisSize.min,
                                                                            children: [
                                                                              TextField(
                                                                                controller: controller,
                                                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                                                decoration: InputDecoration(
                                                                                  labelText: 'Amount (₱)',
                                                                                  errorText: errorText,
                                                                                ),
                                                                              ),
                                                                              const SizedBox(height: 8),
                                                                              Text(
                                                                                'Required: ₱${sa['amount']}',
                                                                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          actions: [
                                                                            TextButton(
                                                                              onPressed: () => Navigator.pop(context),
                                                                              child: const Text('Cancel'),
                                                                            ),
                                                                            TextButton(
                                                                              onPressed: () {
                                                                                final value = double.tryParse(controller.text);
                                                                                if (value == requiredAmount) {
                                                                                  Navigator.pop(context, value);
                                                                                } else {
                                                                                  setState(() {
                                                                                    errorText = 'Amount must be exactly ₱$requiredAmount';
                                                                                  });
                                                                                }
                                                                              },
                                                                              child: const Text('Save'),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      );
                                                                    },
                                                                  );

                                                                  if (amount !=
                                                                      null) {
                                                                    await _savePayment(
                                                                      member['id']
                                                                          .toString(),
                                                                      amount,
                                                                      sa['id']
                                                                          .toString(),
                                                                    );
                                                                    setState(
                                                                        () {});
                                                                  }
                                                                },
                                                        ),
                                                      );
                                                    }),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
            ),
          ],
        ),
      ),
    );
  }
}