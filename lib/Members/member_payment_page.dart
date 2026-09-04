import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Placeholder models — replace with real Supabase data later
// ---------------------------------------------------------------------------

class _DeathNotice {
  final String id;
  final String name;
  final double amountDue;
  const _DeathNotice({
    required this.id,
    required this.name,
    required this.amountDue,
  });
}

enum _PaymentStatus { unpaid, pending, paid }

class _PaymentRecord {
  final String noticeId;
  _PaymentStatus status;
  String? proofUrl;
  String? referenceNumber;
  String? transactionDate;

  _PaymentRecord({
    required this.noticeId,
    // ignore: unused_element_parameter
    this.status = _PaymentStatus.unpaid,
    // ignore: unused_element_parameter
    this.proofUrl,
    // ignore: unused_element_parameter
    this.referenceNumber,
    // ignore: unused_element_parameter
    this.transactionDate,
  });
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class MemberPaymentPage extends StatefulWidget {
  final int? dayungUnitId;
  const MemberPaymentPage({super.key, this.dayungUnitId});

  @override
  State<MemberPaymentPage> createState() => _MemberPaymentPageState();
}

class _MemberPaymentPageState extends State<MemberPaymentPage> {
  // Placeholder death notices with pending amounts
  final List<_DeathNotice> _notices = const [
    _DeathNotice(id: 'd1', name: 'Patay 1', amountDue: 200),
    _DeathNotice(id: 'd2', name: 'Patay 2', amountDue: 200),
  ];

  late final Map<String, _PaymentRecord> _records;

  @override
  void initState() {
    super.initState();
    _records = {
      for (final n in _notices) n.id: _PaymentRecord(noticeId: n.id),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungSurface(context),
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'My Payments',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _warningBanner(),
            const SizedBox(height: 16),
            ..._notices.map((n) => _paymentCard(n)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Warning banner
  // ---------------------------------------------------------------------------

  Widget _warningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'For GCash payments, upload a screenshot that clearly shows the '
              'date, time, and reference number. Payments without proof will '
              'not be confirmed.',
              style: TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF92400E),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Per-notice payment card
  // ---------------------------------------------------------------------------

  Widget _paymentCard(_DeathNotice notice) {
    final record = _records[notice.id]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: dayungSectionCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    notice.name,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: kPrimary,
                    ),
                  ),
                ),
                _statusChip(record.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Amount due
                Row(
                  children: [
                    Text(
                      'Amount Due:',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: dayungSubtextColor(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${notice.amountDue.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // GCash proof upload
                if (record.status != _PaymentStatus.paid) ...[
                  Text(
                    'GCash Payment Proof',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: dayungTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  record.proofUrl == null
                      ? _uploadBox(notice)
                      : _proofPreview(notice, record),
                  const SizedBox(height: 12),

                  // Reference number field
                  _inputField(
                    label: 'Reference Number',
                    hint: 'e.g. 1234567890',
                    icon: Icons.tag_rounded,
                    initialValue: record.referenceNumber,
                    onChanged: (v) =>
                        setState(() => record.referenceNumber = v),
                  ),
                  const SizedBox(height: 10),

                  // Transaction date field
                  _inputField(
                    label: 'Transaction Date & Time',
                    hint: 'e.g. 2024-06-15 10:30 AM',
                    icon: Icons.calendar_today_rounded,
                    initialValue: record.transactionDate,
                    onChanged: (v) =>
                        setState(() => record.transactionDate = v),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _canSubmit(record)
                            ? kPrimary
                            : const Color(0xFF9CA3AF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed:
                          _canSubmit(record) ? () => _submit(notice, record) : null,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text(
                        'Submit Payment',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Paid — show proof
                  if (record.proofUrl != null)
                    GestureDetector(
                      onTap: () => _viewProof(record.proofUrl!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Color(0xFF065F46), size: 18),
                            SizedBox(width: 8),
                            Text(
                              'View Transaction Proof',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF065F46),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Upload box
  // ---------------------------------------------------------------------------

  Widget _uploadBox(_DeathNotice notice) {
    return GestureDetector(
      onTap: () => _pickProof(notice),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: kPrimary.withValues(alpha: 0.25),
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.upload_file_rounded,
                  color: kPrimary.withValues(alpha: 0.5), size: 32),
              const SizedBox(height: 8),
              Text(
                'Tap to upload GCash screenshot',
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kPrimary.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Must show date, time & reference number',
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 11,
                  color: dayungSubtextColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _proofPreview(_DeathNotice notice, _PaymentRecord record) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            record.proofUrl!,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Icon(Icons.image_rounded,
                    size: 48, color: Color(0xFF9CA3AF)),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => setState(() => record.proofUrl = null),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputField({
    required String label,
    required String hint,
    required IconData icon,
    String? initialValue,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      style: TextStyle(
        fontFamily: 'OpenSans',
        fontSize: 14,
        color: dayungTextColor(context),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: kPrimary, size: 18),
        labelStyle: TextStyle(
          fontFamily: 'OpenSans',
          fontSize: 13,
          color: dayungSubtextColor(context),
        ),
        filled: true,
        fillColor: dayungSoftSurface(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: dayungBorder(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: dayungBorder(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _statusChip(_PaymentStatus status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case _PaymentStatus.paid:
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        label = 'Paid';
        break;
      case _PaymentStatus.pending:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        label = 'Pending';
        break;
      default:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        label = 'Unpaid';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  bool _canSubmit(_PaymentRecord record) =>
      record.proofUrl != null &&
      (record.referenceNumber ?? '').trim().isNotEmpty &&
      (record.transactionDate ?? '').trim().isNotEmpty;

  void _pickProof(_DeathNotice notice) {
    // TODO: wire to image_picker + Supabase storage
    setState(() {
      _records[notice.id]!.proofUrl =
          'https://placeholder.com/gcash_receipt.jpg';
    });
  }

  void _submit(_DeathNotice notice, _PaymentRecord record) {
    // TODO: upload to Supabase payments table
    setState(() => record.status = _PaymentStatus.pending);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment for ${notice.name} submitted — pending confirmation'),
        backgroundColor: kPrimary,
      ),
    );
  }

  void _viewProof(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: Image.network(
                url,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: const Color(0xFFF3F4F6),
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded,
                        size: 48, color: Color(0xFF9CA3AF)),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
