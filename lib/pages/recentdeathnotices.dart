import 'dart:async';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/pages/deathnoticedetail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ...existing code...
class RecentDeathNotices extends StatefulWidget {
  final int? dayungUnitId;
  const RecentDeathNotices({Key? key, this.dayungUnitId}) : super(key: key);

  @override
  State<RecentDeathNotices> createState() => _RecentDeathNoticesState();
}

class _RecentDeathNoticesState extends State<RecentDeathNotices> {
  bool _loading = true;

  // Split lists
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _beneficiaries = [];

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();

    if (widget.dayungUnitId == null) {
      setState(() => _loading = false);
      return;
    }

    _fetchDeathNotices();

    // Realtime stream filtered by dayung
    final client = Supabase.instance.client;
    _sub = client
        .from('death_notices')
        .stream(primaryKey: ['id'])
        .eq('dayung_unit_id', widget.dayungUnitId as Object)
        .listen((data) {
          _applySplit(List<Map<String, dynamic>>.from(data));
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _applySplit(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final ad = (a['date_of_death'] ?? '').toString();
      final bd = (b['date_of_death'] ?? '').toString();
      return bd.compareTo(ad); // desc
    });
    final members = rows
        .where((r) => (r['deceased_type'] ?? 'member') == 'member')
        .toList();
    final beneficiaries = rows
        .where((r) => r['deceased_type'] == 'beneficiary')
        .toList();

    setState(() {
      _members = members;
      _beneficiaries = beneficiaries;
      _loading = false;
    });
  }

  Future<void> _fetchDeathNotices() async {
    if (widget.dayungUnitId == null) {
      setState(() {
        _members = [];
        _beneficiaries = [];
        _loading = false;
      });
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('death_notices')
          .select(
            'id, name, date_of_death, barangay, dayung_unit_id, deceased_type, dob, deceased_age',
          )
          .eq('dayung_unit_id', widget.dayungUnitId as Object)
          .order('date_of_death', ascending: false);

      _applySplit(List<Map<String, dynamic>>.from(response as List));
    } catch (_) {
      setState(() {
        _members = [];
        _beneficiaries = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

    if (widget.dayungUnitId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Deaths and Vigil locations'),
          backgroundColor: Colors.white,
          elevation: 1,
          iconTheme: const IconThemeData(color: Colors.black87),
        ),
        backgroundColor: Colors.grey.shade100,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Apply a Dayung first'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DayungSuggestionsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
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
          bottom: const TabBar(
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.black54,
            indicatorColor: Colors.indigo,
            tabs: [
              Tab(text: 'Members'),
              Tab(text: 'Beneficiaries'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildList(context, _members, textScale),
                  _buildList(context, _beneficiaries, textScale),
                ],
              ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<Map<String, dynamic>> items,
    double textScale,
  ) {
    if (items.isEmpty) {
      return const Center(child: Text('No death notices found.'));
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final notice = items[index];
        final name = (notice['name'] ?? '').toString();
        final dod = (notice['date_of_death'] ?? '').toString();
        final barangay = notice['barangay']?.toString();
        // Optional: show DOB/Age if present in the row
        final dob = notice['dob']?.toString();
        final age = notice['deceased_age'];

        final subtitle = StringBuffer();
        if (dob != null && dob.isNotEmpty) {
          subtitle.write('DOB: $dob • ');
        }
        subtitle.write('DOD: $dod');
        if (age is int) {
          subtitle.write(' • Age: $age');
        }
        if (barangay != null && barangay.isNotEmpty) {
          subtitle.write(' • $barangay');
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              backgroundColor: (notice['deceased_type'] == 'beneficiary')
                  ? Colors.purple
                  : Colors.indigo,
              child: const Icon(Icons.person, size: 32, color: Colors.white),
            ),
            title: Text(
              name,
              style: TextStyle(
                fontSize: 18 * textScale,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle.toString(),
                style: TextStyle(
                  fontSize: 14 * textScale,
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
                  builder: (_) => DeathNoticeDetail.byNoticeId(
                    noticeId: notice['id'] as int,
                    dayungUnitId: widget.dayungUnitId,
                    // Optional optimistic values
                    name: notice['name']?.toString(),
                    date: notice['date_of_death']?.toString(),
                    barangay: notice['barangay']?.toString(),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
