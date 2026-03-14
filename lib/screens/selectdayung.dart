import 'dart:convert';

import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';

// Modern color palette
const Color kPrimary = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFF8FAFC);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kText = Color(0xFF111827);
const Color kBorderColor = Color(0xFFE5E7EB);
const String _selectedDayungUnitOwnerIdKey = 'selectedDayungUnitOwnerId';

class SelectDayungPage extends StatefulWidget {
  const SelectDayungPage({super.key, this.requireSelection = false});

  final bool requireSelection;

  @override
  State<SelectDayungPage> createState() => _SelectDayungPageState();
}

class _SelectDayungPageState extends State<SelectDayungPage> {
  final _sb = Supabase.instance.client;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _joined = [];

  int? _prefsSelectedId;

  @override
  void initState() {
    super.initState();
    _loadCurrentSelectedId();
    _fetchJoinedDayung();
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  Future<void> _loadCurrentSelectedId() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = _sb.auth.currentUser?.id;
    final ownerId = prefs.getString(_selectedDayungUnitOwnerIdKey);
    if (currentUserId == null || ownerId == null || ownerId != currentUserId) {
      if (mounted) setState(() => _prefsSelectedId = null);
      return;
    }
    final raw = prefs.getString('selectedDayungUnit');
    if (raw != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(raw));
        final id = map['id'];
        final parsed = id is int ? id : int.tryParse('$id');
        if (mounted) setState(() => _prefsSelectedId = parsed);
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _persistSelectionAndNotify(
    Map<String, dynamic> d,
  ) async {
    final roleProvider = context.read<DayungRoleProvider>();
    final unitProvider = context.read<DayungUnitProvider>();
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeDayung(d);
    await prefs.setString('selectedDayungUnit', jsonEncode(normalized));
    await prefs.setString('selectedDayungUnitData', jsonEncode(normalized));
    final currentUserId = _sb.auth.currentUser?.id;
    if (currentUserId != null) {
      await prefs.setString(_selectedDayungUnitOwnerIdKey, currentUserId);
    }
    if (!mounted) return normalized;

    final id = normalized['id'] is int
        ? normalized['id'] as int
        : int.tryParse('${normalized['id']}');

    // Refresh roles and unit provider
    await roleProvider.refreshRoles(id);
    unitProvider.setDayungUnit(
      '${normalized['name'] ?? 'Dayung'}',
      obj: normalized,
    );

    // Update local fallback immediately so the UI marks "Already using"
    if (mounted) setState(() => _prefsSelectedId = id); // <-- add

    // Let the caller handle navigation
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
          .select(
            'id, secretary_id, treasurer_id, president_id, latitude, longitude, collector_id',
          )
          .or(
            'secretary_id.eq.${user.id},treasurer_id.eq.${user.id},president_id.eq.${user.id},collector_id.eq.${user.id}',
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

      // Tag each as member if in approved list
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

  Future<bool> _confirmRequiredExit() async {
    if (!widget.requireSelection) return true;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Leave selection?'),
          content: const Text(
            'You need to choose a Dayung unit to continue. If you go back now, you will return to login.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Stay here'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Back to login'),
            ),
          ],
        );
      },
    );

    return shouldLeave == true;
  }

  Widget _buildIntroCard(bool isWide) {
    final unitCount = _joined.length;
    final headline = widget.requireSelection
        ? 'Choose the Dayung unit for this session'
        : 'Switch to the Dayung unit you want to use';
    final supporting = widget.requireSelection
        ? 'This account has $unitCount available ${unitCount == 1 ? 'unit' : 'units'}. Pick one before entering the dashboard.'
        : 'Your active unit controls the dashboard data, notifications, and scoped actions you see.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isWide ? 56 : 48,
            height: isWide ? 56 : 48,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.apartment_rounded, color: kPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: isWide ? 18 : 16,
                    fontWeight: FontWeight.w800,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  supporting,
                  style: const TextStyle(color: kSubText, height: 1.45),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$unitCount ${unitCount == 1 ? 'unit' : 'units'} available',
                        style: const TextStyle(
                          color: kPrimaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.requireSelection)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kWarn.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Selection required',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayungCard(
    BuildContext context,
    Map<String, dynamic> d,
    bool isWide,
    int? currentId,
  ) {
    final did = d['id'] is int ? d['id'] as int : int.tryParse('${d['id']}');
    final isCurrent = currentId != null && did != null && currentId == did;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent ? kPrimary : kBorderColor,
          width: isCurrent ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isCurrent
                ? kPrimary.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: isCurrent ? 24 : 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? kPrimary.withValues(alpha: 0.14)
                        : kPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isCurrent ? Icons.check_circle_rounded : Icons.home_rounded,
                    color: isCurrent ? kPrimaryDark : kPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d['name'] ?? 'Dayung',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _address(d),
                        style: const TextStyle(color: kSubText, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrent ? kAccent.withValues(alpha: 0.12) : kBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isCurrent ? 'Active now' : 'Available',
                    style: TextStyle(
                      color: isCurrent ? const Color(0xFF047857) : kSubText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                      isCurrent
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked_rounded,
                      size: isWide ? 18 : 15,
                    ),
                    label: Text(
                      isCurrent ? 'Already using this unit' : 'Use this Dayung',
                      style: TextStyle(fontSize: isWide ? 15 : 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isCurrent ? kSubText : kPrimary,
                      side: BorderSide(
                        color: isCurrent ? kBorderColor : kPrimary,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: isCurrent
                        ? null
                        : () async {
                            final navigator = Navigator.of(context);
                            final normalized = await _persistSelectionAndNotify(
                              d,
                            );
                            if (!mounted) return;
                            navigator.pop(normalized);
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('View on Map'),
                    style: TextButton.styleFrom(
                      foregroundColor: kAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      final normalized = _normalizeDayung(d);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DayungMapPage(
                            dayung: normalized,
                            isMember: (d['is_member'] == true),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final navigator = Navigator.of(context);

    return PopScope<Object?>(
      canPop: !widget.requireSelection,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !widget.requireSelection) return;
        final canLeave = await _confirmRequiredExit();
        if (!mounted || !canLeave) return;
        navigator.pop(null);
      },
      child: Scaffold(
        backgroundColor: kBg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kPrimaryDark, kPrimary, kBg],
              stops: [0.0, 0.18, 0.18],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
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
                        onPressed: () async {
                          final canLeave = await _confirmRequiredExit();
                          if (!mounted || !canLeave) return;
                          navigator.pop(null);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Your Dayung',
                              style: TextStyle(
                                fontSize: isWide ? 24 : 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontFamily: 'Montserrat',
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.requireSelection
                                  ? 'Choose one unit to continue'
                                  : 'Review and switch your active unit',
                              style: const TextStyle(
                                color: Color(0xDBEFF6FF),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: kBg,
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
                    child: _buildBody(context, isWide),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isWide) {
    // Prefer provider; fallback to prefs
    final providerId = context.watch<DayungUnitProvider>().currentUnitId;
    final currentId = providerId ?? _prefsSelectedId; // <-- use fallback

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _fetchJoinedDayung);
    }
    if (_joined.isEmpty) {
      return _EmptyState(
        onFind: () async {
          final messenger = ScaffoldMessenger.of(context);
          final selected = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DayungSuggestionsPage()),
          );
          await _fetchJoinedDayung();
          if (!mounted) return;
          if (selected != null) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Application submitted. Awaiting approval.'),
              ),
            );
          }
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchJoinedDayung,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildIntroCard(isWide),
          const SizedBox(height: 16),
          for (final d in _joined)
            _buildDayungCard(context, d, isWide, currentId),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onFind});
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.home, color: kPrimary, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'No Dayung Found',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: kPrimaryDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You have not joined any Dayung yet.\nFind one to get started!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: kSubText),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.explore),
              label: const Text('Find a Dayung'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onFind,
            ),
          ],
        ),
      ),
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
            Icon(Icons.error_outline, size: 48, color: kDanger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: kDanger, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh, color: kPrimary),
              label: Text('Retry', style: TextStyle(color: kPrimary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kPrimary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
