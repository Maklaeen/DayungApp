import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/President/manage_rules.dart';

class DayungSettingsPage extends StatefulWidget {
  const DayungSettingsPage({super.key});

  @override
  State<DayungSettingsPage> createState() => _DayungSettingsPageState();
}

class _DayungSettingsPageState extends State<DayungSettingsPage> {
  String? _currentDayungName;
  Map<String, dynamic>? _currentDayungData;
  bool _loadingDayung = false;

  final List<String> selectedFilters = const [
    '100',
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString('selectedDayungUnitData') ??
          prefs.getString('selectedDayungUnit');

      if (raw == null) {
        setState(() {
          _currentDayungName = null;
          _currentDayungData = null;
          _loadingDayung = false;
        });
        return;
      }

      final obj = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      setState(() {
        _currentDayungName = (obj['name'] ?? 'Dayung').toString();
        _currentDayungData = obj;
        _loadingDayung = false;
      });

      // IMPORTANT: Do NOT refresh DayungRoleProvider here.
      // Role refresh only when user explicitly changes Dayung.
    } catch (_) {
      setState(() {
        _currentDayungName = null;
        _currentDayungData = null;
        _loadingDayung = false;
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
                    'Dayung settings',
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
                                final messenger = ScaffoldMessenger.of(context);
                                final roleProvider = context
                                    .read<DayungRoleProvider>();
                                final unitProvider = context
                                    .read<DayungUnitProvider>();
                                final selected = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SelectDayungPage(),
                                  ),
                                );
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

                                      // Persist both keys so all pages read the same source
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.setString(
                                        'selectedDayungUnit',
                                        jsonEncode({
                                          'id': selected['id'],
                                          'name': selected['name'],
                                          'barangay': selected['barangay'],
                                          'city': selected['city'],
                                          'province': selected['province'],
                                        }),
                                      );
                                      await prefs.setString(
                                        'selectedDayungUnitData',
                                        jsonEncode(selected),
                                      );

                                      // Refresh role + broadcast name/object so headers/pages rebuild consistently
                                      final id = selected['id'] as int?;
                                      if (!mounted) return;
                                      await roleProvider.refreshRoles(id);
                                      unitProvider.setDayungUnit(
                                        '${selected['name'] ?? 'Dayung'}',
                                        obj: {
                                          'id': selected['id'],
                                          'name': selected['name'],
                                          'barangay': selected['barangay'],
                                          'city': selected['city'],
                                          'province': selected['province'],
                                        },
                                      );

                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Current Dayung updated to ${selected['name']}',
                                          ),
                                        ),
                                      );
                                    } on PostgrestException catch (e) {
                                      if (!mounted) return;
                                      messenger.showSnackBar(
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
                    final messenger = ScaffoldMessenger.of(context);
                    final selectedDayung = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DayungSuggestionsPage(),
                      ),
                    );
                    if (!mounted) return;
                    if (selectedDayung != null &&
                        selectedDayung is Map<String, dynamic>) {
                      // Application was sent via RPC in DayungSuggestionsPage
                      messenger.showSnackBar(
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

              if (context.watch<DayungRoleProvider>().isPresident) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.rule_folder_rounded),
                    label: const Text('Manage Rules'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ManageRulesPagePres(),
                        ),
                      );
                    },
                  ),
                ),
              ],

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

                    // Dummy data for demo, dapat kunin mo ang buong dayung object sa production
                    final dayungData = {
                      'name': key,
                      'barangay': 'Sample Barangay',
                      'city': 'Sample City',
                      'province': 'Sample Province',
                      'latitude':
                          7.123, // Palitan ng totoong lat/lng kung meron
                      'longitude': 125.612,
                    };

                    return GestureDetector(
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DayungMapPage(
                              dayung: dayungData,
                              isApplied: false,
                              isMember: false,
                            ),
                          ),
                        );
                        if (!mounted) return;
                        if (result != null) {
                          // Optional: handle result (e.g., show snackbar)
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Application sent to ${result['name']}!',
                              ),
                            ),
                          );
                          await _loadCurrentDayung();
                        }
                      },
                      child: Card(
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
