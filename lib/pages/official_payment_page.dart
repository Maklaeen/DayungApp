import 'package:capstone_app/Collector/gcash_qr_page.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kOfficialPaymentBg = Color(0xFFFAFAF7);
const kOfficialPaymentText = Color(0xFF1F2937);
const kOfficialPaymentSubText = Color(0xFF4B5563);
const kOfficialPaymentPrimary = Color(0xFF0D47A1);
const kOfficialPaymentPrimaryDark = Color(0xFF083366);
const kOfficialPaymentAccent = Color(0xFF2E7D32);
const kOfficialPaymentWarn = Color(0xFFF57C00);

class OfficialPaymentPage extends StatefulWidget {
  final int dayungUnitId;
  final String roleTitle;
  final String roleSubtitle;

  const OfficialPaymentPage({
    super.key,
    required this.dayungUnitId,
    required this.roleTitle,
    required this.roleSubtitle,
  });

  @override
  State<OfficialPaymentPage> createState() => _OfficialPaymentPageState();
}

class _OfficialPaymentPageState extends State<OfficialPaymentPage> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  double _totalPending = 0;
  List<Map<String, dynamic>> _pendingRows = [];
  List<Map<String, dynamic>> _collectors = [];
  String? _selectedCollectorId;
  Map<int, Map<String, dynamic>> _noticeMeta = {};
  Map<String, String> _memberNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _loading = false;
          _error = 'Missing logged-in account.';
        });
        return;
      }

      final res = await sb
          .from('payments')
          .select('id, amount, death_notice_id, status, created_at, paid_at')
          .eq('user_id', uid)
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(res);
      final total = rows.fold<double>(
        0,
        (sum, row) => sum + _amountOf(row['amount']),
      );

      final collectors = await _loadCollectors();
      final meta = await _loadNoticeMeta(rows);

      if (!mounted) return;
      setState(() {
        _pendingRows = rows;
        _totalPending = total;
        _collectors = collectors;
        _selectedCollectorId = collectors.isNotEmpty
            ? (collectors.first['id'] ?? '').toString()
            : null;
        _noticeMeta = meta.item1;
        _memberNames = meta.item2;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load your pending payments: $e';
      });
    }
  }

  double _amountOf(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> _loadCollectors() async {
    try {
      final assignments = await sb
          .from('dayung_collectors')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId);

      final ids = List<Map<String, dynamic>>.from(assignments)
          .map((row) => row['user_id'])
          .where((value) => value != null)
          .map((value) => value.toString())
          .toSet()
          .toList();

      if (ids.isEmpty) return [];

      final users = await sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', ids);
      return List<Map<String, dynamic>>.from(users);
    } catch (_) {
      return [];
    }
  }

  Future<({Map<int, Map<String, dynamic>> item1, Map<String, String> item2})>
  _loadNoticeMeta(List<Map<String, dynamic>> rows) async {
    final noticeIds = rows
        .map((row) => int.tryParse('${row['death_notice_id'] ?? ''}'))
        .whereType<int>()
        .toSet()
        .toList();

    if (noticeIds.isEmpty) {
      return (item1: <int, Map<String, dynamic>>{}, item2: <String, String>{});
    }

    final notices = await sb
        .from('death_notices')
        .select('id, name, deceased_type, user_id')
        .inFilter('id', noticeIds);

    final noticeRows = List<Map<String, dynamic>>.from(notices);
    final memberIds = noticeRows
        .map((row) => row['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final memberNames = <String, String>{};
    if (memberIds.isNotEmpty) {
      final users = await sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', memberIds);
      for (final user in List<Map<String, dynamic>>.from(users)) {
        memberNames[(user['id'] ?? '').toString()] =
            (user['full_name'] ?? 'Member').toString();
      }
    }

    final noticeMeta = <int, Map<String, dynamic>>{};
    for (final notice in noticeRows) {
      final noticeId = int.tryParse('${notice['id']}');
      if (noticeId == null) continue;
      noticeMeta[noticeId] = notice;
    }
    return (item1: noticeMeta, item2: memberNames);
  }

  String _deceasedLabel(Map<String, dynamic> row) {
    final noticeId = int.tryParse('${row['death_notice_id'] ?? ''}');
    if (noticeId == null) return 'No deceased linked';
    final meta = _noticeMeta[noticeId];
    if (meta == null) return 'For Deceased #$noticeId';

    if ((meta['deceased_type'] ?? '').toString() == 'beneficiary') {
      final beneficiaryName = (meta['name'] ?? 'Beneficiary').toString();
      final memberId = (meta['user_id'] ?? '').toString();
      final memberName = _memberNames[memberId] ?? 'Member';
      return 'For $beneficiaryName, beneficiary of $memberName';
    }

    final deceasedName = (meta['name'] ?? '').toString().trim();
    return deceasedName.isEmpty
        ? 'For Deceased #$noticeId'
        : 'For $deceasedName';
  }

  String _dateLabel(Map<String, dynamic> row) {
    final raw = (row['created_at'] ?? '').toString();
    if (raw.isEmpty) return 'No schedule date';
    return raw.split('T').first;
  }

  Future<void> _openCashModal(Map<String, dynamic> paymentRow) async {
    final amount = _amountOf(paymentRow['amount']);
    final amountCtrl = TextEditingController(text: amount.toStringAsFixed(2));
    String? collectorId = _selectedCollectorId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cash Payment',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kOfficialPaymentText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirm the assigned collector and exact amount before recording payment.',
                style: TextStyle(
                  fontSize: 14,
                  color: kOfficialPaymentSubText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: collectorId,
                items: _collectors
                    .map(
                      (collector) => DropdownMenuItem<String>(
                        value: (collector['id'] ?? '').toString(),
                        child: Text(
                          (collector['full_name'] ?? 'Collector').toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => collectorId = value,
                decoration: const InputDecoration(
                  labelText: 'Collector',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Enter the exact payment amount',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (collectorId == null || collectorId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a collector first.'),
                        ),
                      );
                      return;
                    }

                    final entered =
                        double.tryParse(amountCtrl.text.replaceAll(',', '')) ??
                        0;
                    if ((entered - amount).abs() > 0.009) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Amount must equal ₱${amount.toStringAsFixed(2)}.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.of(context).pop();
                    await _markPaymentAsPaid(paymentRow['id'], collectorId!);
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Confirm Cash Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOfficialPaymentAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openGCashModal(Map<String, dynamic> paymentRow) async {
    final amount = _amountOf(paymentRow['amount']);
    final referenceCtrl = TextEditingController();
    bool hasSentPayment = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GCash Payment',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: kOfficialPaymentText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Amount due: ₱${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kOfficialPaymentPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: kOfficialPaymentPrimary.withOpacity(0.12),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProofStepRow(
                          index: 1,
                          title: 'Open the unit GCash QR',
                          subtitle:
                              'Review the official QR before sending payment.',
                        ),
                        SizedBox(height: 10),
                        _ProofStepRow(
                          index: 2,
                          title: 'Send the exact amount',
                          subtitle:
                              'Make sure the transfer matches the due amount exactly.',
                        ),
                        SizedBox(height: 10),
                        _ProofStepRow(
                          index: 3,
                          title: 'Submit your proof details',
                          subtitle:
                              'Enter the GCash reference so the collector can verify it quickly.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                GcashQrPage(dayungUnitId: widget.dayungUnitId),
                          ),
                        );
                      },
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('Open GCash QR'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: referenceCtrl,
                    inputFormatters: AppInputSecurity.singleLineFormatters(
                      maxLength: 120,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'GCash reference number',
                      hintText: 'Enter the transfer reference or proof note',
                      helperText: 'Use the number from your GCash receipt.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: hasSentPayment,
                    onChanged: (value) {
                      setModalState(() => hasSentPayment = value ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I already reviewed the QR and sent this GCash payment.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kOfficialPaymentText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final reference = AppInputSecurity.sanitizePlainText(
                          referenceCtrl.text,
                          maxLength: 120,
                        ).trim();

                        if (!hasSentPayment) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Confirm that you sent the payment before submitting proof.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (reference.length < 4) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Enter a valid GCash reference number first.',
                              ),
                            ),
                          );
                          return;
                        }

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Submit GCash Proof'),
                            content: Text(
                              'Submit ₱${amount.toStringAsFixed(2)} with reference "$reference" for verification?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Submit'),
                              ),
                            ],
                          ),
                        );

                        if (confirm != true) return;

                        Navigator.of(context).pop();
                        await _markPaymentAsGCashPending(
                          paymentRow['id'],
                          reference,
                        );
                      },
                      icon: const Icon(Icons.verified_rounded),
                      label: const Text('Submit For Verification'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kOfficialPaymentPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _markPaymentAsPaid(dynamic paymentId, String collectorId) async {
    try {
      await sb
          .from('payments')
          .update({
            'status': 'paid',
            'paid_at': DateTime.now().toUtc().toIso8601String(),
            'collected_by': collectorId,
          })
          .eq('id', paymentId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded successfully.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to record payment: $e')));
    }
  }

  Future<void> _markPaymentAsGCashPending(dynamic paymentId, String ref) async {
    try {
      await sb
          .from('payments')
          .update({'status': 'pending_verification', 'gcash_ref': ref})
          .eq('id', paymentId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GCash payment submitted for verification.'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit GCash payment: $e')),
      );
    }
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.14)),
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
              color: kOfficialPaymentText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kOfficialPaymentSubText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: kOfficialPaymentSubText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> row) {
    final amount = _amountOf(row['amount']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: kOfficialPaymentPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.payments_rounded,
                    color: kOfficialPaymentPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _deceasedLabel(row),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kOfficialPaymentText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Created on ${_dateLabel(row)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kOfficialPaymentSubText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '₱${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: kOfficialPaymentPrimaryDark,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: _collectors.isEmpty
                      ? null
                      : () => _openCashModal(row),
                  icon: const Icon(Icons.handshake_rounded),
                  label: const Text('Pay Cash'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOfficialPaymentAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _openGCashModal(row),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('Pay GCash'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOfficialPaymentPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (_collectors.isEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'No collector is assigned to this dayung yet, so cash payment is temporarily unavailable.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kOfficialPaymentWarn,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kOfficialPaymentBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kOfficialPaymentPrimaryDark,
                    kOfficialPaymentPrimary,
                  ],
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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.roleTitle,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.roleSubtitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const DayungPageSkeleton(
                      layout: DayungSkeletonLayout.list,
                      itemCount: 4,
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _summaryCard(
                                  icon: Icons.pending_actions_rounded,
                                  title: 'Pending Total',
                                  value: '₱${_totalPending.toStringAsFixed(2)}',
                                  subtitle:
                                      '${_pendingRows.length} pending contribution${_pendingRows.length == 1 ? '' : 's'}',
                                  color: kOfficialPaymentWarn,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _summaryCard(
                                  icon: Icons.qr_code_2_rounded,
                                  title: 'GCash Option',
                                  value: _pendingRows.isEmpty
                                      ? 'Ready'
                                      : 'Open',
                                  subtitle:
                                      'Use QR then submit proof for review',
                                  color: kOfficialPaymentPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (_pendingRows.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: kOfficialPaymentAccent,
                                    size: 42,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'No pending personal payments',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kOfficialPaymentText,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Your pending contribution records for this dayung will appear here once they are created.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: kOfficialPaymentSubText,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            const Text(
                              'Pending Contributions',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: kOfficialPaymentText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Choose cash if you are paying directly to the assigned collector, or GCash if you will send proof for verification.',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: kOfficialPaymentSubText,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ..._pendingRows.map(_paymentCard),
                          ],
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

class _ProofStepRow extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;

  const _ProofStepRow({
    required this.index,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kOfficialPaymentPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: kOfficialPaymentPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kOfficialPaymentText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kOfficialPaymentSubText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
