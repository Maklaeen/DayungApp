import 'dart:convert';

import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? _currentDayungId;
  String? _currentDayungName;
  Map<String, dynamic>? _currentDayungData;
  bool _loadingDayung = false;

  final List<String> selectedFilters = const [
    'Low fee',
    'Within Davao',
    'Open for all',
    '₱25,000',
  ];

  final Map<String, List<String>> recommended = const {
    'Buhangin Dayung': [
      'Low fee',
      'Open for all',
      'Within Davao City',
      '₱25,900',
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentDayung();
  }

  Future<void> _loadCurrentDayung() async {
    setState(() => _loadingDayung = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _currentDayungId = null;
        _currentDayungName = null;
        _currentDayungData = null;
        _loadingDayung = false;
      });
      return;
    }
    try {
      final userData = await supabase
          .from('users')
          .select('dayung_unit_id')
          .eq('id', user.id)
          .maybeSingle();

      _currentDayungId = userData?['dayung_unit_id'];
      if (_currentDayungId != null) {
        final dayung = await supabase
            .from('dayung_units')
            .select('id, name, barangay, city, province, latitude, longitude')
            .eq('id', _currentDayungId as Object)
            .maybeSingle();

        setState(() {
          _currentDayungData = dayung != null
              ? Map<String, dynamic>.from(dayung)
              : null;
          _currentDayungName = dayung?['name'];
          _loadingDayung = false;
        });
      } else {
        setState(() {
          _currentDayungData = null;
          _currentDayungName = null;
          _loadingDayung = false;
        });
      }
    } on PostgrestException catch (_) {
      setState(() => _loadingDayung = false);
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
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    final headerStyle = TextStyle(
      fontSize: isWide ? 30 : 22,
      fontWeight: FontWeight.bold,
      fontFamily: 'Montserrat',
    );
    final sectionTitleStyle = TextStyle(
      fontSize: isWide ? 20 : 16,
      fontWeight: FontWeight.w600,
      fontFamily: 'Montserrat',
    );
    final bodyTextStyle = TextStyle(
      fontSize: isWide ? 18 : 14,
      fontFamily: 'OpenSans',
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 32),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                  AutoSizeText(
                    'Profile settings',
                    style: headerStyle,
                    maxLines: 1,
                    minFontSize: 16,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Current Dayung card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AutoSizeText(
                        'Current Dayung',
                        style: sectionTitleStyle,
                        maxLines: 1,
                        minFontSize: 12,
                      ),
                      const SizedBox(height: 6),
                      if (_loadingDayung)
                        const LinearProgressIndicator(minHeight: 2)
                      else ...[
                        Row(
                          children: [
                            const Icon(Icons.home, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AutoSizeText(
                                _currentDayungName ?? 'No Dayung Assigned',
                                style: bodyTextStyle.copyWith(
                                  color: _currentDayungName != null
                                      ? Colors.blue
                                      : Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                minFontSize: 10,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Refresh',
                              onPressed: _loadCurrentDayung,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        if (_currentDayungData != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _address(_currentDayungData!),
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_currentDayungData != null &&
                                _currentDayungData!['latitude'] != null &&
                                _currentDayungData!['longitude'] != null)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('View on Map'),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DayungMapPage(
                                        dayung: _currentDayungData!,
                                        isApplied: true, // disable apply on map
                                        isMember: true, // mark as current
                                      ),
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Change'),
                              onPressed: () async {
                                final selected = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SelectDayungPage(),
                                  ),
                                );

                                // If user picked a Dayung, update users.dayung_unit_id
                                if (!mounted) return;
                                if (selected != null &&
                                    selected is Map<String, dynamic>) {
                                  final supabase = Supabase.instance.client;
                                  final user = supabase.auth.currentUser;
                                  if (user != null && selected['id'] != null) {
                                    try {
                                      await supabase
                                          .from('users')
                                          .update({
                                            'dayung_unit_id': selected['id'],
                                          })
                                          .eq('id', user.id);

                                      // Persist the new selection to SharedPreferences so ClaimsPage picks it up
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.setString(
                                        'selectedDayungUnit',
                                        jsonEncode({
                                          'id': selected['id'],
                                          'name': selected['name'],
                                          'barangay': selected['barangay'],
                                          'city': selected['city'],
                                        }),
                                      );

                                      // (Optional) notify a provider if you use one
                                      // context.read<DayungUnitProvider>().setDayungName(selected['name']);

                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Current Dayung updated to ${selected['name']}',
                                          ),
                                        ),
                                      );
                                    } on PostgrestException catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to set Dayung: ${e.message}',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }

                                await _loadCurrentDayung(); // refresh UI
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Apply a Dayung
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Apply a Dayung'),
                  onPressed: () async {
                    final selectedDayung = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DayungSuggestionsPage(),
                      ),
                    );
                    if (selectedDayung != null &&
                        selectedDayung is Map<String, dynamic>) {
                      // Application was sent via RPC in DayungSuggestionsPage
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Application sent to ${selectedDayung['name']}!',
                          ),
                        ),
                      );
                      await _loadCurrentDayung(); // refresh in case approval was instant
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Filters
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          AutoSizeText(
                            'Filters',
                            style: sectionTitleStyle,
                            maxLines: 1,
                            minFontSize: 12,
                          ),
                          TextButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            label: Text(
                              'Edit',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: isWide ? 16 : 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AutoSizeText(
                        'Selected tags:',
                        style: bodyTextStyle,
                        maxLines: 1,
                        minFontSize: 10,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: selectedFilters.map((tag) {
                          return Chip(
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            label: Text(
                              tag,
                              style: TextStyle(fontSize: isWide ? 16 : 13),
                            ),
                            backgroundColor: Colors.grey.shade200,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              AutoSizeText(
                'Recommended for you',
                style: sectionTitleStyle,
                maxLines: 1,
                minFontSize: 12,
              ),
              const SizedBox(height: 12),

              // Recommendations
              Expanded(
                child: ListView.builder(
                  itemCount: recommended.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, idx) {
                    final key = recommended.keys.elementAt(idx);
                    final tags = recommended[key]!;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AutoSizeText(
                              key,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 15,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Montserrat',
                              ),
                              maxLines: 1,
                              minFontSize: 12,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: tags.map((t) {
                                return Chip(
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  label: Text(
                                    t,
                                    style: TextStyle(
                                      fontSize: isWide ? 16 : 13,
                                    ),
                                  ),
                                  backgroundColor: Colors.blue.shade50,
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
