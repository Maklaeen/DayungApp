import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPageBg = Color(0xFFF8FAFC);
const Color _kHeaderGradientStart = Color(0xFF083366);
const Color _kHeaderGradientEnd = Color(0xFF0D47A1);
const Color _kCard = Colors.white;
const Color _kBorder = Color(0xFFE5E7EB);
const Color _kText = Color(0xFF111827);
const Color _kPrimary = Color(0xFF0D47A1);

class TreasurerPaymentPage extends StatefulWidget {
  final int dayungUnitId;

  const TreasurerPaymentPage({super.key, required this.dayungUnitId});

  @override
  State<TreasurerPaymentPage> createState() => _TreasurerPaymentPageState();
}

class _TreasurerPaymentPageState extends State<TreasurerPaymentPage> {
  final sb = Supabase.instance.client;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _paymentType = 'gcash';
  String? _selectedUserId;
  List<Map<String, dynamic>> _paymentRows = [];
  List<Map<String, dynamic>> _userOptions = [];
  final Map<String, String> _userNameById = {};

  @override
  void initState() {
    super.initState();
    _loadPayments();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final rows = await sb
          .from('users')
          .select('id, full_name')
          .order('full_name', ascending: true);

      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(rows ?? []);
      final mappedUsers = <String, String>{};
      for (final u in list) {
        final userId = (u['id'] ?? '').toString();
        final fullName = (u['full_name'] ?? '').toString().trim();
        if (userId.isNotEmpty) {
          mappedUsers[userId] = fullName;
        }
      }

      if (!mounted) return;
      setState(() {
        _userOptions = list
            .map(
              (u) => {
                'user_id': (u['id'] ?? '').toString(),
                'full_name': (u['full_name'] ?? '').toString(),
              },
            )
            .toList();
        _userNameById.clear();
        _userNameById.addAll(mappedUsers);
      });
    } catch (e) {
      // Don't block the page for users failing to load; keep payments working.
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadPayments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await sb
          .from('advance_payments')
          .select(
            'id, user_id, amount, type, created_at, added_by, dayung_unit_id, users!advance_payments_user_id_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        final list = (rows as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _paymentRows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load payment records: $e';
      });
    }
  }

  String _fullNameForRow(Map<String, dynamic> row) {
    final userData = row['users'];
    if (userData is Map<String, dynamic>) {
      final name = (userData['full_name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    return (row['user_id'] ?? 'User').toString();
  }

  String _addedByNameForRow(Map<String, dynamic> row) {
    final addedBy = (row['added_by'] ?? '').toString().trim();
    if (addedBy.isEmpty) return 'Unknown';
    return _userNameById[addedBy] ?? addedBy;
  }

  String _amountLabel(dynamic amount) {
    final value = double.tryParse(amount?.toString() ?? '') ?? 0.0;
    return '₱${value.toStringAsFixed(2)}';
  }

  String _dateLabel(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return 'No date';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return DateFormat('MMM d, yyyy h:mm a').format(local);
  }

  List<Map<String, dynamic>> get _nameOptions {
    final unique = <String, Map<String, dynamic>>{};
    for (final row in _paymentRows) {
      final userId = (row['user_id'] ?? '').toString();
      final fullName = _fullNameForRow(row);
      if (userId.isEmpty) continue;
      unique.putIfAbsent(
        userId,
        () => {'user_id': userId, 'full_name': fullName},
      );
    }
    return unique.values.toList();
  }

  Future<void> _handlePay() async {
    final userId = _selectedUserId;
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a user name first.')),
      );
      return;
    }

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid advance amount.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final memberName = _nameController.text.trim();
        return AlertDialog(
          title: const Text('Confirm payment'),
          content: Text(
            'Record an advance payment of ${_amountLabel(amount)} for ${memberName.isNotEmpty ? memberName : 'this member'}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _saving = true);

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await sb.from('advance_payments').insert({
        'user_id': userId,
        'amount': amount,
        'type': _paymentType.toLowerCase(),
        'created_at': now,
        'added_by': sb.auth.currentUser?.id,
        'dayung_unit_id': widget.dayungUnitId,
        'has_remaining': true,
      });

      if (!mounted) return;
      _nameController.clear();
      _amountController.clear();
      _selectedUserId = null;
      await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to record payment: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kHeaderGradientStart, _kHeaderGradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Back',
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Transaction',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPayments,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: _kCard,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _kBorder),
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
                                const Text(
                                  'Payment Record',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: _kText,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Autocomplete<Map<String, dynamic>>(
                                  optionsBuilder: (TextEditingValue value) {
                                    final query = value.text
                                        .trim()
                                        .toLowerCase();
                                    final options = _userOptions;
                                    if (query.isEmpty) return options;
                                    return options.where((member) {
                                      final name = (member['full_name'] ?? '')
                                          .toString();
                                      return name.toLowerCase().contains(query);
                                    });
                                  },
                                  displayStringForOption: (option) =>
                                      (option['full_name'] ?? '').toString(),
                                  onSelected: (option) {
                                    final userId = (option['user_id'] ?? '')
                                        .toString();
                                    setState(() {
                                      _selectedUserId = userId;
                                      _nameController.text =
                                          (option['full_name'] ?? '')
                                              .toString();
                                    });
                                  },
                                  fieldViewBuilder:
                                      (
                                        context,
                                        fieldTextEditingController,
                                        focusNode,
                                        onFieldSubmitted,
                                      ) {
                                        fieldTextEditingController.text =
                                            _nameController.text;
                                        return TextFormField(
                                          controller:
                                              fieldTextEditingController,
                                          focusNode: focusNode,
                                          onFieldSubmitted: (_) =>
                                              onFieldSubmitted(),
                                          decoration: const InputDecoration(
                                            labelText: 'NAME',
                                            hintText: 'Select member name',
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(
                                              Icons.person_outline_rounded,
                                            ),
                                          ),
                                          onChanged: (value) {
                                            _nameController.text = value;
                                            _selectedUserId = null;
                                          },
                                        );
                                      },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _amountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Advance Amount',
                                    hintText: '0.00',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(
                                      Icons.attach_money_rounded,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<String>(
                                  initialValue: _paymentType,
                                  decoration: const InputDecoration(
                                    labelText: 'Type',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.payment_rounded),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'gcash',
                                      child: Text('GCash'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'cash',
                                      child: Text('Cash'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _paymentType = value);
                                    }
                                  },
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _saving ? null : _handlePay,
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.check_circle_rounded,
                                          ),
                                    label: Text(_saving ? 'Paying...' : 'Pay'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kPrimary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                            decoration: BoxDecoration(
                              color: _kCard,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _kBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
                                  child: Text(
                                    'Payment List',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: _kText,
                                    ),
                                  ),
                                ),
                                _paymentRows.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(18),
                                        child: Text(
                                          'No payment records found.',
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          columnSpacing: 20,
                                          horizontalMargin: 18,
                                          headingTextStyle: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: _kText,
                                          ),
                                          columns: const [
                                            DataColumn(label: Text('Name')),
                                            DataColumn(
                                              label: Text('Advance Amount'),
                                            ),
                                            DataColumn(label: Text('Type')),
                                            DataColumn(label: Text('Added By')),
                                            DataColumn(label: Text('Date')),
                                          ],
                                          rows: _paymentRows.map((row) {
                                            final name = _fullNameForRow(row);
                                            final type = (row['type'] ?? 'cash')
                                                .toString()
                                                .toLowerCase();
                                            return DataRow(
                                              cells: [
                                                DataCell(Text(name)),
                                                DataCell(
                                                  Text(
                                                    _amountLabel(row['amount']),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    type == 'gcash'
                                                        ? 'GCash'
                                                        : 'Cash',
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(_addedByNameForRow(row)),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _dateLabel(
                                                      row['created_at'],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }).toList(),
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
