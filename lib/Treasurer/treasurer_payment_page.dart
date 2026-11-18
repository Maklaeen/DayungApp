import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPageBg = Color(0xFFF8FAFC);
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color: _kHeaderGradientEnd,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF1E40AF),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
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
                  IconButton(
                    tooltip: 'Refresh payments',
                    onPressed: _loading ? null : _loadPayments,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadPayments,
                child: _loading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        children: const [
                          SizedBox(
                            height: 360,
                            child: DayungPageSkeleton(
                              layout: DayungSkeletonLayout.list,
                              padding: EdgeInsets.all(20),
                            ),
                          ),
                        ],
                      )
                    : _error != null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.all(20),
                        children: [_buildLoadError()],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 1200;
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: wide
                                ? [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 360,
                                          child: _buildPaymentForm(),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(child: _buildPaymentList()),
                                      ],
                                    ),
                                  ]
                                : [
                                    _buildPaymentForm(),
                                    const SizedBox(height: 16),
                                    _buildPaymentList(),
                                  ],
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentForm() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
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
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _kText,
            ),
          ),
          const SizedBox(height: 14),
          Autocomplete<Map<String, dynamic>>(
            optionsBuilder: (TextEditingValue value) {
              final query = value.text.trim().toLowerCase();
              if (query.isEmpty) return _userOptions;
              return _userOptions.where((member) {
                final name = (member['full_name'] ?? '').toString();
                return name.toLowerCase().contains(query);
              });
            },
            displayStringForOption: (option) =>
                (option['full_name'] ?? '').toString(),
            onSelected: (option) {
              final userId = (option['user_id'] ?? '').toString();
              setState(() {
                _selectedUserId = userId;
                _nameController.text = (option['full_name'] ?? '').toString();
              });
            },
            fieldViewBuilder:
                (
                  context,
                  fieldTextEditingController,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  fieldTextEditingController.text = _nameController.text;
                  return TextFormField(
                    controller: fieldTextEditingController,
                    focusNode: focusNode,
                    onFieldSubmitted: (_) => onFieldSubmitted(),
                    decoration: InputDecoration(
                      labelText: 'Member name',
                      hintText: 'Choose a member',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                    onChanged: (value) {
                      _nameController.text = value;
                      _selectedUserId = null;
                    },
                  );
                },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Advance amount',
              hintText: '0.00',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _paymentType,
            decoration: InputDecoration(
              labelText: 'Payment type',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              prefixIcon: const Icon(Icons.payment_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 'gcash', child: Text('GCash')),
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _paymentType = value);
            },
          ),
          const SizedBox(height: 14),
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
                  : const Icon(Icons.check_circle_rounded),
              label: Text(_saving ? 'Saving...' : 'Record payment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentList() {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Payment List',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FC),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_paymentRows.length} ${_paymentRows.length == 1 ? 'record' : 'records'}',
                    style: const TextStyle(
                      color: _kPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_paymentRows.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_outlined, color: _kPrimary),
                  SizedBox(width: 10),
                  Text('No payment records yet.'),
                ],
              ),
            )
          else
            RecordDataTable(
              columnSpacing: 18,
              horizontalMargin: 16,
              headingRowHeight: 48,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 72,
              headingRowColor: const Color(0xFFEAF2FC),
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _kPrimary,
                fontSize: 14,
                fontFamily: 'Montserrat',
              ),
              dataTextStyle: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'OpenSans',
              ),
              dividerThickness: 1,
              border: const TableBorder(
                horizontalInside: BorderSide(color: Color(0xFFD7E0EA)),
              ),
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Added by')),
                DataColumn(label: Text('Date')),
              ],
              rows: _paymentRows.indexed.map((entry) {
                final (index, row) = entry;
                final type = (row['type'] ?? 'cash').toString().toLowerCase();
                return DataRow(
                  color: WidgetStatePropertyAll(
                    index.isEven ? Colors.white : const Color(0xFFF5F8FC),
                  ),
                  cells: [
                    DataCell(Text(_fullNameForRow(row))),
                    DataCell(Text(_amountLabel(row['amount']))),
                    DataCell(Text(type == 'gcash' ? 'GCash' : 'Cash')),
                    DataCell(Text(_addedByNameForRow(row))),
                    DataCell(Text(_dateLabel(row['created_at']))),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadError() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Color(0xFFB45309)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Could not load payment records',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _kText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Pull down to retry or tap below.'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Error details'),
            children: [SelectableText(_error ?? '')],
          ),
          OutlinedButton.icon(
            onPressed: _loadPayments,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
