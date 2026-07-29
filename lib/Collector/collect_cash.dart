import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kAccentDark = Color(0xFF083366);
const kBorder = Color(0xFFE5E7EB);
const kSurface = Color(0xFFF8FAFC);
const kSuccess = Color(0xFF10B981);
const kWarn = Color(0xFFF59E0B);

class CollectCashPage extends StatefulWidget {
  final int dayungUnitId;
  final String? preselectedDeceasedUserId;

  const CollectCashPage({
    super.key,
    required this.dayungUnitId,
    this.preselectedDeceasedUserId,
  });

  @override
  State<CollectCashPage> createState() => _CollectCashPageState();
}

class _CollectCashPageState extends State<CollectCashPage> {
  String? get _currentUserId => sb.auth.currentUser?.id;
  int get _unpaidCount {
    int count = _payments
        .where((p) => (p['status'] ?? '').toString().toLowerCase() == 'unpaid')
        .length;
    return count;
  }

  static const Duration _queryTimeout = Duration(seconds: 10);

  final sb = Supabase.instance.client;

  bool _loading = true;
  bool _savingPayment = false;
  bool _hasChanges = false;
  String? _error;

  List<Map<String, dynamic>> _approvedMembers = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _deceasedOptions = [];
  List<Map<String, dynamic>> _claims = [];
  // IDs of members assigned to the logged-in collector (if any).
  Set<String> _assignedMemberIds = <String>{};

  Map<String, dynamic>? _selectedDeceased;
  String _memberSearch = '';
  String _deceasedSearch = '';

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  bool _isClaimedMoney(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final normalized = value.toString().trim().toLowerCase();
    return normalized == 'yes' || normalized == 'true' || normalized == '1';
  }

  bool get _hasSelectedDeceased => _selectedDeceased != null;

  List<Map<String, dynamic>> get _filteredDeceasedOptions {
    if (_deceasedSearch.trim().isEmpty) return _deceasedOptions;
    final query = _deceasedSearch.trim().toLowerCase();
    return _deceasedOptions.where((option) {
      final displayName = (option['display_name'] ?? '')
          .toString()
          .toLowerCase();
      return displayName.contains(query);
    }).toList();
  }

  double get _totalCollectedForSelected {
    final selected = _selectedDeceased;
    if (selected == null) return 0.0;
    return _payments
        .where(
          (payment) =>
              (payment['status'] ?? '').toString().toLowerCase() == 'paid' &&
              _paymentMatchesSelected(payment, selected),
        )
        .fold<double>(
          0.0,
          (sum, payment) => sum + _asDouble(payment['amount']),
        );
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final selected = _selectedDeceased;
    if (selected == null) return const [];

    final excludedUserId = (selected['user_id'] ?? '').toString();
    final query = _memberSearch.trim().toLowerCase();

    final members = _approvedMembers.where((member) {
      final memberId = (member['id'] ?? '').toString();
      if (memberId.isEmpty) return false;
      if (excludedUserId.isNotEmpty && memberId == excludedUserId) {
        return false;
      }
      if (query.isEmpty) return true;
      final fullName = (member['full_name'] ?? '').toString().toLowerCase();
      return fullName.contains(query);
    }).toList();

    // If the current user is a collector with assigned member IDs, limit the
    // displayed members to only those assigned to this collector.
    if (_assignedMemberIds.isNotEmpty) {
      members.retainWhere((member) {
        final memberId = (member['id'] ?? '').toString();
        return _assignedMemberIds.contains(memberId);
      });
    }

    members.sort((a, b) {
      final aPaid = _isMemberPaid((a['id'] ?? '').toString(), selected);
      final bPaid = _isMemberPaid((b['id'] ?? '').toString(), selected);
      if (aPaid != bPaid) return aPaid ? 1 : -1;
      return (a['full_name'] ?? '').toString().toLowerCase().compareTo(
        (b['full_name'] ?? '').toString().toLowerCase(),
      );
    });
    return members;
  }

  int get _paidCountForSelected {
    final selected = _selectedDeceased;
    if (selected == null) return 0;
    return _filteredMembers.where((member) {
      return _isMemberPaid((member['id'] ?? '').toString(), selected);
    }).length;
  }

  int get _pendingCountForSelected {
    final selected = _selectedDeceased;
    if (selected == null) return 0;
    return _filteredMembers.where((member) {
      return !_isMemberPaid((member['id'] ?? '').toString(), selected);
    }).length;
  }

  @override
  void initState() {
    super.initState();
    _loadAll().then((_) {});
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Determine if the current user is a collector and get their collectors_id
      final currentUserId = sb.auth.currentUser?.id ?? '';
      String collectorId = '';
      _assignedMemberIds = <String>{};
      if (currentUserId.isNotEmpty) {
        final collectorRows = List<Map<String, dynamic>>.from(
          await sb
              .from('dayung_collectors')
              .select('collectors_id')
              .eq('user_id', currentUserId)
              .limit(1)
              .timeout(_queryTimeout),
        );
        if (collectorRows.isNotEmpty) {
          collectorId = (collectorRows.first['collectors_id'] ?? '').toString();
        }
      }

      // Build applications query. If the current user is a collector, restrict
      // to rows where `assigned_collector` matches their collectors_id so that
      // other collectors won't see user_ids assigned to someone else or NULL.
      var applicationsQuery = sb
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');
      if (collectorId.isNotEmpty) {
        applicationsQuery = applicationsQuery.eq('assigned_collector', collectorId);
      }

      final results = await Future.wait([
        applicationsQuery.timeout(_queryTimeout),

        sb
            .from('payments')
            .select(
              'id, user_id, amount, status, paid_at, created_at, collected_by, '
              'datepaidamount, userdeceased, dayung_unit_id, type',
            )
            .eq('dayung_unit_id', widget.dayungUnitId)
            .timeout(_queryTimeout),

        sb.from('beneficiaries').select('id, full_name').timeout(_queryTimeout),
        sb
            .from('claims')
            .select(
              'id, status, user_id, beneficiary_id, amount, PassedAway, datesetamount, claimedmoney',
            )
            .timeout(_queryTimeout),
      ]);

      // _assignedMemberIds will be set from the fetched approvedApps below when
      // collectorId is present so we don't need a separate query.

      final approvedApps = List<Map<String, dynamic>>.from(results[0]);

      // If this user is a collector (collectorId present) then the applications
      // query was already restricted to their assigned rows; use that to set
      // the assigned member ids. This also ensures rows with NULL
      // `assigned_collector` are not visible to other collectors.
      if (collectorId.isNotEmpty) {
        _assignedMemberIds = {
          for (final row in approvedApps) (row['user_id'] ?? '').toString()
        }..remove('');
      }

      final payments = List<Map<String, dynamic>>.from(results[1]);

      final beneficiaries = List<Map<String, dynamic>>.from(results[2]);
      final claims = List<Map<String, dynamic>>.from(results[3]);

      final memberIds = <String>{
        for (final row in approvedApps) (row['user_id'] ?? '').toString(),
      }..remove('');

      // If we have assigned member IDs for this collector, filter payments to only
      // those for the assigned members so the UI shows relevant payment rows.
      if (_assignedMemberIds.isNotEmpty) {
        payments.removeWhere((p) {
          final uid = (p['user_id'] ?? '').toString();
          return !_assignedMemberIds.contains(uid);
        });
      }

      final lookupUserIds = <String>{
        ...memberIds,

        for (final row in payments) (row['user_id'] ?? '').toString(),
        for (final row in payments) (row['collected_by'] ?? '').toString(),
        // Ensure we fetch full names for deceased users referenced by claims
        for (final row in claims) (row['user_id'] ?? '').toString(),
      }..remove('');

      final userRows = lookupUserIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await sb
                  .from('users')
                  .select('id, full_name')
                  .inFilter('id', lookupUserIds.toList())
                  .timeout(_queryTimeout),
            );

      final userMap = {
        for (final row in userRows)
          (row['id'] ?? '').toString(): (row['full_name'] ?? 'Member')
              .toString(),
      };

      final approvedMembers =
          memberIds
              .map((id) => {'id': id, 'full_name': userMap[id] ?? 'Member'})
              .toList()
            ..sort((a, b) {
              return (a['full_name'] ?? '').toString().toLowerCase().compareTo(
                (b['full_name'] ?? '').toString().toLowerCase(),
              );
            });

      final deceasedOptions = _buildDeceasedOptions(
        setAmounts: claims,
        beneficiaries: beneficiaries,
        userMap: userMap,
        deathNotices: [],
      );

      // Ensure every approved claim produces a deceased option even when
      // there are no death notices or payments referencing `userdeceased`.
      // This guarantees the UI shows the full name for the claim's user_id.
      final existingKeys = {for (final o in deceasedOptions) (o['key'] ?? '').toString()};
      for (final claim in claims) {
        final beneficiaryId = (claim['beneficiary_id'] ?? '').toString();
        final userId = (claim['user_id'] ?? '').toString();
        final key = beneficiaryId.isNotEmpty ? 'beneficiary:$beneficiaryId' : 'user:$userId';
        if (key == 'user:' || existingKeys.contains(key)) continue;

        final displayName = beneficiaryId.isNotEmpty
            ? _beneficiaryLabel(beneficiaries, beneficiaryId)
            : (userMap[userId] ?? (claim['PassedAway'] ?? claim['passed_away'] ?? 'Deceased Member'));

        deceasedOptions.add({
          'id': claim['id'],
          'key': key,
          'death_notice_id': null,
          'user_id': userId,
          'beneficiary_id': beneficiaryId,
          'display_name': displayName,
          'amount': _asDouble(claim['amount']),
          'required_amount': _asDouble(claim['amount']),
          'deceased_type': beneficiaryId.isNotEmpty ? 'beneficiary' : 'member',
        });
        existingKeys.add(key);
      }

      deceasedOptions.sort((a, b) => (a['display_name'] ?? '').toString().toLowerCase().compareTo((b['display_name'] ?? '').toString().toLowerCase()));

      Map<String, dynamic>? nextSelected;
      final selectedKey = (_selectedDeceased?['key'] ?? '').toString();
      if (selectedKey.isNotEmpty) {
        for (final option in deceasedOptions) {
          if ((option['key'] ?? '').toString() == selectedKey) {
            nextSelected = option;
            break;
          }
        }
      }
      nextSelected ??= _resolvePreselectedClaim(deceasedOptions);

      if (!mounted) return;
      setState(() {
        _approvedMembers = approvedMembers;
        _payments = payments;
        _deceasedOptions = deceasedOptions;
        _claims = claims;
        _selectedDeceased = nextSelected;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load collection data: $e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _resolvePreselectedClaim(
    List<Map<String, dynamic>> deceasedOptions,
  ) {
    final selectedUserId =
        (_selectedDeceased?['user_id'] ?? widget.preselectedDeceasedUserId ?? '')
            .toString();
    if (selectedUserId.isEmpty) return null;

    for (final option in deceasedOptions) {
      if ((option['user_id'] ?? '').toString() == selectedUserId) {
        return option;
      }
    }

    return null;
  }

  Map<String, dynamic> _selectionForClaim(Map<String, dynamic> claim) {
    final beneficiaryId = (claim['beneficiary_id'] ?? '').toString();
    final userId = (claim['user_id'] ?? '').toString();
    final key = beneficiaryId.isNotEmpty
        ? 'beneficiary:$beneficiaryId'
        : 'user:$userId';

    for (final option in _deceasedOptions) {
      if ((option['key'] ?? '').toString() == key) {
        return option;
      }
    }

    final displayName = beneficiaryId.isNotEmpty
        ? ((claim['PassedAway'] ?? claim['passed_away'] ?? 'Beneficiary')
              .toString())
        : _memberName(userId);

    return {
      ...claim,
      'key': key,
      'display_name': displayName,
      'amount': _asDouble(claim['amount']),
      'required_amount': _asDouble(claim['amount']),
    };
  }

  List<Map<String, dynamic>> _buildDeceasedOptions({
    required List<Map<String, dynamic>> setAmounts,
    required List<Map<String, dynamic>> deathNotices,
    required List<Map<String, dynamic>> beneficiaries,
    required Map<String, String> userMap,
  }) {
    final options = <Map<String, dynamic>>[];
    final seenKeys = <String>{};

    for (final notice in deathNotices) {
      final beneficiaryId = (notice['beneficiary_id'] ?? '').toString();
      final userId = (notice['user_id'] ?? '').toString();

      Map<String, dynamic>? setAmount;
      for (final row in setAmounts) {
        if (beneficiaryId.isNotEmpty &&
            (row['beneficiary_id'] ?? '').toString() == beneficiaryId) {
          setAmount = row;
          break;
        }
        if (beneficiaryId.isEmpty &&
            userId.isNotEmpty &&
            (row['userdeceased'] ?? '').toString() == userId) {
          setAmount = row;
          break;
        }
      }

      if (setAmount == null) continue;

      final key = beneficiaryId.isNotEmpty
          ? 'beneficiary:$beneficiaryId'
          : 'user:$userId';
      if (!seenKeys.add(key)) continue;

      final displayName = beneficiaryId.isNotEmpty
          ? _beneficiaryLabel(beneficiaries, beneficiaryId)
          : ((notice['name'] ?? '').toString().trim().isNotEmpty
                ? (notice['name'] ?? '').toString()
                : (userMap[userId] ?? 'Deceased Member'));

      options.add({
        'id': setAmount['id'],
        'key': key,
        'death_notice_id': notice['id'],
        'user_id': userId,
        'beneficiary_id': beneficiaryId,
        'display_name': displayName,
        'amount': _asDouble(setAmount['amount']),
        'required_amount': _asDouble(setAmount['amount']),

        'deceased_type': (notice['deceased_type'] ?? 'member').toString(),
      });
    }

    for (final setAmount in setAmounts) {
      final beneficiaryId = (setAmount['beneficiary_id'] ?? '').toString();
      final userId = (setAmount['userdeceased'] ?? '').toString();
      final key = beneficiaryId.isNotEmpty
          ? 'beneficiary:$beneficiaryId'
          : 'user:$userId';
      if (key == 'user:' || !seenKeys.add(key)) continue;

      options.add({
        'id': setAmount['id'],
        'key': key,
        'death_notice_id': null,
        'user_id': userId,
        'beneficiary_id': beneficiaryId,
        'display_name': beneficiaryId.isNotEmpty
            ? _beneficiaryLabel(beneficiaries, beneficiaryId)
            : (userMap[userId] ?? 'Deceased Member'),
        'amount': _asDouble(setAmount['amount']),
        'required_amount': _asDouble(setAmount['amount']),

        'deceased_type': beneficiaryId.isNotEmpty ? 'beneficiary' : 'member',
      });
    }

    options.sort((a, b) {
      return (a['display_name'] ?? '').toString().toLowerCase().compareTo(
        (b['display_name'] ?? '').toString().toLowerCase(),
      );
    });

    return options;
  }

  String _beneficiaryLabel(
    List<Map<String, dynamic>> beneficiaries,
    String beneficiaryId,
  ) {
    for (final beneficiary in beneficiaries) {
      if ((beneficiary['id'] ?? '').toString() != beneficiaryId) continue;
      final fullName = (beneficiary['full_name'] ?? '').toString().trim();
      if (fullName.isNotEmpty) return fullName;
    }
    return 'Beneficiary';
  }

  bool _paymentMatchesSelected(
    Map<String, dynamic> payment,
    Map<String, dynamic>? selected,
  ) {
    if (selected == null) return false;
    final selectedUserId = (selected['user_id'] ?? '').toString();
    return (payment['userdeceased'] ?? '').toString() == selectedUserId;
  }

  bool _isMemberPaid(String memberId, Map<String, dynamic>? selected) {
    for (final payment in _payments) {
      if ((payment['user_id'] ?? '').toString() != memberId) continue;
      if (!_paymentMatchesSelected(payment, selected)) continue;
      final status = (payment['status'] ?? '').toString().toLowerCase();

      if (status == 'paid') return true;
    }

    return false;
  }

  Map<String, dynamic>? _paymentForMember(String memberId) {
    final selected = _selectedDeceased;
    if (selected == null) return null;

    Map<String, dynamic>? fallback;
    for (final payment in _payments) {
      if ((payment['user_id'] ?? '').toString() != memberId) continue;
      if (!_paymentMatchesSelected(payment, selected)) continue;
      final status = (payment['status'] ?? '').toString().toLowerCase();
      if (status == 'paid') return payment;
      fallback ??= payment;
    }
    return fallback;
  }

  Future<void> _showCollectDialog(Map<String, dynamic> member) async {
    final selected = _selectedDeceased;
    if (selected == null) return;

    final amount = _asDouble(selected['amount']);
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No amount has been set for this notice yet.'),
        ),
      );
      return;
    }

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Confirm Cash Collection',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: kAccentDark,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This will mark the payment as paid and generate a receipt-ready record for this member.',
                  style: TextStyle(
                    fontSize: 14,
                    color: kSubText.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'OpenSans',
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                _detailRow(
                  'Member',
                  (member['full_name'] ?? 'Member').toString(),
                ),
                _detailRow(
                  'For',
                  (selected['display_name'] ?? 'Deceased').toString(),
                ),
                _detailRow('Amount', 'PHP ${amount.toStringAsFixed(2)}'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.payments_rounded),
                    label: const Text('Mark as Paid'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirm == true) {
      await _savePayment((member['id'] ?? '').toString(), amount);
    }
  }

  Future<void> _savePayment(String userId, double amount) async {
    final selected = _selectedDeceased;
    if (selected == null || _savingPayment) return;

    setState(() => _savingPayment = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final collectorId = sb.auth.currentUser?.id;
      if (collectorId == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Not logged in as collector.')),
        );
        return;
      }
      final deceasedUserId = (selected['user_id'] ?? '').toString();

      // Find the latest payment row for this user and deceased
      final paymentRows = List<Map<String, dynamic>>.from(
        await sb
            .from('payments')
            .select('id, status, amount, userdeceased')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('user_id', userId)
            .eq('userdeceased', deceasedUserId)
            .order('created_at', ascending: false)
            .limit(1)
            .timeout(_queryTimeout),
      );
      Map<String, dynamic>? payment = paymentRows.isNotEmpty
          ? paymentRows.first
          : null;

      // If payment record does not exist, create it automatically
      if (payment == null) {
        final insertResult = await sb
            .from('payments')
            .insert({
              'user_id': userId,
              'userdeceased': deceasedUserId,
              'amount': amount,
              'status': 'unpaid',
              'type': 'deceased_payment',
              'dayung_unit_id': widget.dayungUnitId,
            })
            .select()
            .timeout(_queryTimeout);
        if (insertResult.isNotEmpty) {
          payment = insertResult.first;
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to create payment record. Please try again.',
              ),
            ),
          );
          setState(() => _savingPayment = false);
          return;
        }
      }

      final now = DateTime.now().toUtc().toIso8601String();
      // Only update the existing payment to PAID

      await sb
          .from('payments')
          .update({
            'status': 'paid',
            'paid_at': now,
            'collected_by': collectorId,
            'datepaidamount': now,
          })
          .eq('id', payment['id'])
          .timeout(_queryTimeout);

      payment['status'] = 'paid';
      payment['paid_at'] = now;

      // Mark that we made changes so callers can refresh when this page pops.
      _hasChanges = true;

      // Update aggregate summary fields on the related claim
      await _updateClaimPaymentSummary(selected);

      await _loadAll();
      if (!mounted) return;

      _showReceiptPreview(
        memberName: _memberName(userId),
        deceasedName: (selected['display_name'] ?? 'Deceased').toString(),
        amount: amount,
        paymentId: payment['id'],
        paidAt: payment['paid_at'] ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update payment: $e')));
    } finally {
      if (mounted) {
        setState(() => _savingPayment = false);
      }
    }
  }

  /// Updates the aggregate payment summary fields on a claim row in Supabase.
  ///
  /// - paid_count: number of payments with status == 'paid'
  /// - unpaid_count: number of payments with status == 'unpaid'
  /// - total_paid_amount: sum(amount) where status == 'paid'
  /// - total_payment_amount: sum(amount) where status in ('paid', 'unpaid')
  Future<void> _updateClaimPaymentSummary(Map<String, dynamic> claim) async {
    try {
      final deceasedUserId = (claim['user_id'] ?? '').toString();
      if (deceasedUserId.isEmpty) return;

      final payments = List<Map<String, dynamic>>.from(
        await sb
            .from('payments')
            .select('id, amount, status, userdeceased, dayung_unit_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('userdeceased', deceasedUserId)
            .timeout(_queryTimeout),
      );

      int paidCount = 0;
      int unpaidCount = 0;
      double totalPaidAmount = 0.0;
      double totalPaymentAmount = 0.0;

      for (final payment in payments) {
        final status = (payment['status'] ?? '').toString().toLowerCase();
        if (status != 'paid' && status != 'unpaid') continue;

        final paymentAmount = _asDouble(payment['amount']);

        if (status == 'paid') {
          paidCount++;
          totalPaidAmount += paymentAmount;
        }
        if (status == 'unpaid') {
          unpaidCount++;
        }

        totalPaymentAmount += paymentAmount;
      }

      await sb
          .from('claims')
          .update({
            'paid_count': paidCount,
            'unpaid_count': unpaidCount,
            'total_paid_amount': totalPaidAmount,
            'total_payment_amount': totalPaymentAmount,
          })
          .eq('id', claim['id'])
          .timeout(_queryTimeout);
    } catch (_) {
      // Silently ignore summary update failures to avoid blocking payment save.
    }
  }

  String _memberName(String userId) {
    for (final member in _approvedMembers) {
      if ((member['id'] ?? '').toString() == userId) {
        return (member['full_name'] ?? 'Member').toString();
      }
    }
    return 'Member';
  }

  void _showReceiptPreview({
    required String memberName,
    required String deceasedName,
    required double amount,
    required dynamic paymentId,
    required String paidAt,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF083366), Color(0xFF0D47A1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cash Receipt',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                        ),
                      ),

                      const SizedBox(height: 18),
                      _receiptLine('Member', memberName),
                      _receiptLine('For', deceasedName),
                      _receiptLine(
                        'Amount',
                        'PHP ${amount.toStringAsFixed(2)}',
                      ),
                      _receiptLine('Paid At', paidAt.split('T').join(' ')),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Done'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _ensurePaymentRecordsForClaim(Map<String, dynamic> claim) async {
    final deceasedUserId = claim['user_id'].toString();
    final dayungUnitId = widget.dayungUnitId;

    for (final member in _approvedMembers) {
      final memberId = member['id'].toString();
      if (memberId == deceasedUserId) continue; // skip deceased

      // Check if payment exists
      final existing = _payments.any(
        (p) =>
            p['user_id'].toString() == memberId &&
            p['userdeceased'].toString() == deceasedUserId &&
            p['dayung_unit_id'] == dayungUnitId,
      );
      if (!existing) {
        // Insert missing payment record
        await sb.from('payments').insert({
          'user_id': memberId,
          'userdeceased': deceasedUserId,
          'amount': claim['amount'],
          'status': 'unpaid',
          'dayung_unit_id': dayungUnitId,
          // add other required fields
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 860;

    return WillPopScope(
      onWillPop: () async {
        if (_selectedDeceased != null) {
          setState(() {
            _selectedDeceased = null;
            _memberSearch = '';
          });
          return false;
        }

        Navigator.of(context).pop(_hasChanges);
        return false;
      },
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(wide),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 20,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: kAccent),
                          )
                        : _error != null
                            ? _buildErrorState()
                            : RefreshIndicator(
                                color: kAccent,
                                onRefresh: _loadAll,
                                child: ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 20, 20, 24),
                                  children: _hasSelectedDeceased
                                      ? _buildMemberStep()
                                      : _buildDeceasedStep(),
                                ),
                              ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDeceasedStep() {
    final approvedClaims = _claims
        .where(
          (c) => (c['status'] ?? '').toString().toLowerCase() == 'approved',
        )
        .toList()
      ..sort((a, b) {
        final aClaimed = _isClaimedMoney(a['claimedmoney']);
        final bClaimed = _isClaimedMoney(b['claimedmoney']);
        if (aClaimed != bClaimed) return aClaimed ? 1 : -1;

        final aDate = DateTime.tryParse(
          (a['datesetamount'] ?? '').toString(),
        );
        final bDate = DateTime.tryParse(
          (b['datesetamount'] ?? '').toString(),
        );
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

    // Show approved claims regardless of whether any payments currently
    // reference their `user_id`. Collectors will still see only assigned
    // members in the members list; claims (the deceased options) remain
    // visible even if there are no payment rows with `userdeceased` set.

    return [
      _overviewCard(
        title: 'Collection Overview',
        subtitle:
            'Choose an approved claim, then record which members have already paid in cash.',
        cards: [
          _statCard(
            icon: Icons.payments_rounded,
            label: 'Paid Cash',
            value:
                '${_payments.where((row) => (row['status'] ?? '').toString().toLowerCase() == 'paid').length}',
            tone: const Color(0xFF0F766E),
          ),
          _statCard(
            icon: Icons.pending_actions_rounded,
            label: 'Unpaid Cash',
            value: '$_unpaidCount',
            tone: kWarn,
          ),
          _statCard(
            icon: Icons.receipt_long_rounded,
            label: 'Approved Claims',
            value: '${approvedClaims.length}',
            tone: const Color(0xFF1E40AF),
          ),
          _statCard(
            icon: Icons.groups_rounded,
            label: 'Approved Members',
            value: '${_approvedMembers.length}',
            tone: const Color(0xFFB45309),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _searchCard(
        hint: 'Search claim title or passed away',
        onChanged: (value) => setState(() => _deceasedSearch = value.trim()),
      ),
      const SizedBox(height: 18),
      if (approvedClaims.isEmpty)
        _emptyState(
          title: 'No approved claims found',
          subtitle:
              'Claims must be approved before collectors can record cash payments here.',
        )
      else
        ...approvedClaims.map(_claimCard),
    ];
  }

  Widget _claimCard(Map<String, dynamic> claim) {
    final isClaimed = _isClaimedMoney(claim['claimedmoney']);
    final beneficiaryId = (claim['beneficiary_id'] ?? '').toString();
    final userId = (claim['user_id'] ?? '').toString();
    final key = beneficiaryId.isNotEmpty ? 'beneficiary:$beneficiaryId' : 'user:$userId';
    String displayName = '';
    try {
      final opt = _deceasedOptions.firstWhere(
        (o) => (o['key'] ?? '').toString() == key,
        orElse: () => <String, dynamic>{},
      );
      if (opt.isNotEmpty) displayName = (opt['display_name'] ?? '').toString();
    } catch (_) {
      displayName = '';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          setState(() {
            _selectedDeceased = _selectionForClaim(claim);
            _memberSearch = '';
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      (claim['beneficiary_id'] ?? '').toString().isNotEmpty
                          ? 'Claim for ${_beneficiaryLabel([], (claim['beneficiary_id'] ?? '').toString())}'
                          : (displayName.isNotEmpty ? displayName : _memberName(userId)),
                      style: const TextStyle(
                        fontSize: 16,
                        color: kText,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ),
                  if (isClaimed) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'CLAIMED MONEY',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF374151),
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
             
              const SizedBox(height: 4),
              Text(
                'Amount: PHP ${_asDouble(claim['amount']).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: kSubText,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMemberStep() {
    final selected = _selectedDeceased!;
    return [
      const SizedBox(height: 14),
      const Text(
        'Cash Receipt',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          fontFamily: 'Montserrat',
        ),
      ),
      const SizedBox(height: 14),
      _overviewCard(
        title: (selected['display_name'] ?? 'Deceased').toString(),
        subtitle:
            'Review all assigned members for this notice and mark their cash contributions once collected.',
        cards: [
          _statCard(
            icon: Icons.check_circle_rounded,
            label: 'Paid Members',
            value: '$_paidCountForSelected',
            tone: kSuccess,
          ),
          _statCard(
            icon: Icons.pending_actions_rounded,
            label: 'Pending Members',
            value: '$_pendingCountForSelected',
            tone: kWarn,
          ),
          _statCard(
            icon: Icons.payments_outlined,
            label: 'Required Amount',
            value: 'PHP ${_asDouble(selected['amount']).toStringAsFixed(2)}',
            tone: kAccent,
          ),
          _statCard(
            icon: Icons.attach_money_rounded,
            label: 'Total Collected',
            value: 'PHP ${_totalCollectedForSelected.toStringAsFixed(2)}',
            tone: const Color(0xFF047857),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _searchCard(
        hint: 'Search member by name',
        onChanged: (value) => setState(() => _memberSearch = value.trim()),
      ),
      const SizedBox(height: 18),
      if (_filteredMembers.isEmpty)
        _emptyState(
          title: 'No members matched this filter',
          subtitle:
              'Try a different search term or go back and choose another notice.',
        )
      else
        ..._filteredMembers.map(_memberCard),
    ];
  }

  Widget _buildHeader(bool wide) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        wide ? 36 : 28,
        wide ? 24 : 16,
        wide ? 32 : 24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF083366), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x22083366),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              if (_selectedDeceased != null) {
                setState(() {
                  _selectedDeceased = null;
                  _memberSearch = '';
                });
                return;
              }
              Navigator.of(context).pop(_hasChanges);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collect Cash Payments',
                  style: TextStyle(
                    fontSize: wide ? 24 : 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedDeceased == null
                      ? 'Select a death notice first, then record paid cash contributions member by member.'
                      : 'You are now reviewing the members assigned to the selected notice.',
                  style: TextStyle(
                    fontSize: wide ? 14 : 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _headerPill(
                      icon: Icons.groups_rounded,
                      label: '${_approvedMembers.length} members',
                    ),
                    _headerPill(
                      icon: Icons.receipt_long_rounded,
                      label: '${_deceasedOptions.length} active notices',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewCard({
    required String title,
    required String subtitle,
    required List<Widget> cards,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: kSubText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Row(
                  children: [
                    for (int index = 0; index < cards.length; index++) ...[
                      Expanded(child: cards[index]),
                      if (index != cards.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (int index = 0; index < cards.length; index++) ...[
                    cards[index],
                    if (index != cards.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kSubText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kText,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchCard({
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: kSurface,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kAccent),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _deceasedCard(Map<String, dynamic> option) {
    final requiredAmount = _asDouble(option['required_amount']);
    final excludedUserId = (option['user_id'] ?? '').toString();
    final totalMembers = _approvedMembers.where((member) {
      final memberId = (member['id'] ?? '').toString();
      return memberId.isNotEmpty && memberId != excludedUserId;
    }).length;
    final paidCount = _approvedMembers.where((member) {
      final memberId = (member['id'] ?? '').toString();
      if (memberId.isEmpty || memberId == excludedUserId) return false;
      return _isMemberPaid(memberId, option);
    }).length;
    final isComplete = totalMembers > 0 && paidCount >= totalMembers;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          setState(() {
            _selectedDeceased = option;
            _memberSearch = '';
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (option['display_name'] ?? 'Deceased').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kText,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Required cash contribution: PHP ${requiredAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: kSubText,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'OpenSans',
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
                      color: isComplete
                          ? kSuccess.withValues(alpha: 0.12)
                          : kAccent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isComplete ? 'Complete' : '$paidCount/$totalMembers',
                      style: TextStyle(
                        color: isComplete ? kSuccess : kAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _miniChip(
                    icon: Icons.groups_rounded,
                    label: '$totalMembers chargeable members',
                    color: kAccent,
                    background: const Color(0xFFEFF6FF),
                  ),
                  _miniChip(
                    icon: Icons.check_circle_rounded,
                    label: '$paidCount paid',
                    color: kSuccess,
                    background: const Color(0xFFECFDF5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberCard(Map<String, dynamic> member) {
    final memberId = (member['id'] ?? '').toString();
    final payment = _paymentForMember(memberId);
    final status = (payment?['status'] ?? '').toString().toLowerCase();
    final bool isPaid = status == 'paid';
    final bool isCurrentUser = _currentUserId == memberId;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isPaid ? kSuccess.withValues(alpha: 0.18) : kBorder,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            spreadRadius: 0,
            offset: Offset(0, 6),
            color: Color(0x1A000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: (isPaid ? kSuccess : kAccent).withValues(
                    alpha: 0.12,
                  ),
                  child: Icon(
                    isPaid
                        ? Icons.check_circle_rounded
                        : Icons.payments_rounded,
                    color: isPaid ? kSuccess : kAccent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (member['full_name'] ?? 'Member').toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: kText,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isPaid
                            ? 'Payment already marked as paid.'
                            : (payment != null &&
                                    (payment['type'] ?? '').toString().toLowerCase() ==
                                        'deceased_payment'
                                ? 'Ready for cash collection and receipt generation. User ID: ${payment['user_id'] ?? ''}'
                                : 'Ready for cash collection and receipt generation.'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: kSubText,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'OpenSans',
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
                    color: (isPaid ? kSuccess : kWarn).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isPaid ? 'Paid' : 'Pending',
                    style: TextStyle(
                      color: isPaid ? kSuccess : kWarn,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _miniChip(
                  icon: Icons.payments_rounded,
                  label: isPaid
                      ? 'PHP ${_asDouble(payment?['amount']).toStringAsFixed(2)}'
                      : 'PHP ${_asDouble(_selectedDeceased?['amount']).toStringAsFixed(2)}',
                  color: kAccent,
                  background: const Color(0xFFEFF6FF),
                ),
                if (payment != null &&
                    (payment['paid_at'] ?? '').toString().isNotEmpty)
                  _miniChip(
                    icon: Icons.schedule_rounded,
                    label: (payment['paid_at'] ?? '')
                        .toString()
                        .split('T')
                        .first,
                    color: kSuccess,
                    background: const Color(0xFFECFDF5),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (isCurrentUser)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.block),
                      label: const Text('Cannot collect for yourself'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kWarn.withOpacity(0.7),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFFDE68A),
                        disabledForegroundColor: kWarn,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kWarn.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'You cannot collect your own payment. Please pay via GCash or ask the Treasurer to record your payment.',
                      style: TextStyle(
                        color: kWarn,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isPaid ? null : () => _showCollectDialog(member),
                  icon: Icon(
                    isPaid
                        ? Icons.check_circle_rounded
                        : Icons.payments_rounded,
                  ),
                  label: Text(isPaid ? 'Paid' : 'Collect Cash'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    disabledForegroundColor: const Color(0xFF6B7280),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Color(0xFFB45309)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Could not load cash collection data',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _error ?? 'Unknown error',
                style: const TextStyle(
                  color: kSubText,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadAll,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry fetch'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState({required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 32,
              color: kAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: kSubText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kSubText,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kText,
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
