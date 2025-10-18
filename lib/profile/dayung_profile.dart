import 'dart:convert';
import 'package:capstone_app/screens/dayung_suggestions.dart' hide kPrimary, kAccent, kWarn;
import 'package:capstone_app/screens/selectdayung.dart'
    hide kPrimary, kWarn, kAccent;
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
  // Preferences state
  bool _loadingPrefs = false;
  bool _savingPrefs = false;
  String? _prefFeeRange;
  String? _prefPaymentMethod;
  bool? _prefOpenForAll;
  String? _prefFundSupportRange;
  bool _loadingRecs = false;
  List<Map<String, dynamic>> _recommendedUnits = [];
  // Location was removed from suggestions; keep optional if you want to use it later:
  String? _prefLocation;

  String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^\d]'), '');
  String _trimLower(String? s) => (s ?? '').trim().toLowerCase();

  List<String> get _prefsTags {
    final tags = <String>[];
    if ((_prefFeeRange ?? '').isNotEmpty) tags.add(_prefFeeRange!);
    if ((_prefPaymentMethod ?? '').isNotEmpty) tags.add(_prefPaymentMethod!);
    if (_prefOpenForAll != null)
      tags.add(_prefOpenForAll! ? 'Open for all' : 'Restricted');
    if ((_prefFundSupportRange ?? '').isNotEmpty)
      tags.add(_prefFundSupportRange!);
    // if ((_prefLocation ?? '').isNotEmpty) tags.add(_prefLocation!);
    return tags.isEmpty ? ['No preferences set'] : tags;
  }

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
    _loadPreferences().then((_) => _loadRecommendations());
  }

  Future<void> _loadRecommendations() async {
    setState(() => _loadingRecs = true);
    final supabase = Supabase.instance.client;
    try {
      var qb = supabase
          .from('dayung_units')
          .select(
            'id, name, barangay, city, province, latitude, longitude, fee_range, payment_method, open_for_all, fund_support_range, created_at',
          );

      int filters = 0;

      final feeDigits = _digits(_prefFeeRange);
      if ((_prefFeeRange ?? '').isNotEmpty) {
        filters++;
        if (feeDigits.isNotEmpty) {
          qb = qb.ilike('fee_range', '%$feeDigits%');
        } else {
          qb = qb.ilike('fee_range', '%${_trimLower(_prefFeeRange)}%');
        }
      }

      if ((_prefPaymentMethod ?? '').isNotEmpty) {
        filters++;
        qb = qb.ilike('payment_method', '%${_trimLower(_prefPaymentMethod)}%');
      }

      if (_prefOpenForAll != null) {
        filters++;
        qb = qb.eq('open_for_all', _prefOpenForAll as Object);
      }

      final fundDigits = _digits(_prefFundSupportRange);
      if ((_prefFundSupportRange ?? '').isNotEmpty) {
        filters++;
        if (fundDigits.isNotEmpty) {
          qb = qb.ilike('fund_support_range', '%$fundDigits%');
        } else {
          qb = qb.ilike(
            'fund_support_range',
            '%${_trimLower(_prefFundSupportRange)}%',
          );
        }
      }

      // Order newest first, cap results
      List<dynamic> rows = await qb
          .order('created_at', ascending: false)
          .limit(10);

      // Fallback: if no filters or no matches, show a small sample
      if (rows.isEmpty) {
        rows = await supabase
            .from('dayung_units')
            .select('id, name, barangay, city, province, latitude, longitude')
            .order('created_at', ascending: false)
            .limit(10);
      }

      setState(() {
        _recommendedUnits = rows.cast<Map<String, dynamic>>();
      });
    } catch (_) {
      setState(() => _recommendedUnits = []);
    } finally {
      if (mounted) setState(() => _loadingRecs = false);
    }
  }

  Future<void> _loadPreferences() async {
    setState(() => _loadingPrefs = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _loadingPrefs = false);
      return;
    }
    try {
      final pref = await supabase
          .from('user_preferences')
          .select(
            'fee_range, payment_method, open_for_all, fund_support_range, location',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      setState(() {
        _prefFeeRange = (pref?['fee_range'] as String?)?.trim();
        _prefPaymentMethod = (pref?['payment_method'] as String?)?.trim();
        _prefOpenForAll = pref?['open_for_all'] as bool?;
        _prefFundSupportRange = (pref?['fund_support_range'] as String?)
            ?.trim();
        _prefLocation = (pref?['location'] as String?)?.trim();
        _loadingPrefs = false;
      });
    } on PostgrestException catch (_) {
      setState(() => _loadingPrefs = false);
    }
  }

  Future<void> _savePreferences() async {
    setState(() => _savingPrefs = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _savingPrefs = false);
      return;
    }
    final payload = {
      'user_id': user.id,
      'fee_range': _prefFeeRange,
      'payment_method': _prefPaymentMethod,
      'open_for_all': _prefOpenForAll,
      'fund_support_range': _prefFundSupportRange,
      'location': _prefLocation, // optional, not used for suggestions
    };
    try {
      // Requires RLS policies allowing user-owned select/insert/update and a unique constraint on user_id
      await supabase
          .from('user_preferences')
          .upsert(payload, onConflict: 'user_id');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preferences updated')));
      Navigator.of(context).maybePop(); // close sheet if open
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: ${e.message}')));
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }

  void _showEditPreferencesSheet() {
    final formKey = GlobalKey<FormState>();
    // Local edit copies
    String? feeRange = _prefFeeRange;
    String? paymentMethod = _prefPaymentMethod;
    bool? openForAll = _prefOpenForAll;
    String? fundSupportRange = _prefFundSupportRange;
    String? location = _prefLocation;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: kSubText.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Text(
                  'Edit Preferences',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Montserrat',
                    color: kText,
                  ),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: feeRange,
                  decoration: const InputDecoration(
                    labelText: 'Registration Fee Range',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Any',
                            'Free',
                            '₱1 - ₱100',
                            '₱101 - ₱500',
                            '₱501+',
                            '₱100',
                            '₱500',
                            '₱1000',
                          ]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (v) => feeRange = v,
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Any', 'GCash', 'Bank Transfer', 'Cash']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => paymentMethod = v,
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: openForAll == null
                      ? null
                      : (openForAll! ? 'Yes' : 'No'),
                  decoration: const InputDecoration(
                    labelText: 'Open for All?',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Yes', 'No']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => openForAll = v == null ? null : v == 'Yes',
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: fundSupportRange,
                  decoration: const InputDecoration(
                    labelText: 'Fund Support Range',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Any',
                            '₱0 - ₱500',
                            '₱501 - ₱1000',
                            '₱1001+',
                            '₱500',
                            '₱1000',
                            '₱1500',
                          ]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (v) => fundSupportRange = v,
                ),
                const SizedBox(height: 10),

                // Optional location (not used in suggestions)
                TextFormField(
                  initialValue: location,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Davao City',
                  ),
                  onChanged: (v) =>
                      location = v.trim().isEmpty ? null : v.trim(),
                ),
                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _savingPrefs
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _savingPrefs ? 'Saving...' : 'Save Preferences',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryLight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _savingPrefs
                        ? null
                        : () async {
                            // Persist form values to state, then save
                            setState(() {
                              _prefFeeRange = feeRange == 'Any'
                                  ? null
                                  : feeRange;
                              _prefPaymentMethod = paymentMethod == 'Any'
                                  ? null
                                  : paymentMethod;
                              _prefOpenForAll = openForAll;
                              _prefFundSupportRange = fundSupportRange == 'Any'
                                  ? null
                                  : fundSupportRange;
                              _prefLocation = location;
                            });
                            await _savePreferences();
                            if (mounted) setState(() {}); // refresh tags
                          },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
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
                                      child: const Icon(
                                        Icons.home_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
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
                                          color: kPrimary.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                        color: _currentDayungName != null
                                            ? kSuccess
                                            : kWarn,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        _currentDayungName ??
                                            'No Dayung Assigned',
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
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          color: kPrimary,
                                          size: 12,
                                        ),
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
                                            color: kSubText.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.location_on_rounded,
                                            color: kSubText,
                                            size: 12,
                                          ),
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
                                        _currentDayungData!['latitude'] !=
                                            null &&
                                        _currentDayungData!['longitude'] !=
                                            null)
                                      Expanded(
                                        child: Container(
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: kAccent,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => map.DayungMapPage(
                                                      dayung:
                                                          _currentDayungData!,
                                                      isApplied:
                                                          true, // disable apply on map
                                                      isMember:
                                                          true, // mark as current
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.map_rounded,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'View on Map',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
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
                                        _currentDayungData!['latitude'] !=
                                            null &&
                                        _currentDayungData!['longitude'] !=
                                            null)
                                      const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: kPrimary,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            onTap: () async {
                                              final selected =
                                                  await Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const SelectDayungPage(),
                                                    ),
                                                  );

                                              // If user picked a Dayung, update users.dayung_unit_id
                                              if (!mounted) return;
                                              if (selected != null &&
                                                  selected
                                                      is Map<String, dynamic>) {
                                                final supabase =
                                                    Supabase.instance.client;
                                                final user =
                                                    supabase.auth.currentUser;
                                                if (user != null &&
                                                    selected['id'] != null) {
                                                  try {
                                                    await supabase
                                                        .from('users')
                                                        .update({
                                                          'dayung_unit_id':
                                                              selected['id'],
                                                        })
                                                        .eq('id', user.id);

                                                    // Persist the new selection to SharedPreferences so ClaimsPage picks it up
                                                    final prefs =
                                                        await SharedPreferences.getInstance();
                                                    await prefs.setString(
                                                      'selectedDayungUnit',
                                                      jsonEncode({
                                                        'id': selected['id'],
                                                        'name':
                                                            selected['name'],
                                                        'barangay':
                                                            selected['barangay'],
                                                        'city':
                                                            selected['city'],
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
                                                  } on PostgrestException catch (
                                                    e
                                                  ) {
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
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.swap_horiz_rounded,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
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
                                    builder: (_) =>
                                        const DayungSuggestionsPage(),
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
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.add_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
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
                                      child: const Icon(
                                        Icons.filter_list_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
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
                                        onPressed: _showEditPreferencesSheet,
                                        icon: const Icon(
                                          Icons.edit_rounded,
                                          color: kPrimary,
                                          size: 12,
                                        ),
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              if (_loadingPrefs)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else ...[
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
                                  children: _prefsTags.map((tag) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
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
                                child: const Icon(
                                  Icons.recommend_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
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
                              IconButton(
                                tooltip: 'Refresh',
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                  color: kPrimary,
                                ),
                                onPressed: _loadRecommendations,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_loadingRecs)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_recommendedUnits.isEmpty)
                          Text(
                            'No recommendations yet. Edit your filters above.',
                            style: TextStyle(
                              color: kSubText,
                              fontSize: isWide ? 14 : 12,
                            ),
                          )
                        else
                          Column(
                            children: _recommendedUnits.map((d) {
                              return GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => map.DayungMapPage(
                                        dayung: d,
                                        isApplied: false,
                                        isMember: false,
                                      ),
                                    ),
                                  );
                                  if (result != null && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Application sent to ${d['name']}!',
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: kAccent.withValues(
                                                alpha: 0.05,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Icon(
                                              Icons.home_rounded,
                                              color: kAccent,
                                              size: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              d['name'] ?? 'Unnamed Dayung',
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
                                      const SizedBox(height: 8),
                                      Text(
                                        _address(d),
                                        style: TextStyle(
                                          color: kSubText,
                                          fontSize: 12,
                                          fontFamily: 'OpenSans',
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          OutlinedButton.icon(
                                            icon: const Icon(
                                              Icons.map_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('Map'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kPrimary,
                                              side: const BorderSide(
                                                color: kPrimary,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      map.DayungMapPage(
                                                        dayung: d,
                                                        isApplied: false,
                                                        isMember: false,
                                                      ),
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('Similar'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kPrimary,
                                              side: const BorderSide(
                                                color: kPrimary,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                            ),
                                            onPressed: _loadRecommendations,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
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
