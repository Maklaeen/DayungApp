import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:capstone_app/utils/dayung_recommendations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/President/manage_rules.dart';

const kSettingsText = Color(0xFF111827);
const kSettingsSubText = Color(0xFF6B7280);
const kSettingsPrimary = Color(0xFF3B82F6);
const kSettingsAccent = Color(0xFF059669);
const kSettingsCardBg = Color(0xFFFFFFFF);
const kSettingsBorder = Color(0xFFE5E7EB);

class DayungSettingsPage extends StatefulWidget {
  const DayungSettingsPage({super.key});

  @override
  State<DayungSettingsPage> createState() => _DayungSettingsPageState();
}

class _DayungSettingsPageState extends State<DayungSettingsPage> {
  String? _currentDayungName;
  Map<String, dynamic>? _currentDayungData;
  bool _loadingDayung = false;
  bool _loadingPrefs = false;
  bool _savingPrefs = false;
  bool _prefsSaveSuccess = false;
  bool _loadingRecs = false;
  bool _changingDayung = false;
  bool _changeDayungSuccess = false;

  String? _prefMeetingFrequency;
  String? _prefContributionAmount;
  String? _prefMembershipPayment;
  String? _prefPenaltyPayment;
  String? _prefPenaltyPolicy;
  String? _prefPaymentMethod;
  bool? _prefOpenForAll;
  String? _prefLocation;

  double? _userLat;
  double? _userLng;

  List<Map<String, dynamic>> _recommendedUnits = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentDayung();
    _loadPreferences().then((_) async {
      await _loadRecommendations();
    });
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

  List<String> get _prefsTags {
    final tags = DayungPreferencesData(
      meetingFrequency: _prefMeetingFrequency,
      contributionAmount: _prefContributionAmount,
      membershipPayment: _prefMembershipPayment,
      penaltyPayment: _prefPenaltyPayment,
      penaltyPolicy: _prefPenaltyPolicy,
      paymentMethod: _prefPaymentMethod,
      openForAll: _prefOpenForAll,
      location: _prefLocation,
      userLat: _userLat,
      userLng: _userLng,
    ).tags;
    return tags.isEmpty ? ['No preferences set'] : tags;
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
      final preferences = await DayungRecommendationService.loadPreferences(
        supabase,
        userId: user.id,
      );

      if (!mounted) return;
      setState(() {
        _prefMeetingFrequency = preferences.meetingFrequency;
        _prefContributionAmount = preferences.contributionAmount;
        _prefMembershipPayment = preferences.membershipPayment;
        _prefPenaltyPayment = preferences.penaltyPayment;
        _prefPenaltyPolicy = preferences.penaltyPolicy;
        _prefPaymentMethod = preferences.paymentMethod;
        _prefOpenForAll = preferences.openForAll;
        _prefLocation = preferences.location;
        _userLat = preferences.userLat;
        _userLng = preferences.userLng;
        _loadingPrefs = false;
      });
    } catch (_) {
      if (!mounted) return;
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

    try {
      final preferences = DayungPreferencesData(
        meetingFrequency: _prefMeetingFrequency,
        contributionAmount: _prefContributionAmount,
        membershipPayment: _prefMembershipPayment,
        penaltyPayment: _prefPenaltyPayment,
        penaltyPolicy: _prefPenaltyPolicy,
        paymentMethod: _prefPaymentMethod,
        openForAll: _prefOpenForAll,
        location: _prefLocation,
        userLat: _userLat,
        userLng: _userLng,
      );
      await DayungRecommendationService.savePreferences(
        supabase,
        userId: user.id,
        preferences: preferences,
      );
      if (!mounted) return;
      setState(() {
        _savingPrefs = false;
        _prefsSaveSuccess = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preferences updated')));
      await _loadPreferences();
      await _loadRecommendations();
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;
      Navigator.of(context).maybePop();
      setState(() => _prefsSaveSuccess = false);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _prefsSaveSuccess = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: ${error.message}')),
      );
    } finally {
      if (mounted && !_prefsSaveSuccess) {
        setState(() => _savingPrefs = false);
      }
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() => _loadingRecs = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() {
        _recommendedUnits = [];
        _loadingRecs = false;
      });
      return;
    }

    try {
      final excludedIds =
          await DayungRecommendationService.loadPendingApplicationDayungIds(
            supabase,
            userId: user.id,
          );
      final preferences = DayungPreferencesData(
        meetingFrequency: _prefMeetingFrequency,
        contributionAmount: _prefContributionAmount,
        membershipPayment: _prefMembershipPayment,
        penaltyPayment: _prefPenaltyPayment,
        penaltyPolicy: _prefPenaltyPolicy,
        paymentMethod: _prefPaymentMethod,
        openForAll: _prefOpenForAll,
        location: _prefLocation,
        userLat: _userLat,
        userLng: _userLng,
      );
      final recommendations =
          await DayungRecommendationService.loadRecommendations(
            supabase,
            preferences: preferences,
            currentDayungId: _currentDayungData?['id'] as int?,
            excludedDayungIds: excludedIds,
          );

      if (!mounted) return;
      setState(() => _recommendedUnits = recommendations);
    } catch (_) {
      if (!mounted) return;
      setState(() => _recommendedUnits = []);
    } finally {
      if (mounted) setState(() => _loadingRecs = false);
    }
  }

  Future<void> _showChangeDayungConfirmation() async {
    final next = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Change Dayung?'),
          content: Text(
            _currentDayungName == null
                ? 'You are about to choose a Dayung unit for this session.'
                : 'You are about to switch away from ${_currentDayungName!}. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (next == true) {
      await _changeDayung();
    }
  }

  void _showEditPreferencesSheet() {
    _prefsSaveSuccess = false;
    String? meetingFrequency = _prefMeetingFrequency ?? 'Any';
    String? contributionAmount = _prefContributionAmount ?? 'Any';
    String? membershipPayment = _prefMembershipPayment ?? 'Any';
    String? penaltyPayment = _prefPenaltyPayment ?? 'Any';
    String? paymentMethod = _prefPaymentMethod ?? 'Any';
    String? openForAllStr = _prefOpenForAll == null
        ? null
        : (_prefOpenForAll! ? 'Yes' : 'No');
    String? penaltyPolicy = _prefPenaltyPolicy;
    String? location = _prefLocation;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: kSettingsSubText.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Text(
                  'Edit Preferences',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Montserrat',
                    color: kSettingsText,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: meetingFrequency,
                  decoration: const InputDecoration(
                    labelText: 'Meeting Frequency',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Any', 'Weekly', 'Monthly', 'Needed']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => meetingFrequency = value,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: contributionAmount,
                  decoration: const InputDecoration(
                    labelText: 'Registration Fee Range',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Any',
                            '50-100',
                            '100-150',
                            '150-200',
                            '200-250',
                            '250-300',
                            '300-350',
                            '400 plus',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => contributionAmount = value,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: membershipPayment,
                  decoration: const InputDecoration(
                    labelText: 'Membership Payment',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Any',
                            '50-100',
                            '100-150',
                            '150-200',
                            '200-250',
                            '250-300',
                            '300-350',
                            '400 plus',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => membershipPayment = value,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: penaltyPayment,
                  decoration: const InputDecoration(
                    labelText: 'Penalty Payment',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Any',
                            '50-100',
                            '100-150',
                            '150-200',
                            '200-250',
                            '250-300',
                            '300-350',
                            '400 plus',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => penaltyPayment = value,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Any', 'Cash', 'GCash', 'Both']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => paymentMethod = value,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: openForAllStr,
                  decoration: const InputDecoration(
                    labelText: 'Open for All?',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Yes', 'No']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => openForAllStr = value,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: penaltyPolicy,
                  decoration: const InputDecoration(
                    labelText: 'Penalty Policy (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Brief description of penalties',
                  ),
                  maxLines: 2,
                  onChanged: (value) => penaltyPolicy = value.trim().isEmpty
                      ? null
                      : value.trim(),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: location,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Location (from your address)',
                    border: OutlineInputBorder(),
                  ),
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
                        : Icon(
                            _prefsSaveSuccess ? Icons.check_circle : Icons.save,
                          ),
                    label: Text(
                      _savingPrefs
                          ? 'Saving...'
                          : (_prefsSaveSuccess ? 'Saved' : 'Save Preferences'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kSettingsPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _savingPrefs
                        ? null
                        : () async {
                            setState(() {
                              _prefMeetingFrequency = meetingFrequency == 'Any'
                                  ? null
                                  : meetingFrequency;
                              _prefContributionAmount =
                                  contributionAmount == 'Any'
                                  ? null
                                  : contributionAmount;
                              _prefMembershipPayment =
                                  membershipPayment == 'Any'
                                  ? null
                                  : membershipPayment;
                              _prefPenaltyPayment = penaltyPayment == 'Any'
                                  ? null
                                  : penaltyPayment;
                              _prefPaymentMethod = paymentMethod == 'Any'
                                  ? null
                                  : paymentMethod;
                              _prefOpenForAll = openForAllStr == null
                                  ? null
                                  : openForAllStr == 'Yes';
                              _prefPenaltyPolicy = penaltyPolicy;
                              _prefLocation = location;
                            });
                            await _savePreferences();
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

  Future<void> _changeDayung() async {
    final messenger = ScaffoldMessenger.of(context);
    final roleProvider = context.read<DayungRoleProvider>();
    final unitProvider = context.read<DayungUnitProvider>();
    final selected = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelectDayungPage()),
    );
    if (!mounted) return;
    var didChange = false;
    if (selected != null && selected is Map<String, dynamic>) {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null && selected['id'] != null) {
        setState(() {
          _changingDayung = true;
          _changeDayungSuccess = false;
        });
        try {
          await supabase
              .from('users')
              .update({'dayung_unit_id': selected['id']})
              .eq('id', user.id);

          final prefs = await SharedPreferences.getInstance();
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
          await prefs.setString('selectedDayungUnitData', jsonEncode(selected));

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
              content: Text('Current Dayung updated to ${selected['name']}'),
            ),
          );
          didChange = true;
        } on PostgrestException catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text('Failed to set Dayung: ${e.message}')),
          );
        } finally {
          if (mounted) {
            setState(() => _changingDayung = false);
          }
        }
      }
    }

    await _loadCurrentDayung();
    await _loadRecommendations();
    if (didChange && mounted) {
      setState(() => _changeDayungSuccess = true);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        setState(() => _changeDayungSuccess = false);
      }
    }
  }

  Future<void> _applyForDayung() async {
    final messenger = ScaffoldMessenger.of(context);
    final selectedDayung = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DayungSuggestionsPage()),
    );
    if (!mounted) return;
    if (selectedDayung != null && selectedDayung is Map<String, dynamic>) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Application sent to ${selectedDayung['name']}!'),
        ),
      );
      await _loadCurrentDayung();
      await _loadRecommendations();
    }
  }

  void _openCurrentDayungMap() {
    if (_currentDayungData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DayungMapPage(
          dayung: _currentDayungData!,
          isApplied: true,
          isMember: true,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSettingsCardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kSettingsBorder.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120B1F33),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSummaryInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSettingsBorder.withValues(alpha: 0.9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kSettingsPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: kSettingsPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kSettingsSubText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: kSettingsText,
                    fontFamily: 'OpenSans',
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final roleProvider = context.watch<DayungRoleProvider>();
    final hasCurrentDayung = _currentDayungData != null;
    final canViewMap =
        hasCurrentDayung &&
        _currentDayungData!['latitude'] != null &&
        _currentDayungData!['longitude'] != null;
    final currentAddress = hasCurrentDayung
        ? _address(_currentDayungData!)
        : 'No location details yet';

    final sectionTitleStyle = TextStyle(
      fontSize: isWide ? 20 : 16,
      fontWeight: FontWeight.w600,
      fontFamily: 'Montserrat',
    );
    final bodyTextStyle = TextStyle(
      fontSize: isWide ? 18 : 14,
      fontFamily: 'OpenSans',
    );
    final mutedTextStyle = bodyTextStyle.copyWith(color: kSettingsSubText);
    final titleColor = kSettingsText;
    final primaryColor = kSettingsPrimary;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 28 : 18,
                  vertical: isWide ? 24 : 18,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kSettingsPrimary, kSettingsAccent],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context, true),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dayung Settings',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: isWide ? 28 : 22,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Text(
                              //   'Manage your current Dayung, discover options, and update unit access in one place.',
                              //   style: TextStyle(
                              //     color: Colors.white.withValues(alpha: 0.88),
                              //     fontSize: isWide ? 14 : 12,
                              //     height: 1.4,
                              //     fontFamily: 'OpenSans',
                              //   ),
                              // ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              hasCurrentDayung
                                  ? 'Your current Dayung is active below. Use Change Dayung if you want to switch units.'
                                  : 'No Dayung is assigned yet. Start by tapping Change Dayung or Apply a Dayung.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.94),
                                fontSize: 12,
                                height: 1.4,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            hasCurrentDayung
                                ? Icons.home_work_rounded
                                : Icons.location_city_outlined,
                            color: primaryColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current Dayung',
                                style: bodyTextStyle.copyWith(
                                  color: mutedTextStyle.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              AutoSizeText(
                                _currentDayungName ?? 'No Dayung Assigned',
                                style: bodyTextStyle.copyWith(
                                  color: titleColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: isWide ? 22 : 18,
                                ),
                                maxLines: 1,
                                minFontSize: 12,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: _loadCurrentDayung,
                          icon: Icon(
                            Icons.refresh_rounded,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _changingDayung
                            ? null
                            : _showChangeDayungConfirmation,
                        icon: _changingDayung
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _changeDayungSuccess
                                    ? Icons.check_circle
                                    : Icons.swap_horiz_rounded,
                              ),
                        label: Text(
                          _changingDayung
                              ? 'Changing...'
                              : (_changeDayungSuccess
                                    ? 'Changed'
                                    : 'Change Dayung'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loadingDayung)
                      const ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(99)),
                        child: LinearProgressIndicator(minHeight: 6),
                      )
                    else ...[
                      _buildSummaryInfoRow(
                        icon: Icons.location_on_outlined,
                        label: 'Location',
                        value: currentAddress,
                      ),
                      _buildSummaryInfoRow(
                        icon: Icons.verified_user_outlined,
                        label: 'Status',
                        value: hasCurrentDayung
                            ? 'Currently assigned to this Dayung unit.'
                            : 'No active Dayung assignment yet.',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (canViewMap)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openCurrentDayungMap,
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('View on Map'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  minimumSize: const Size.fromHeight(52),
                                  side: BorderSide(
                                    color: kSettingsBorder.withValues(
                                      alpha: 0.9,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          if (canViewMap) const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _applyForDayung,
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Apply a Dayung'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                                minimumSize: const Size.fromHeight(52),
                                side: BorderSide(
                                  color: kSettingsBorder.withValues(alpha: 0.9),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
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
              if (roleProvider.isPresident) ...[
                const SizedBox(height: 16),
                _buildSectionCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kSettingsAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.rule_folder_rounded,
                        color: kSettingsAccent,
                      ),
                    ),
                    title: Text(
                      'Manage Rules',
                      style: bodyTextStyle.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Open Dayung rules and policy management.',
                      style: mutedTextStyle,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
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
              const SizedBox(height: 16),
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AutoSizeText(
                          'Filters',
                          style: sectionTitleStyle.copyWith(color: titleColor),
                          maxLines: 1,
                          minFontSize: 12,
                        ),
                        TextButton.icon(
                          onPressed: _showEditPreferencesSheet,
                          icon: Icon(Icons.tune_rounded, color: primaryColor),
                          label: Text(
                            'Edit',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: isWide ? 16 : 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These preferences influence what Dayung suggestions appear first.',
                      style: mutedTextStyle,
                    ),
                    const SizedBox(height: 14),
                    if (_loadingPrefs)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _prefsTags.map((tag) {
                          return Chip(
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            label: Text(
                              tag,
                              style: TextStyle(
                                fontSize: isWide ? 15 : 13,
                                color: kSettingsAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: kSettingsAccent.withValues(
                              alpha: 0.08,
                            ),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AutoSizeText(
                          'Recommended for you',
                          style: sectionTitleStyle.copyWith(color: titleColor),
                          maxLines: 1,
                          minFontSize: 12,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Refresh recommendations',
                          onPressed: _loadRecommendations,
                          icon: const Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: kSettingsPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Suggested Dayung units based on your filters and nearby matches.',
                      style: mutedTextStyle,
                    ),
                    const SizedBox(height: 14),
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
                        style: mutedTextStyle,
                      )
                    else
                      ..._recommendedUnits.map((dayungData) {
                        final tags = List<String>.from(
                          (dayungData['__tags'] as List?) ?? const <String>[],
                        );
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
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Application sent to ${result['name']}!',
                                  ),
                                ),
                              );
                              await _loadCurrentDayung();
                              await _loadRecommendations();
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: kSettingsCardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: kSettingsBorder.withValues(alpha: 0.9),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x100B1F33),
                                  blurRadius: 16,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: AutoSizeText(
                                        (dayungData['name'] ?? 'Unnamed Dayung')
                                            .toString(),
                                        style: TextStyle(
                                          fontSize: isWide ? 18 : 15,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Montserrat',
                                          color: titleColor,
                                        ),
                                        maxLines: 1,
                                        minFontSize: 12,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _address(dayungData),
                                  style: mutedTextStyle.copyWith(fontSize: 13),
                                ),
                                if ((dayungData['__score'] as num?) !=
                                    null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Match score: ${(((dayungData['__score'] as num?) ?? 0) * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: tags.map((tag) {
                                    return Chip(
                                      labelPadding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      label: Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: isWide ? 15 : 13,
                                        ),
                                      ),
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      side: BorderSide.none,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
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
            ],
          ),
        ),
      ),
    );
  }
}
