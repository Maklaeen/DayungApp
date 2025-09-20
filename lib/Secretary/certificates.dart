import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final cert = list[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: ListTile(
            leading: const Icon(Icons.article, color: Colors.blue),
            title: Text(cert['deceased_name'] ?? 'Unknown'),
            subtitle: Text(
              "Date of Death: ${_formatDate(cert['date_of_death'])}\n"
              "Submitted: ${_formatDate(cert['submitted_at'])}",
            ),
            trailing: IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              onPressed: () {
                final fileUrl = cert['file_url'];
                if (fileUrl != null && fileUrl.toString().isNotEmpty) {
                  // open pdf in browser or viewer
                  Supabase.instance.client.auth
                      .signOut(); // replace later with file launcher
                }
              },
            ),
          ),
        );
      },
    );
  }
}
