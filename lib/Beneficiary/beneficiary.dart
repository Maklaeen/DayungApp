import 'package:auto_size_text/auto_size_text.dart';
import 'package:capstone_app/Beneficiary/addbeneficiary.dart' as add;
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
const kSuccess = Color(0xFF10B981);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);

class BeneficiaryPage extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showBackButton;

  const BeneficiaryPage({super.key, this.onBack, this.showBackButton = true});

  @override
  State<BeneficiaryPage> createState() => _BeneficiaryPageState();
}

class _BeneficiaryPageState extends State<BeneficiaryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> beneficiaries = [];
  List<dynamic> pendingBeneficiaries = [];
  List<dynamic> activeBeneficiaries = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchBeneficiaries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchBeneficiaries() async {
    setState(() => isLoading = true);

    final user = Supabase.instance.client.auth.currentUser;
    final response = await Supabase.instance.client
        .from('beneficiaries')
        .select()
        .eq('user_id', user!.id);

    final List<dynamic> allBeneficiaries = response;
    final List<dynamic> pending = allBeneficiaries
        .where((b) => b['status'] == 'Pending' || b['status'] == null)
        .toList();
    final List<dynamic> active = allBeneficiaries
        .where((b) => b['status'] == 'Approved')
        .toList();

    setState(() {
      beneficiaries = allBeneficiaries;
      pendingBeneficiaries = pending;
      activeBeneficiaries = active;
      isLoading = false;
    });
  }

  Future<void> _navigateToAddBeneficiary(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const add.AddBeneficiaryPage()),
    );
    fetchBeneficiaries();
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'approved':
        return kSuccess;
      case 'rejected':
        return kDanger;
      default:
        return kWarn;
    }
  }

  IconData _statusIcon(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'approved':
        return Icons.verified_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  Future<void> _showResolvedFile(BuildContext context, String url) async {
    final resolved = await resolveSupabaseStorageUrl(url);
    if (resolved == null) return;

    if (storageLooksLikePdf(resolved)) {
      await launchUrl(
        Uri.parse(resolved),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  resolved,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Text('Could not load image'),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Close'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBeneficiaryDetails(Map item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final width = MediaQuery.of(sheetContext).size.width;
        final isWide = width > 700;
        final isCompact = width < 360;
        final status = item['status']?.toString();
        final statusColor = _statusColor(status);

        return Container(
          decoration: const BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 24,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isWide ? 40 : 20,
                24,
                isWide ? 40 : 20,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _statusIcon(status),
                          color: statusColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AutoSizeText(
                              item['full_name'] ?? 'Beneficiary Details',
                              maxLines: 2,
                              minFontSize: 16,
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w800,
                                fontSize: isWide ? 24 : 20,
                                color: kText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                status ?? 'Pending',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: kSubText),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: kBorderColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        _detailRow('Relationship', item['relationship']),
                        _detailRow('Date of Birth', item['dob']),
                        _detailRow('Marital Status', item['marital_status']),
                        _detailRow('Status', status),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (item['birth_certificate'] != null &&
                      item['birth_certificate'].toString().isNotEmpty)
                    _fileSection(
                      context: sheetContext,
                      label: 'Birth Certificate',
                      url: item['birth_certificate'],
                      compact: isCompact,
                    ),
                  if (item['valid_id'] != null &&
                      item['valid_id'].toString().isNotEmpty)
                    _fileSection(
                      context: sheetContext,
                      label: 'Valid ID',
                      url: item['valid_id'],
                      compact: isCompact,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fileSection({
    required BuildContext context,
    required String label,
    required String url,
    required bool compact,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kBorderColor.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: kAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: kText,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap to open the uploaded document.',
                          style: TextStyle(
                            color: kSubText,
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: compact
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showResolvedFile(context, url),
                  child: const Text(
                    'View',
                    style: TextStyle(
                      color: kAccent,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Montserrat',
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

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontFamily: 'Montserrat',
                color: kText,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              (value == null || value.isEmpty) ? 'Not provided' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'OpenSans',
                color: kSubText,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCategoryChip({
    required String label,
    required int count,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeneficiariesList(List<dynamic> items, String type) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    if (items.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.symmetric(vertical: isWide ? 20 : 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
                padding: EdgeInsets.all(isWide ? 32 : 24),
                decoration: BoxDecoration(
                  color: kCardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kBorderColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        type == 'active'
                            ? Icons.verified_user_rounded
                            : Icons.schedule_rounded,
                        size: isWide ? 64 : 56,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No $type beneficiaries found',
                      style: TextStyle(
                        fontSize: isWide ? 22 : 20,
                        fontWeight: FontWeight.w800,
                        color: kText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    // const SizedBox(height: 8),
                    // const Text(
                    //   'No beneficiaries match the selected filter right now.',
                    //   textAlign: TextAlign.center,
                    //   style: TextStyle(
                    //     fontSize: 15,
                    //     color: kSubText,
                    //     fontFamily: 'OpenSans',
                    //     fontWeight: FontWeight.w500,
                    //   ),
                    // ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 20, isWide ? 24 : 16, 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final status = item['status']?.toString();
        final statusColor = _statusColor(status);
        final hasDocuments =
            (item['birth_certificate'] != null &&
                item['birth_certificate'].toString().isNotEmpty) ||
            (item['valid_id'] != null &&
                item['valid_id'].toString().isNotEmpty);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showBeneficiaryDetails(item),
              child: Padding(
                padding: EdgeInsets.all(isWide ? 22 : 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: isWide ? 56 : 52,
                      height: isWide ? 56 : 52,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        color: statusColor,
                        size: isWide ? 30 : 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  status ?? 'Pending',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                              ),
                              if (hasDocuments)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'Documents Ready',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: kPrimary,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            item['full_name'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isWide ? 19 : 17,
                              fontWeight: FontWeight.w800,
                              color: kText,
                              fontFamily: 'Montserrat',
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Relationship: ${item['relationship'] ?? 'Not provided'}',
                            style: TextStyle(
                              fontSize: isWide ? 15 : 14,
                              height: 1.5,
                              color: kText,
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.cake_rounded,
                                size: 16,
                                color: kSubText,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item['dob']?.toString().isNotEmpty == true
                                      ? item['dob'].toString()
                                      : 'Date of birth not provided',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kSubText,
                                    fontFamily: 'OpenSans',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: kSubText,
                                size: 22,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final isCompact = width < 380;
    final totalCount = beneficiaries.length;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                30,
                isWide ? 36 : 28,
                isWide ? 24 : 16,
                isWide ? 32 : 24,
              ),
              decoration: const BoxDecoration(
                color: kPrimary,
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
                  if (widget.showBackButton)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: widget.onBack ?? () => Navigator.pop(context),
                    ),
                  if (widget.showBackButton) const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'My Beneficiaries',
                      style: TextStyle(
                        fontSize: isWide ? 24 : 17,
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
            Padding(
              padding: EdgeInsets.fromLTRB(
                isWide ? 24 : 16,
                16,
                isWide ? 24 : 16,
                0,
              ),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 20 : 16,
                  vertical: isWide ? 18 : 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: kBorderColor.withValues(alpha: 0.45),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.groups_rounded,
                            color: kPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                totalCount == 0
                                    ? 'No beneficiaries added yet'
                                    : '$totalCount beneficiary${totalCount == 1 ? '' : 'ies'} on record',
                                style: TextStyle(
                                  fontSize: isWide ? 18 : 16,
                                  fontWeight: FontWeight.w800,
                                  color: kText,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              // const SizedBox(height: 4),
                              // const Text(
                              //   'Track approved and pending beneficiaries in one place.',
                              //   style: TextStyle(
                              //     fontSize: 13,
                              //     color: kSubText,
                              //     fontFamily: 'OpenSans',
                              //     fontWeight: FontWeight.w600,
                              //     height: 1.4,
                              //   ),
                              // ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTopCategoryChip(
                          label: 'Approved',
                          count: activeBeneficiaries.length,
                          color: kSuccess,
                          background: const Color(0xFFF0FDF4),
                        ),
                        _buildTopCategoryChip(
                          label: 'Pending',
                          count: pendingBeneficiaries.length,
                          color: kWarn,
                          background: const Color(0xFFFFFBEB),
                        ),
                        _buildTopCategoryChip(
                          label: 'Total',
                          count: totalCount,
                          color: kPrimary,
                          background: const Color(0xFFF5F9FF),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isWide ? 24 : 16,
                16,
                isWide ? 24 : 16,
                0,
              ),
              child: AnimatedBuilder(
                animation: _tabController,
                builder: (context, child) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: kBorderColor.withValues(alpha: 0.45),
                      ),
                    ),
                    child: isCompact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.filter_list_rounded,
                                    size: 16,
                                    color: kSubText,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Filter beneficiaries',
                                    style: TextStyle(
                                      color: kSubText,
                                      fontFamily: 'OpenSans',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _NavTab(
                                label: 'Active',
                                icon: Icons.check_circle_rounded,
                                selected: _tabController.index == 0,
                                onTap: () => _tabController.animateTo(0),
                              ),
                              const SizedBox(height: 8),
                              _NavTab(
                                label: 'Pending',
                                icon: Icons.schedule_rounded,
                                selected: _tabController.index == 1,
                                onTap: () => _tabController.animateTo(1),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              const Icon(
                                Icons.filter_list_rounded,
                                size: 16,
                                color: kSubText,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _NavTab(
                                        label: 'Active',
                                        icon: Icons.check_circle_rounded,
                                        selected: _tabController.index == 0,
                                        onTap: () =>
                                            _tabController.animateTo(0),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _NavTab(
                                        label: 'Pending',
                                        icon: Icons.schedule_rounded,
                                        selected: _tabController.index == 1,
                                        onTap: () =>
                                            _tabController.animateTo(1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: kAccent),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildBeneficiariesList(activeBeneficiaries, 'active'),
                        _buildBeneficiariesList(
                          pendingBeneficiaries,
                          'pending',
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isWide ? 24 : 16,
                0,
                isWide ? 24 : 16,
                16,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                    label: const Text(
                      'Add Beneficiary',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => _navigateToAddBeneficiary(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? kAccent.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? kAccent.withValues(alpha: 0.18)
                : kBorderColor.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? kAccent : kSubText),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? kAccent : kSubText,
                fontFamily: 'Montserrat',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
