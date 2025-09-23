import 'package:flutter/material.dart';
import 'package:capstone_app/pages/deathnoticedetail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecentDeathNotices extends StatefulWidget {
  const RecentDeathNotices({Key? key}) : super(key: key);

  @override
  State<RecentDeathNotices> createState() => _RecentDeathNoticesState();
}

class _RecentDeathNoticesState extends State<RecentDeathNotices> {
  List<Map<String, dynamic>> _deathNotices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDeathNotices();
    // Optional: Listen for real-time updates
    Supabase.instance.client
        .from('death_notices')
        .stream(primaryKey: ['id'])
        .listen((data) {
          setState(() {
            _deathNotices = List<Map<String, dynamic>>.from(data);
            _loading = false;
          });
        });
  }

  Future<void> _fetchDeathNotices() async {
    final response = await Supabase.instance.client
        .from('death_notices')
        .select('id, name, date_of_death, barangay')
        .order('date_of_death', ascending: false);
    setState(() {
      _deathNotices = List<Map<String, dynamic>>.from(response);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'Deaths and Vigil locations',
          style: TextStyle(
            fontSize: 24 * textScale,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _deathNotices.isEmpty
          ? const Center(child: Text('No death notices found.'))
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: _deathNotices.length,
              itemBuilder: (context, index) {
                final notice = _deathNotices[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    leading: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.indigo,
                      child: const Icon(
                        Icons.person,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      notice['name'] ?? '',
                      style: TextStyle(
                        fontSize: 18 * textScale,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        notice['date_of_death'] ?? '',
                        style: TextStyle(
                          fontSize: 16 * textScale,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 20 * textScale,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeathNoticeDetail(
                            name: notice['name'] ?? '',
                            date: notice['date_of_death'] ?? '',
                            barangay: notice['barangay'] ?? '',
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
