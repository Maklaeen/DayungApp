import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart'
    hide kPrimary, kAccent, kWarn;
import 'package:capstone_app/screens/selectdayung.dart'
    hide kPrimary, kWarn, kAccent;
import 'package:capstone_app/screens/dayung_map_page.dart' as map;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  String? _prefLocation;

  bool _loadingApplied = false;
  List<Map<String, dynamic>> _appliedDayungs = [];
  String? _appliedDebug;

  String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^\d]'), '');
  String _trimLower(String? s) => (s ?? '').trim().toLowerCase();

  List<String> get _prefsTags {
    final tags = <String>[];
    if ((_prefFeeRange ?? '').isNotEmpty) tags.add(_prefFeeRange!);
    if ((_prefPaymentMethod ?? '').isNotEmpty) tags.add(_prefPaymentMethod!);
    if (_prefOpenForAll != null) {
      tags.add(_prefOpenForAll! ? 'Open for all' : 'Restricted');
    }
    if ((_prefFundSupportRange ?? '').isNotEmpty) {
      tags.add(_prefFundSupportRange!);
    }
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
    _loadAppliedDayungs();
  }

  Future<void> _loadAppliedDayungs() async {
    setState(() {
      _loadingApplied = true;
      _appliedDebug = null;
    });
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loadingApplied = false;
        _appliedDayungs = [];
        _appliedDebug = 'No user.';
      });
      return;
    }

    try {
      final rows = await supabase
          .from('applications')
          .select('id,status,applied_at,name,dayung_unit_id,dayung_units(name)')
          .eq('user_id', user.id)
          .eq('status', 'pending')
          .order('applied_at', ascending: false);

      final list = (rows as List).map((r) => Map<String, dynamic>.from(r)).map((
        r,
      ) {
        final fallback = (r['dayung_units'] is Map && r['dayung_units'] != null)
            ? r['dayung_units']['name']
            : null;
        r['display_name'] = (r['name'] as String?)?.trim().isNotEmpty == true
            ? r['name']
            : (fallback ?? 'Unknown Dayung');
        return r;
      }).toList();

      setState(() {
        _appliedDayungs = list;
        if (list.isEmpty) {
          _appliedDebug = '';
        }
      });
    } on PostgrestException catch (e) {
      setState(() {
        _appliedDayungs = [];
        _appliedDebug = 'Postgrest: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _appliedDayungs = [];
        _appliedDebug = 'Error: $e';
      });
    } finally {
      setState(() => _loadingApplied = false);
    }
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
                  initialValue: feeRange,
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
                  initialValue: paymentMethod,
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
                  initialValue: openForAll == null
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
                  initialValue: fundSupportRange,
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

    // Use DayungUnitProvider or SharedPreferences as the source of truth
    final provider = context.read<DayungUnitProvider>();
    await provider.loadDayungUnit(); // ensures latest from prefs

    final obj = provider.dayungUnitObj;
    final name = provider.dayungUnit;
    setState(() {
      _currentDayungId = obj?['id'] as int?;
      _currentDayungName = name;
      _currentDayungData = obj;
      _loadingDayung = false;
    });
  }

  String _address(Map<String, dynamic> d) {
    final parts = <String>[
      if ((d['barangay'] ?? '').toString().isNotEmpty) d['barangay'],
      if ((d['city'] ?? '').toString().isNotEmpty) d['city'],
      if ((d['province'] ?? '').toString().isNotEmpty) d['province'],
    ];
    return parts.join(', ');
  }

  // Show requirements sheet for an applied Dayung
  void _showRequirementsSheet(String dayungName, {List<String>? requirements}) {
    final reqs =
        requirements ??
        const [
          'Birth Certificate',
          'Valid Government ID',
          'Proof of Residency',
          'Marriage Certificate (if applicable)',
        ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: kSubText.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                'Upload Requirements',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                  color: kText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your application for $dayungName is pending. Please upload the following:',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'OpenSans',
                  color: kSubText,
                ),
              ),
              const SizedBox(height: 12),
              ...reqs.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.description_rounded,
                        size: 16,
                        color: kPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'OpenSans',
                            color: kText,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Montserrat',
                            color: kAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    final sectionTitleStyle = TextStyle(
      fontSize: isWide ? 20 : 16,
      fontWeight: FontWeight.w700,
      fontFamily: 'Montserrat',
      color: kText,
    );
    final bodyTextStyle = TextStyle(
      fontSize: isWide ? 18 : 14,
      fontFamily: 'OpenSans',
      color: kSubText,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Modern Curved Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kPrimaryLight, kAccentDark],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  child: const Icon(Icons.group, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentDayungName ?? 'Manage Dayung',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: isWide ? 28 : 22,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentDayungData != null
                            ? _address(_currentDayungData!)
                            : 'No address set',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 15,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Refresh',
                  onPressed: _loadCurrentDayung,
                ),
              ],
            ),
          ),
          // Main Content
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
                    // --- Current Dayung Card ---
                    Card(
                      elevation: 4,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.home_rounded,
                                    color: kPrimary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'Current Dayung',
                                  style: sectionTitleStyle,
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Refresh',
                                  onPressed: _loadCurrentDayung,
                                  icon: const Icon(
                                    Icons.refresh,
                                    size: 18,
                                    color: kPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_loadingDayung)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else ...[
                              Row(
                                children: [
                                  Icon(
                                    _currentDayungName != null
                                        ? Icons.verified_rounded
                                        : Icons.warning_amber_rounded,
                                    color: _currentDayungName != null
                                        ? kSuccess
                                        : kWarn,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _currentDayungName ??
                                          'No Dayung Assigned',
                                      style: bodyTextStyle.copyWith(
                                        color: kText,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_currentDayungData != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: kAccentDark,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _address(_currentDayungData!),
                                        style: bodyTextStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // --- Apply a Dayung Button ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Apply a Dayung',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          final selectedDayung = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DayungSuggestionsPage(),
                            ),
                          );
                          if (selectedDayung != null &&
                              selectedDayung is Map<String, dynamic>) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Application for ${selectedDayung['name']} sent!',
                                ),
                              ),
                            );
                            await _loadCurrentDayung();
                            await _loadAppliedDayungs();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 10),

                    // --- How to Apply Button ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'How to Apply?',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryLight,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          // Your existing modal logic here
                          showModalBottomSheet(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                            ),
                            builder: (ctx) => Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                20,
                                20,
                                32,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 40,
                                      height: 4,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: kSubText.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const Text(
                                    'How to Apply',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Montserrat',
                                      color: kText,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'To apply for a Dayung, select a unit and complete the requirements.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'OpenSans',
                                      color: kSubText,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  ...const [
                                    'Birth Certificate',
                                    'Valid Government ID',
                                    'Proof of Residency',
                                    'Marriage Certificate (if applicable)',
                                  ].map(
                                    (r) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.description_rounded,
                                            size: 16,
                                            color: kPrimary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              r,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontFamily: 'OpenSans',
                                                color: kText,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),

                    // --- Applied Dayung List Card ---
                    Card(
                      elevation: 4,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: kPrimaryLight.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.assignment_turned_in,
                                    color: kPrimaryLight,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'Applied Dayung',
                                  style: sectionTitleStyle,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  icon: const Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: kPrimary,
                                  ),
                                  label: const Text(
                                    '',
                                    style: TextStyle(
                                      color: kPrimary,
                                      overflow: TextOverflow.ellipsis,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  onPressed: () {
                                    // Your existing modal logic here
                                    showModalBottomSheet(
                                      context: context,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(16),
                                        ),
                                      ),
                                      builder: (ctx) => Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          20,
                                          20,
                                          20,
                                          32,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Center(
                                              child: Container(
                                                width: 40,
                                                height: 4,
                                                margin: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: kSubText.withOpacity(
                                                    0.2,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                            ),
                                            const Text(
                                              'Pending Applications',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'Montserrat',
                                                color: kText,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            const Text(
                                              'These are Dayung units you have applied to but are not yet approved.',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontFamily: 'OpenSans',
                                                color: kSubText,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_loadingApplied)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else if (_appliedDayungs.isEmpty) ...[
                              Text(
                                'You have no pending applications.',
                                style: bodyTextStyle.copyWith(color: kSubText),
                              ),
                              if (_appliedDebug != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _appliedDebug!,
                                  style: bodyTextStyle.copyWith(
                                    color: kSubText,
                                    fontSize: isWide ? 12 : 10,
                                  ),
                                ),
                              ],
                            ] else
                              ..._appliedDayungs.map((app) {
                                final dayungName =
                                    (app['name'] as String?) ?? 'N/A';
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () =>
                                        _showRequirementsSheet(dayungName),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 12,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 6),
                                      decoration: BoxDecoration(
                                        color: kPrimaryLight.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.folder,
                                            color: kPrimaryLight,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              app['display_name'] ??
                                                  'Unknown Dayung',
                                              style: bodyTextStyle.copyWith(
                                                color: kText,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: kSubText,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // --- Filters Card ---
                    Card(
                      elevation: 4,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: kAccent.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.filter_list_rounded,
                                    color: kAccent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text('Filters', style: sectionTitleStyle),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _showEditPreferencesSheet,
                                  icon: const Icon(
                                    Icons.edit,
                                    size: 16,
                                    color: kPrimaryLight,
                                  ),
                                  label: const Text(
                                    'Edit',
                                    style: TextStyle(
                                      color: kPrimaryLight,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
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
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _prefsTags.map((tag) {
                                  return Chip(
                                    label: Text(
                                      tag,
                                      style: TextStyle(
                                        color: kAccentDark,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                    backgroundColor: kAccentDark.withOpacity(
                                      0.08,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // --- Recommendations Card ---
                    Card(
                      elevation: 4,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.recommend_rounded,
                                    color: kPrimary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'Recommended for you',
                                  style: sectionTitleStyle,
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Refresh',
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                    color: kPrimary,
                                  ),
                                  onPressed: _loadRecommendations,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_loadingRecs)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Opened map for ${d['name']}',
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
                                        color: kPrimaryLight.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.home,
                                                color: kPrimaryLight,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  d['name'] ?? 'Unnamed Unit',
                                                  style: bodyTextStyle.copyWith(
                                                    color: kText,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right,
                                                color: kSubText,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _address(d),
                                            style: bodyTextStyle,
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.dashboard_rounded, color: Colors.white),
            label: const Text(
              'Dashboard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Montserrat',
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryLight,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
    );
  }
}
