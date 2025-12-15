import 'package:capstone_app/Beneficiary/addbeneficiary.dart' as add;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:auto_size_text/auto_size_text.dart';

// Additional colors for beneficiary-specific styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const double kEdge = 16;

class BeneficiaryPage extends StatefulWidget {
  const BeneficiaryPage({super.key});

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

    // ignore: unnecessary_type_check
    if (response is List) {
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
    } else {
      setState(() => isLoading = false);
      print('Failed to fetch beneficiaries');
    }
  }

  Future<void> _navigateToAddBeneficiary(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const add.AddBeneficiaryPage()),
    );
    fetchBeneficiaries();
  }

  void _showBeneficiaryDetails(Map item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              AutoSizeText(
                item['full_name'] ?? 'Beneficiary Details',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
                maxLines: 1,
                minFontSize: 14,
              ),
              const SizedBox(height: 16),
              _detailRow('Date of Birth', item['dob']),
              _detailRow('Marital Status', item['marital_status']),
              _detailRow('Relationship', item['relationship']),
              _detailRow('Status', item['status']),
              const SizedBox(height: 12),
              if (item['birth_certificate'] != null &&
                  item['birth_certificate'].toString().isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Birth Certificate:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.network(
                                    item['birth_certificate'],
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Text('Could not load image'),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'View File',
                        style: TextStyle(
                          color: Colors.blue[800],
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              // --- ADD THIS BLOCK FOR VALID ID ---
              if (item['valid_id'] != null &&
                  item['valid_id'].toString().isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'Valid ID:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.network(
                                    item['valid_id'],
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Text('Could not load image'),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'View File',
                        style: TextStyle(
                          color: Colors.blue[800],
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              // --- END OF BLOCK ---
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'Montserrat',
            ),
          ),
          Expanded(
            child: Text(
              value ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'OpenSans'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeneficiariesList(List<dynamic> beneficiaries, String type) {
    if (beneficiaries.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: kSubText),
              const SizedBox(height: 16),
              Text(
                'No $type beneficiaries found',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kText,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No beneficiaries match the selected filter',
                style: const TextStyle(
                  fontSize: 14,
                  color: kSubText,
                  fontFamily: 'OpenSans',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: beneficiaries.length,
      itemBuilder: (context, index) {
        final item = beneficiaries[index];
        return GestureDetector(
          onTap: () => _showBeneficiaryDetails(item),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: kPrimary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['full_name'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Montserrat',
                          color: kText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['relationship'] ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: kSubText,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                      if (item['dob'] != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'DOB: ${item['dob']}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: kSubText,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      ],
                      if (item['status'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: item['status'] == 'Approved'
                                  ? kSuccess.withValues(alpha: 0.1)
                                  : item['status'] == 'Rejected'
                                  ? kDanger.withValues(alpha: 0.1)
                                  : kWarn.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item['status'],
                              style: TextStyle(
                                color: item['status'] == 'Approved'
                                    ? kSuccess
                                    : item['status'] == 'Rejected'
                                    ? kDanger
                                    : kWarn,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'OpenSans',
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (item['birth_certificate'] != null &&
                    item['birth_certificate'].toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf,
                      color: Colors.blue,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              // HEADER
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                color: kPrimary,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.inbox_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Beneficiaries',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Tab Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                color: const Color(0xFFF1F5F9),
                child: Row(
                  children: [
                    Icon(Icons.filter_list_rounded, size: 16, color: kSubText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, child) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _NavTab(
                                label: 'Active',
                                icon: Icons.schedule_rounded,
                                selected: _tabController.index == 0,
                                onTap: () => _tabController.animateTo(0),
                              ),
                              _NavTab(
                                label: 'Pending',
                                icon: Icons.check_circle_rounded,
                                selected: _tabController.index == 1,
                                onTap: () => _tabController.animateTo(1),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // LIST
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBeneficiariesList(
                            pendingBeneficiaries,
                            'Active',
                          ),
                          _buildBeneficiariesList(
                            activeBeneficiaries,
                            'Pending',
                          ),
                        ],
                      ),
              ),

              // ADD BUTTON
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToAddBeneficiary(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kSuccess,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'Add a Beneficiary',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w600,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: selected ? kPrimary : kSubText),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? kPrimary : kSubText,
                  fontFamily: 'Montserrat',
                ),
              ),
            ],
          ),
          if (selected) ...[
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: label.length * 8.0,
              decoration: BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
