import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class DayungSuggestionsPage extends StatefulWidget {
  const DayungSuggestionsPage({super.key});

  @override
  State<DayungSuggestionsPage> createState() => _DayungSuggestionsPageState();
}

class _DayungSuggestionsPageState extends State<DayungSuggestionsPage> {
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _allDayungs = [];
  bool _loading = true;
  Position? _userPosition;
  int? _currentDayungId;
  String _query = '';
  Set<int> _appliedDayungIds = {}; // to disable Apply if already applied

  static const double highlightDistanceMeters = 3500; // 3.5 km

  @override
  void initState() {
    super.initState();
    _fetchSuggestions();
  }

  Future<void> _fetchSuggestions() async {
    setState(() => _loading = true);

    // Get user location (ask permission)
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _userPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } else {
        _userPosition = null;
      }
    } catch (_) {
      _userPosition = null;
    }

    // Fetch all dayung units
    final data = await _sb
        .from('dayung_units')
        .select('id, name, barangay, city, province, latitude, longitude');

    final dayungs = List<Map<String, dynamic>>.from(data);

    // Sort by distance if we have location, otherwise by name
    if (_userPosition != null) {
      dayungs.sort((a, b) {
        final distA = _distanceToUser(a);
        final distB = _distanceToUser(b);
        return distA.compareTo(distB);
      });
    } else {
      dayungs.sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
          (b['name'] ?? '').toString(),
        ),
      );
    }

    setState(() {
      _allDayungs = dayungs;
      _loading = false;
    });

    await Future.wait([_loadAppliedIds(), _loadMembershipId()]);
  }

  Future<void> _loadMembershipId() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final me = await _sb
          .from('users')
          .select('dayung_unit_id')
          .eq('id', uid)
          .maybeSingle();
      setState(() {
        _currentDayungId = me?['dayung_unit_id'] as int?;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadAppliedIds() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final apps = await _sb
          .from('applications')
          .select('dayung_unit_id')
          .eq('user_id', user.id);
      final set = <int>{};
      for (final row in List<Map<String, dynamic>>.from(apps)) {
        final id = row['dayung_unit_id'];
        if (id is int) set.add(id);
      }
      setState(() => _appliedDayungIds = set);
    } catch (_) {
      // If RLS blocks select, just ignore and keep buttons enabled
    }
  }

  double _distanceToUser(Map<String, dynamic> dayung) {
    if (_userPosition == null ||
        dayung['latitude'] == null ||
        dayung['longitude'] == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      (dayung['latitude'] as num).toDouble(),
      (dayung['longitude'] as num).toDouble(),
    );
  }

  String _formatDistance(double? meters) {
    if (meters == null || meters == double.infinity) return '';
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
  }

  String _address(Map<String, dynamic> d) {
    final parts = <String>[
      if ((d['barangay'] ?? '').toString().isNotEmpty) d['barangay'],
      if ((d['city'] ?? '').toString().isNotEmpty) d['city'],
      if ((d['province'] ?? '').toString().isNotEmpty) d['province'],
    ];
    return parts.join(', ');
  }

  Future<void> _applyToDayung(Map<String, dynamic> dayung) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in to apply.')));
      return;
    }
    try {
      final res = await _sb.rpc(
        'apply_to_dayung',
        params: {'p_dayung_unit_id': dayung['id']},
      );
      if (res != null) {
        setState(() {
          _appliedDayungIds.add(dayung['id'] as int);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Application sent to ${dayung['name']}!')),
        );
        // Return to previous page (e.g., Settings) with selected dayung
        if (mounted) Navigator.pop(context, dayung);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply. Please try again.')),
        );
      }
    } on PostgrestException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Apply failed: ${e.message.isEmpty ? 'Unexpected error' : e.message}',
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allDayungs.where((d) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      final name = (d['name'] ?? '').toString().toLowerCase();
      final addr = _address(d).toLowerCase();
      return name.contains(q) || addr.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Find a Dayung')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchSuggestions,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name or location',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 12),
                  if (_userPosition == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: const [
                          Icon(Icons.location_off, color: Colors.orange),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Location permission not granted. Sorting by name.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: Text('No dayung units found.')),
                    ),
                  ...filtered.map((d) {
                    final distance =
                        (_userPosition != null &&
                            d['latitude'] != null &&
                            d['longitude'] != null)
                        ? _distanceToUser(d)
                        : null;
                    final isNear =
                        distance != null &&
                        distance != double.infinity &&
                        distance <= highlightDistanceMeters;
                    final isApplied = _appliedDayungIds.contains(
                      d['id'] as int,
                    );
                    final isMember =
                        _currentDayungId != null && _currentDayungId == d['id'];

                    return Card(
                      color: isNear ? Colors.green[50] : null,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title + distance chip
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    d['name'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (distance != null &&
                                    distance != double.infinity)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.place,
                                          size: 14,
                                          color: Colors.blue,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDistance(distance),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _address(d),
                              style: const TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 10),

                            // Actions
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.map_outlined),
                                  label: const Text('View Map'),
                                  onPressed: () async {
                                    final selected = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DayungMapPage(
                                          dayung: d,
                                          isApplied: isApplied || isMember,
                                          isMember: isMember,
                                        ),
                                      ),
                                    );
                                    if (selected != null &&
                                        selected is Map<String, dynamic>) {
                                      // Extra guard in case state changed while on map
                                      final id = selected['id'] as int?;
                                      final nowApplied =
                                          id != null &&
                                          _appliedDayungIds.contains(id);
                                      final nowMember =
                                          _currentDayungId != null &&
                                          _currentDayungId == id;
                                      if (nowMember) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'You are already a member of this Dayung.',
                                            ),
                                          ),
                                        );
                                      } else if (nowApplied) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'You have already applied to this Dayung.',
                                            ),
                                          ),
                                        );
                                      } else {
                                        await _applyToDayung(selected);
                                        await _loadAppliedIds();
                                      }
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  icon: Icon(
                                    isMember
                                        ? Icons.verified
                                        : (isApplied
                                              ? Icons.check_circle
                                              : Icons.how_to_reg),
                                  ),
                                  label: Text(
                                    isMember
                                        ? 'Your Dayung'
                                        : (isApplied ? 'Applied' : 'Apply'),
                                  ),
                                  onPressed: (isApplied || isMember)
                                      ? null
                                      : () => _applyToDayung(d),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
