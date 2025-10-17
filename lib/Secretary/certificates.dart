import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Modern color palette
const Color kPrimary = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFF8FAFC);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class CertificatesPage extends StatefulWidget {
  const CertificatesPage({super.key});

  @override
  State<CertificatesPage> createState() => _CertificatesPageState();
}

class _CertificatesPageState extends State<CertificatesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  List<Map<String, dynamic>> _certificates = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _fetchCertificates();
  }

  Future<void> _fetchCertificates() async {
    final supabase = Supabase.instance.client;
    try {
      final response = await supabase
          .from('certificates')
          .select(
            'id, deceased_name, date_of_death, submitted_at, file_url, user_id',
          )
          .order('submitted_at', ascending: false);

      if (response is List) {
        setState(() {
          _certificates = response
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint("Error fetching certificates: $e\n$st");
      setState(() => _loading = false);
    }
  }

  String _formatDate(dynamic ds) {
    if (ds == null) return '';
    try {
      final d = DateTime.parse(ds.toString());
      return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return ds.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Curved Header with Back Button
            Container(
              padding: const EdgeInsets.fromLTRB(8, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kPrimaryDark,
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
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.description, color: Colors.white, size: 28),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Certificates',
                      style: TextStyle(
                        fontSize: 22,
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
            // Tabs (if you want to add more in the future)
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
              child: TabBar(
                controller: _tabController,
                labelColor: kPrimaryDark,
                unselectedLabelColor: kSubText,
                indicatorColor: kPrimary,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                tabs: const [Tab(text: "All Certificates")],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: kPrimary),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [_buildCertificatesList(_certificates)],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificatesList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(Icons.info_outline, color: kSubText, size: 48),
                const SizedBox(height: 16),
                const Text(
                  "No certificates found.",
                  style: TextStyle(
                    fontSize: 16,
                    color: kSubtleText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchCertificates,
      child: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 32, thickness: 1, color: Color(0xFFE1E4E8)),
        itemBuilder: (context, index) {
          final cert = list[index];
          final fileUrl = cert['file_url'];
          return Card(
            elevation: 3,
            color: kCardBg,
            margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: kPrimary.withOpacity(0.15),
                        child: const Icon(
                          Icons.description,
                          color: kPrimaryDark,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          cert['deceased_name'] ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: kPrimaryDark,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _infoRow(
                    Icons.event,
                    'Date of Death: ${_formatDate(cert['date_of_death'])}',
                  ),
                  _infoRow(
                    Icons.upload_file,
                    'Submitted: ${_formatDate(cert['submitted_at'])}',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              fileUrl != null && fileUrl.toString().isNotEmpty
                              ? () async {
                                  if (await canLaunchUrl(Uri.parse(fileUrl))) {
                                    await launchUrl(
                                      Uri.parse(fileUrl),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                }
                              : null,
                          icon: const Icon(
                            Icons.picture_as_pdf,
                            color: kPrimaryDark,
                          ),
                          label: const Text('View Certificate'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kPrimaryDark,
                            side: const BorderSide(color: kPrimaryDark),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // TODO: Validate logic here
                          },
                          icon: const Icon(Icons.verified, size: 20),
                          label: const Text('Validate'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kSubText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: kNeutralText),
            ),
          ),
        ],
      ),
    );
  }
}
