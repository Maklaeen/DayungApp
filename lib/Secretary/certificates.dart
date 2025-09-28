import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
    _tabController = TabController(
      length: 1,
      vsync: this,
    ); // pwede dagdagan (Pending, Approved…)
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

      // ignore: unnecessary_type_check
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
      appBar: AppBar(
        title: const Text("Certificates"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "All Certificates")],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildCertificatesList(_certificates)],
            ),
    );
  }

  Widget _buildCertificatesList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const Center(child: Text("No certificates found"));
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 32, thickness: 1, color: Color(0xFFE1E4E8)),
      itemBuilder: (context, index) {
        final cert = list[index];
        final fileUrl = cert['file_url'];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description,
                    size: 40,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      cert['deceased_name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: Color(0xFF1F2937),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          fileUrl != null && fileUrl.toString().isNotEmpty
                          ? () async {
                              // Open PDF in browser or viewer
                              if (await canLaunchUrl(Uri.parse(fileUrl))) {
                                await launchUrl(
                                  Uri.parse(fileUrl),
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Color(0xFF1F2937),
                        side: const BorderSide(color: Color(0xFF1F2937)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('View Certificate'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // TODO: Validate logic here
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF0D47A1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Validate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
