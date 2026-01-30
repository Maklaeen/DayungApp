import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Modern palette (reuse from other files)
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFFAFAF7);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kText = Color(0xFF1F2937);

class DayungSuggestionsPage extends StatefulWidget {
  const DayungSuggestionsPage({super.key});

  @override
  State<DayungSuggestionsPage> createState() => _DayungSuggestionsPageState();
}

class _DayungSuggestionsPageState extends State<DayungSuggestionsPage> {
  final _sb = Supabase.instance.client;
  final alreadyApplied = false;

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

  String _address(Map<String, dynamic> d) {
    return [
      if (d['barangay'] != null) d['barangay'],
      if (d['city'] != null) d['city'],
      if (d['province'] != null) d['province'],
    ].where((e) => e != null && e.toString().isNotEmpty).join(', ');
  }

  Future<void> _fetchDayungs() async {
    setState(() => _loading = true);
    try {
      final res = await _sb
          .from('dayung_units')
          .select(
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
      if (!mounted) return;
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
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Modern Curved Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kPrimaryDark, kPrimary],
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find a Dayung',
                    style: TextStyle(
                      fontSize: isWide ? 28 : 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Montserrat',
                      letterSpacing: 0.3,
                      shadows: const [
                        Shadow(
                          color: Colors.black26,
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Browse and search for Dayung units near you.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 15,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Modern Search Bar
                  Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(24),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by name, barangay, city, or province',
                        prefixIcon: const Icon(Icons.search, color: kPrimary),
                        border: InputBorder.none,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
            // Main Content
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: _buildBody(context, isWide),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isWide) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    if (_filteredDayungs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: kSubText.withOpacity(0.25),
              ),
              const SizedBox(height: 18),
              Text(
                'No dayung units found.',
                style: TextStyle(
                  color: kSubText,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your search or check back later.',
                style: TextStyle(
                  color: kSubText.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDayungs,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          ..._filteredDayungs.map((d) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: Card(
                elevation: 4,
                color: kCardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: kPrimary.withOpacity(0.10),
                        child: const Icon(
                          Icons.home,
                          color: kPrimary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d['name'] ?? 'Unnamed Unit',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: kText,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _address(d),
                              style: const TextStyle(
                                color: kSubText,
                                fontSize: 14,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: Icon(
                          alreadyApplied ? Icons.check_circle : Icons.map,
                          color: alreadyApplied ? kSubText : Colors.white,
                        ),
                        label: Text(
                          alreadyApplied ? 'Applied' : 'Map',
                          style: TextStyle(
                            color: alreadyApplied ? kSubText : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: alreadyApplied ? kCardBg : kPrimary,
                          foregroundColor: alreadyApplied
                              ? kSubText
                              : Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: alreadyApplied
                              ? BorderSide(color: kSubText.withOpacity(0.3))
                              : BorderSide.none,
                        ),
                        onPressed: alreadyApplied
                            ? null
                            : () async {
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
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          // Modern Dashboard Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.dashboard, color: Colors.white),
              label: const Text(
                'Go to dashboard',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'Montserrat',
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const MemberDashboardPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
