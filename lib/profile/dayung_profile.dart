import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/pages/apply_membership.dart';
import 'package:capstone_app/Providers/role_router.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:capstone_app/screens/dayungquestion.dart';
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

Future<void> openDayungRecommendations(BuildContext context) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Please sign in first.')));
    return;
  }

  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => QuestionnaireScreen(
        userId: user.id,
        role: 'member',
        returnToCaller: true,
      ),
    ),
  );
}

class DayungSettingsPage extends StatefulWidget {
  const DayungSettingsPage({super.key});

  @override
  State<DayungSettingsPage> createState() => _DayungSettingsPageState();
}

class _DayungSettingsPageState extends State<DayungSettingsPage> {
  String? _currentDayungName;
  Map<String, dynamic>? _currentDayungData;
  bool _loadingDayung = false;
  bool _loadingUserLocation = true;
  String _userLocation = 'Loading location...';
  bool _changingDayung = false;
  bool _changeDayungSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentDayung();
    _loadUserLocation();
  }

  Future<void> _loadUserLocation() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loadingUserLocation = false;
          _userLocation = 'No signed-in user';
        });
      }
      return;
    }

    setState(() => _loadingUserLocation = true);
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('address, latitude, longitude')
          .eq('id', user.id)
          .maybeSingle();

      String? valueFor(Object? value) {
        final valueString = value?.toString().trim();
        return valueString == null || valueString.isEmpty ? null : valueString;
      }

      final address = valueFor(response?['address']);
      final latitude = valueFor(response?['latitude']);
      final longitude = valueFor(response?['longitude']);
      final locationDetails = <String>[if (address != null) address];

      if (!mounted) return;
      setState(() {
        _userLocation = locationDetails.isEmpty
            ? 'No location details available'
            : locationDetails.join('\n');
      });
    } catch (error) {
      debugPrint('Failed to load user location: $error');
      if (mounted) {
        setState(() => _userLocation = 'Unable to load location');
      }
    } finally {
      if (mounted) setState(() => _loadingUserLocation = false);
    }
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
    }
  }

  Future<void> _openPendingApplication() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final application = await Supabase.instance.client
          .from('applications')
          .select('dayung_unit_id, name')
          .eq('user_id', user.id)
          .eq('status', 'for_confirmation')
          .order('applied_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      final rawDayungUnitId = application?['dayung_unit_id'];
      final dayungUnitId = rawDayungUnitId is int
          ? rawDayungUnitId
          : int.tryParse('$rawDayungUnitId');
      if (application == null || dayungUnitId == null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.info_outline_rounded),
            title: const Text('No Pending Application'),
            content: const Text('No pending application to continue.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ApplyMembershipWizard(
            dayungUnitId: dayungUnitId,
            dayungName: (application['name'] ?? 'Dayung').toString(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open pending application: $error')),
      );
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

  Future<void> _openFullQuestionnaire() async {
    await openDayungRecommendations(context);
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
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  isWide ? 30 : 16,
                  20,
                  isWide ? 24 : 16,
                  24,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D47A1),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF1E40AF),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: IconButton(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const RoleRouter(),
                            ),
                            (route) => false,
                          );
                        },
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
                              fontSize: isWide ? 24 : 20,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                      _currentDayungName ??
                                          'No Dayung Assigned',
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
                                onPressed: () {
                                  _loadCurrentDayung();
                                  _loadUserLocation();
                                },
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
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
                              borderRadius: BorderRadius.all(
                                Radius.circular(99),
                              ),
                              child: LinearProgressIndicator(minHeight: 6),
                            )
                          else ...[
                            _buildSummaryInfoRow(
                              icon: Icons.location_on_outlined,
                              label: 'Location',
                              value: _loadingUserLocation
                                  ? 'Loading location...'
                                  : _userLocation,
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
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (canViewMap) const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _applyForDayung,
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: const Text('Finding a Dayung'),
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
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openPendingApplication,
                              icon: const Icon(Icons.pending_actions_outlined),
                              label: const Text('Pending Application'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openFullQuestionnaire,
                              icon: const Icon(Icons.quiz_outlined),
                              label: const Text('Dayung Recommendations'),
                            ),
                          ),
                        ],
                      ),
                    ),
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
