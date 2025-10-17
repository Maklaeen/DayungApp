import 'dart:convert';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:capstone_app/screens/selectdayung.dart' hide kPrimary, kWarn, kAccent;
import 'package:capstone_app/screens/dayung_map_page.dart' as map;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Additional colors for manage dayung styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF047857);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const double kEdge = 16;

class DayungProfile extends StatefulWidget {
  const DayungProfile({super.key});

  @override
  State<DayungProfile> createState() => _DayungProfileState();
}

class _DayungProfileState extends State<DayungProfile> {
  int? _currentDayungId;
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
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E40AF), // Deep blue gradient
              Color(0xFF3B82F6), // Medium blue
              Color(0xFFF8FAFC), // Light background
            ],
            stops: [0.0, 0.15, 0.15],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Modern Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context, true),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Manage Dayung',
                        style: TextStyle(
                          fontSize: isWide ? 24 : 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                          shadows: [
                            const Shadow(
                              color: Colors.black26,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 20,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Current Dayung card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kPrimary.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: kPrimary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(Icons.home_rounded, color: Colors.white, size: 14),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        'Current Dayung',
                                        style: sectionTitleStyle.copyWith(
                                          color: kText,
                                          fontSize: isWide ? 16 : 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_loadingDayung)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: kPrimary.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            color: kPrimary,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Loading dayung information...',
                                        style: TextStyle(
                                          color: kPrimary,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: _currentDayungName != null 
                                            ? kSuccess.withValues(alpha: 0.08)
                                            : kWarn.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(
                                        _currentDayungName != null 
                                            ? Icons.check_circle_rounded
                                            : Icons.warning_amber_rounded,
                                        color: _currentDayungName != null ? kSuccess : kWarn,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        _currentDayungName ?? 'No Dayung Assigned',
                                        style: bodyTextStyle.copyWith(
                                          color: _currentDayungName != null
                                              ? kText
                                              : kSubText,
                                          fontWeight: FontWeight.w500,
                                          fontSize: isWide ? 14 : 12,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: kPrimary.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: IconButton(
                                        tooltip: 'Refresh',
                                        onPressed: _loadCurrentDayung,
                                        icon: const Icon(Icons.refresh_rounded, color: kPrimary, size: 12),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_currentDayungData != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: kSubText.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: kSubText.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: Icon(Icons.location_on_rounded, color: kSubText, size: 12),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _address(_currentDayungData!),
                                            style: TextStyle(
                                              color: kSubText,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              fontFamily: 'OpenSans',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    if (_currentDayungData != null &&
                                        _currentDayungData!['latitude'] != null &&
                                        _currentDayungData!['longitude'] != null)
                                      Expanded(
                                        child: Container(
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: kAccent,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(8),
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => map.DayungMapPage(
                                                      dayung: _currentDayungData!,
                                                      isApplied: true, // disable apply on map
                                                      isMember: true, // mark as current
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.map_rounded, color: Colors.white, size: 16),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'View on Map',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                      fontFamily: 'Montserrat',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (_currentDayungData != null &&
                                          _currentDayungData!['latitude'] != null &&
                                          _currentDayungData!['longitude'] != null)
                                      const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: kPrimary,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: () async {
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
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Change',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    fontFamily: 'Montserrat',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Apply a Dayung
                        Container(
                          width: double.infinity,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
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
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 14),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Apply a Dayung',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Filters
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kAccent.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: kAccent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(Icons.filter_list_rounded, color: Colors.white, size: 14),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        'Filters',
                                        style: sectionTitleStyle.copyWith(
                                          color: kText,
                                          fontSize: isWide ? 16 : 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: kPrimary.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: TextButton.icon(
                                        onPressed: () {},
                                        icon: const Icon(Icons.edit_rounded, color: kPrimary, size: 12),
                                        label: Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: kPrimary,
                                            fontSize: isWide ? 12 : 10,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Selected tags:',
                                style: bodyTextStyle.copyWith(
                                  color: kSubText,
                                  fontWeight: FontWeight.w500,
                                  fontSize: isWide ? 14 : 12,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: selectedFilters.map((tag) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: kAccent.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: isWide ? 12 : 10,
                                        color: kAccent,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: kPrimary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.recommend_rounded, color: Colors.white, size: 14),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  'Recommended for you',
                                  style: sectionTitleStyle.copyWith(
                                    color: kText,
                                    fontSize: isWide ? 16 : 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Recommendations
                        ...recommended.entries.map((entry) {
                          final key = entry.key;
                          final tags = entry.value;

                          // Dummy data for demo, dapat kunin mo ang buong dayung object sa production
                          final dayungData = {
                            'name': key,
                            'barangay': 'Sample Barangay',
                            'city': 'Sample City',
                            'province': 'Sample Province',
                            'latitude': 7.123, // Palitan ng totoong lat/lng kung meron
                            'longitude': 125.612,
                          };

                          return GestureDetector(
                            onTap: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => map.DayungMapPage(
                                    dayung: dayungData,
                                    isApplied: false,
                                    isMember: false,
                                  ),
                                ),
                              );
                              if (result != null && mounted) {
                                // Optional: handle result (e.g., show snackbar)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Application sent to ${result['name']}!',
                                    ),
                                  ),
                                );
                                await _loadCurrentDayung();
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: kAccent.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(Icons.home_rounded, color: kAccent, size: 12),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          key,
                                          style: TextStyle(
                                            fontSize: isWide ? 14 : 12,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'Montserrat',
                                            color: kText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: tags.map((t) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: kAccent.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          t,
                                          style: TextStyle(
                                            fontSize: isWide ? 10 : 8,
                                            color: kAccent,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
