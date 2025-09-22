import 'package:capstone_app/Beneficiary/addbeneficiary.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:auto_size_text/auto_size_text.dart';

class BeneficiaryPage extends StatefulWidget {
  const BeneficiaryPage({super.key});

  @override
  State<BeneficiaryPage> createState() => _BeneficiaryPageState();
}

class _BeneficiaryPageState extends State<BeneficiaryPage> {
  List<dynamic> beneficiaries = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchBeneficiaries();
  }

  Future<void> fetchBeneficiaries() async {
    setState(() => isLoading = true);

    final user = Supabase.instance.client.auth.currentUser;
    final response = await Supabase.instance.client
        .from('beneficiaries')
        .select()
        .eq('user_id', user!.id);

    if (response is List) {
      setState(() {
        beneficiaries = response;
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
      MaterialPageRoute(builder: (context) => const AddBeneficiaryPage()),
    );
    fetchBeneficiaries();
  }

  void _showBeneficiaryDetails(Map item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: AutoSizeText(
          item['full_name'] ?? 'Beneficiary Details',
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
          maxLines: 1,
          minFontSize: 14,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        launchUrl(Uri.parse(item['birth_certificate']));
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Back button and title
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      AutoSizeText(
                        'Beneficiaries',
                        style: TextStyle(
                          fontSize: isWide ? 28 : 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Montserrat',
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        minFontSize: 16,
                      ),
                    ],
                  ),

                  // Right: Notification and profile
                ],
              ),
            ),
            const Divider(thickness: 1.5, color: Colors.grey),
            const SizedBox(height: 16),

            // LIST
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : beneficiaries.isEmpty
                  ? const Center(
                      child: AutoSizeText(
                        'No beneficiaries added yet.',
                        style: TextStyle(
                          fontSize: 18,
                          fontFamily: 'Montserrat',
                        ),
                        maxLines: 1,
                        minFontSize: 12,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: beneficiaries.length,
                      itemBuilder: (context, index) {
                        final item = beneficiaries[index];
                        return GestureDetector(
                          onTap: () => _showBeneficiaryDetails(item),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person,
                                  color: Colors.indigo,
                                  size: 30,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AutoSizeText(
                                        item['full_name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Montserrat',
                                        ),
                                        maxLines: 1,
                                        minFontSize: 12,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item['relationship'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.black54,
                                          fontFamily: 'OpenSans',
                                        ),
                                      ),
                                      if (item['status'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  item['status'] == 'Approved'
                                                  ? Colors.green[100]
                                                  : item['status'] == 'Rejected'
                                                  ? Colors.red[100]
                                                  : Colors.orange[100],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              item['status'],
                                              style: TextStyle(
                                                color:
                                                    item['status'] == 'Approved'
                                                    ? Colors.green[900]
                                                    : item['status'] ==
                                                          'Rejected'
                                                    ? Colors.red[900]
                                                    : Colors.orange[900],
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'OpenSans',
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (item['birth_certificate'] != null &&
                                    item['birth_certificate']
                                        .toString()
                                        .isNotEmpty)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () {
                                      launchUrl(
                                        Uri.parse(item['birth_certificate']),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // ADD BUTTON
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToAddBeneficiary(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const AutoSizeText(
                    'Add a Beneficiary',
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    minFontSize: 12,
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
