import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DayungSuggestionsPage extends StatefulWidget {
  const DayungSuggestionsPage({super.key});

  @override
  State<DayungSuggestionsPage> createState() => _DayungSuggestionsPageState();
}

class _DayungSuggestionsPageState extends State<DayungSuggestionsPage> {
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _allDayungs = [];
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _fetchDayungs();
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  Map<String, dynamic> _normalizeDayung(Map<String, dynamic> d) {
    final lat = _toDouble(d['latitude'] ?? d['lat']);
    final lng = _toDouble(d['longitude'] ?? d['lng']);
    return {...d, 'latitude': lat, 'longitude': lng, 'lat': lat, 'lng': lng};
  }

  Future<void> _fetchDayungs() async {
    setState(() => _loading = true);
    try {
      final res = await _sb
          .from('dayung_units')
          .select(
            // INCLUDE latitude/longitude so we don’t fallback
            'id, name, barangay, city, province, description, rules, tags, latitude, longitude',
          )
          .order('name');
      setState(() {
        _allDayungs = List<Map<String, dynamic>>.from(
          res,
        ).map((e) => _normalizeDayung(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading dayung units: $e')));
    }
  }

  List<Map<String, dynamic>> get _filteredDayungs {
    if (_query.trim().isEmpty) return _allDayungs;
    final q = _query.toLowerCase();
    return _allDayungs.where((d) {
      return (d['name'] ?? '').toString().toLowerCase().contains(q) ||
          (d['barangay'] ?? '').toString().toLowerCase().contains(q) ||
          (d['city'] ?? '').toString().toLowerCase().contains(q) ||
          (d['province'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a Dayung')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDayungs,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name, barangay, city, or province',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      setState(() => _query = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_filteredDayungs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'No dayung units found.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ..._filteredDayungs.map((d) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(d['name'] ?? 'Unnamed Unit'),
                        subtitle: Text(
                          [
                                if (d['barangay'] != null) d['barangay'],
                                if (d['city'] != null) d['city'],
                                if (d['province'] != null) d['province'],
                              ]
                              .where(
                                (e) => e != null && e.toString().isNotEmpty,
                              )
                              .join(', '),
                        ),
                        onTap: () async {
                          final normalized = _normalizeDayung(
                            Map<String, dynamic>.from(d),
                          );

                          final lat = normalized['latitude'] as double?;
                          final lng = normalized['longitude'] as double?;
                          if (lat == null || lng == null) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No location set for this Dayung.',
                                ),
                              ),
                            );
                            return;
                          }

                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DayungMapPage(
                                dayung: normalized,
                                isApplied: false,
                                isMember: false,
                              ),
                            ),
                          );
                          if (result != null && mounted) {
                            Navigator.pop(context, result);
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
