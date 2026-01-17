import 'package:capstone_app/Beneficiary/addbeneficiary.dart' as add;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:auto_size_text/auto_size_text.dart';

// Modern palette (reuse from dashboard/gcash)
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
const kSuccess = Color(0xFF10B981);
const kCardBg = Color(0xFFFFFFFF);

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
      debugPrint('Failed to fetch beneficiaries');
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
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: kAccent.withOpacity(0.1),
                    child: const Icon(Icons.person_rounded, color: kAccent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AutoSizeText(
                      item['full_name'] ?? 'Beneficiary Details',
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: kText,
                      ),
                      maxLines: 1,
                      minFontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _detailRow('Date of Birth', item['dob']),
              _detailRow('Marital Status', item['marital_status']),
              _detailRow('Relationship', item['relationship']),
              _detailRow('Status', item['status']),
              const SizedBox(height: 16),
              if (item['birth_certificate'] != null &&
                  item['birth_certificate'].toString().isNotEmpty)
                _fileSection(
                  context,
                  label: 'Birth Certificate',
                  url: item['birth_certificate'],
                ),
              if (item['valid_id'] != null &&
                  item['valid_id'].toString().isNotEmpty)
                _fileSection(context, label: 'Valid ID', url: item['valid_id']),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Close'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileSection(
    BuildContext context, {
    required String label,
    required String url,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: kBg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: const Icon(Icons.picture_as_pdf, color: kAccent),
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, color: kText),
          ),
          trailing: TextButton(
            child: const Text(
              'View',
              style: TextStyle(color: kAccent, fontWeight: FontWeight.w600),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text('Could not load image'),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Close'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'Montserrat',
              color: kText,
            ),
          ),
          Expanded(
            child: Text(
              value ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'OpenSans', color: kSubText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeneficiariesList(List<dynamic> beneficiaries, String type) {
    if (beneficiaries.isEmpty) {
      return Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
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
                const Text(
                  'No beneficiaries match the selected filter',
                  style: TextStyle(
                    fontSize: 14,
                    color: kSubText,
                    fontFamily: 'OpenSans',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: beneficiaries.length,
      itemBuilder: (context, index) {
        final item = beneficiaries[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            onTap: () => _showBeneficiaryDetails(item),
            leading: CircleAvatar(
              backgroundColor: kAccent.withOpacity(0.1),
              child: const Icon(Icons.person_rounded, color: kAccent),
            ),
            title: Text(
              item['full_name'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, color: kText),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Relationship: ${item['relationship'] ?? ''}',
                  style: const TextStyle(color: kSubText),
                ),
                if (item['dob'] != null)
                  Text(
                    'DOB: ${item['dob']}',
                    style: const TextStyle(color: kSubText, fontSize: 12),
                  ),
                if (item['status'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item['status'] == 'Approved'
                            ? kSuccess.withOpacity(0.12)
                            : item['status'] == 'Rejected'
                            ? kDanger.withOpacity(0.12)
                            : kWarn.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item['status'],
                        style: TextStyle(
                          color: item['status'] == 'Approved'
                              ? kSuccess
                              : item['status'] == 'Rejected'
                              ? kDanger
                              : kWarn,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            trailing:
                item['birth_certificate'] != null &&
                    item['birth_certificate'].toString().isNotEmpty
                ? const Icon(Icons.picture_as_pdf, color: kAccent)
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 600;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Modern Curved Header
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
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Icon(Icons.group, color: Colors.white, size: 24),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'My Beneficiaries',
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
            // Modern Tab Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: kBg,
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
                              icon: Icons.check_circle_rounded,
                              selected: _tabController.index == 0,
                              onTap: () => _tabController.animateTo(0),
                            ),
                            _NavTab(
                              label: 'Pending',
                              icon: Icons.schedule_rounded,
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
            // List
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
            // Add Button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text(
                    'Add Beneficiary',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  onPressed: () => _navigateToAddBeneficiary(context),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kAccent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
