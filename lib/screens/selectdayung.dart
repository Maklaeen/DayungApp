import 'dart:convert';

import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';

class SelectDayungPage extends StatefulWidget {
  const SelectDayungPage({super.key});

  @override
  State<SelectDayungPage> createState() => _SelectDayungPageState();
}

class _SelectDayungPageState extends State<SelectDayungPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _joined = [];

  @override
  void initState() {
    super.initState();
    _fetchJoinedDayung();
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  Future<Map<String, dynamic>> _persistSelectionAndNotify(
    Map<String, dynamic> d,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeDayung(d);
    await prefs.setString('selectedDayungUnit', jsonEncode(normalized));
    await prefs.setString('selectedDayungUnitData', jsonEncode(normalized));
    if (!mounted) return normalized;
    final id = normalized['id'] is int
        ? normalized['id'] as int
        : int.tryParse('${normalized['id']}');
    await context.read<DayungRoleProvider>().refreshRoles(id);
    context.read<DayungUnitProvider>().setDayungUnit(
      '${normalized['name'] ?? 'Dayung'}',
      obj: normalized,
    );
    return normalized;
  }

  Map<String, dynamic> _normalizeDayung(Map<String, dynamic> d) {
    final lat = _toDouble(d['latitude'] ?? d['lat'] ?? d['latitute']);
    final lng = _toDouble(d['longitude'] ?? d['lng'] ?? d['long'] ?? d['lon']);
    return {...d, 'latitude': lat, 'longitude': lng, 'lat': lat, 'lng': lng};
  }

  Future<void> _fetchJoinedDayung() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = _sb.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _joined = [];
        _error = 'Please log in.';
      });
      return;
    }

    try {
      final apps = await _sb
          .from('applications')
          .select('dayung_unit_id, approved_at')
          .eq('user_id', user.id)
          .eq('status', 'approved')
          .order('approved_at', ascending: false);

      final List<dynamic> appsList = apps as List<dynamic>;
      final approvedIds = appsList
          .map((r) => (r as Map)['dayung_unit_id'] as int)
          .toList();
      final officerRows = await _sb
          .from('dayung_units')
          .select('id, secretary_id, treasurer_id, president_id')
          .or(
            'secretary_id.eq.${user.id},treasurer_id.eq.${user.id},president_id.eq.${user.id}',
          );
      final officerIds = (officerRows as List<dynamic>)
          .map((e) => (e as Map)['id'] as int)
          .toList();

      List<int> collectorIds = [];
      try {
        final dc = await _sb
            .from('dayung_collectors')
            .select('dayung_unit_id')
            .eq('user_id', user.id);
        collectorIds = (dc as List<dynamic>)
            .map((e) => (e as Map)['dayung_unit_id'] as int)
            .toList();
      } catch (_) {}

      final ids = <int>{
        ...approvedIds,
        ...officerIds,
        ...collectorIds,
      }.toList();

      if (ids.isEmpty) {
        setState(() {
          _joined = [];
          _loading = false;
        });
        return;
      }

      // Get dayung details (include latitude/longitude)
      final dayungs = await _sb
          .from('dayung_units')
          .select('id, name, barangay, city, province, latitude, longitude')
          .inFilter('id', ids);

      final List<Map<String, dynamic>> joined = (dayungs as List<dynamic>)
          .map((e) => _normalizeDayung(Map<String, dynamic>.from(e)))
          .toList();

      // NEW: tag each as member if in approved list
      final approvedSet = approvedIds.toSet();
      for (final j in joined) {
        final jid = j['id'] is int
            ? j['id'] as int
            : int.tryParse('${j['id']}');
        j['is_member'] = jid != null && approvedSet.contains(jid);
      }

      // Keep membership order first; officer-only units go after
      final approvedOrder = <int, DateTime?>{};
      for (final a in appsList) {
        final m = a as Map<String, dynamic>;
        approvedOrder[m['dayung_unit_id'] as int] = m['approved_at'] != null
            ? DateTime.tryParse(m['approved_at'].toString())
            : null;
      }
      joined.sort((a, b) {
        final da = approvedOrder[a['id'] as int];
        final db = approvedOrder[b['id'] as int];
        if (da == null && db == null) {
          return (a['name'] ?? '').toString().compareTo(
            (b['name'] ?? '').toString(),
          );
        }
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      setState(() {
        _joined = joined;
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message.isEmpty
            ? 'Failed to load dayung (RLS/policy?)'
            : e.message;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Unexpected error loading your dayungs.';
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Your Dayung')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _fetchJoinedDayung)
            : RefreshIndicator(
                onRefresh: _fetchJoinedDayung,
                child: _joined.isEmpty
                    ? _EmptyState(
                        onFind: () async {
                          final selected = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DayungSuggestionsPage(),
                            ),
                          );
                          await _fetchJoinedDayung();
                          if (selected != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Application submitted. Awaiting approval.',
                                ),
                              ),
                            );
                          }
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _joined.length,
                        itemBuilder: (ctx, i) {
                          final d = _joined[i];
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        child: Icon(Icons.home),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          d['name'] ?? 'Dayung',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _address(d),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.check_circle),
                                        label: const Text('Use this Dayung'),
                                        onPressed: () async {
                                          final normalized =
                                              await _persistSelectionAndNotify(
                                                d,
                                              );
                                          if (!mounted) return;
                                          Navigator.pop(
                                            context,
                                            normalized,
                                          ); // pop normalized, not raw d
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                      TextButton.icon(
                                        icon: const Icon(Icons.map), // NEW
                                        label: const Text('View on Map'),
                                        onPressed: () {
                                          final normalized = _normalizeDayung(
                                            d,
                                          );
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => DayungMapPage(
                                                dayung: normalized,
                                                isMember:
                                                    (d['is_member'] == true),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onFind});
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 40),
        Icon(
          Icons.search,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'You have not joined any Dayung yet.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Find your Dayung and submit an application. Once approved, it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.explore),
              label: const Text('Find a Dayung'),
              onPressed: onFind,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
