import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:capstone_app/utils/dayung_service_tags.dart';
import 'package:capstone_app/utils/dayung_similarity.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Modern palette (reuse from other files)
const Color kPrimary = Color(0xFF0D47A1);
const kPrimaryLight = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFFAFAF7);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kText = Color(0xFF1F2937);
const Color kBorderColor = Color(0xFFE5E7EB);

class DayungSuggestionsPage extends StatefulWidget {
  const DayungSuggestionsPage({super.key});

  @override
  State<DayungSuggestionsPage> createState() => _DayungSuggestionsPageState();
}

Widget _buildAppliedBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4D6),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Already applied',
      style: TextStyle(
        color: Color(0xFF8A5A00),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DayungSuggestionsPageState extends State<DayungSuggestionsPage> {
  final _sb = Supabase.instance.client;
  bool _showSearchBar = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allDayungs = [];
  Set<int> _appliedDayungIds = {};
  Map<int, double> _matchPercentages = {};
  bool _loading = false;
  String? _error;
  String? _matchMessage;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _fetchDayungs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }

  bool _isDayungApplied(Map<String, dynamic> dayung) {
    final id = _toInt(dayung['id']);
    return id != null && _appliedDayungIds.contains(id);
  }

  Map<String, dynamic> _normalizeDayung(Map<String, dynamic> d) {
    final lat = _toDouble(d['latitude'] ?? d['lat']);
    final lng = _toDouble(d['longitude'] ?? d['lng']);
    return {...d, 'latitude': lat, 'longitude': lng, 'lat': lat, 'lng': lng};
  }

  String _address(Map<String, dynamic> d) {
    return [
      if (d['barangay'] != null) d['barangay'],
      if (d['city'] != null) d['city'],
      if (d['province'] != null) d['province'],
    ].where((e) => e != null && e.toString().isNotEmpty).join(', ');
  }

  Future<void> _fetchDayungs() async {
    setState(() {
      _loading = true;
      _error = null;
      _appliedDayungIds = {};
      _matchPercentages = {};
      _matchMessage = null;
    });
    try {
      final res = await _sb
          .from('dayung_units')
          .select('id, name, barangay, city, province, latitude, longitude')
          .order('name');
      final userId = _sb.auth.currentUser?.id;
      final applicationRows = userId == null
          ? <dynamic>[]
          : await _sb
                .from('applications')
                .select('dayung_unit_id')
                .eq('user_id', userId);
      final appliedDayungIds = <int>{
        for (final row in applicationRows)
          if (_toInt(row['dayung_unit_id']) != null)
            _toInt(row['dayung_unit_id'])!,
      };
      if (!mounted) return;
      setState(() {
        _allDayungs = List<Map<String, dynamic>>.from(
          res,
        ).map((e) => _normalizeDayung(e)).toList();
        _appliedDayungIds = appliedDayungIds;
      });
      await _fetchMatchPercentages();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Failed to load Dayung units: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load Dayung units. Please try again.';
      });
    }
  }

  Future<void> _fetchMatchPercentages() async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _matchPercentages = {};
        _matchMessage =
            'Sign in and set at least 5 preferences to see match percentages.';
      });
      return;
    }

    try {
      final preferences = await _sb
          .from('user_preferences')
          .select(
            'meeting_frequency, payment_method, contribution_amount, '
            'membership_payment, penalty_payment, '
            '${dayungServiceTagColumns.values.join(',')}',
          )
          .eq('user_id', userId)
          .maybeSingle();

      if (preferences == null ||
          !hasEnoughRecommendationPreferences(
            countDayungPreferences(Map<String, dynamic>.from(preferences)),
          )) {
        if (!mounted) return;
        setState(() {
          _matchPercentages = {};
          _matchMessage =
              'Choose at least 5 preferences in Dayung Preferences to see match percentages.';
        });
        return;
      }

      final rules = await _sb
          .from('dayung_rules')
          .select(
            'dayung_unit_id, meeting_frequency, payment_method, '
            'exactamountforcollection, exactamountformembership, '
            'penalty_payment, exactpenaltypayment, '
            '${dayungServiceTagColumns.values.join(',')}',
          );
      final userLocation = await _sb
          .from('users')
          .select('latitude, longitude')
          .eq('id', userId)
          .maybeSingle();
      final userLatitude = _toDouble(userLocation?['latitude']);
      final userLongitude = _toDouble(userLocation?['longitude']);
      final userVector = generateDayungPreferenceVector(
        Map<String, dynamic>.from(preferences),
      );
      final dayungsById = {
        for (final dayung in _allDayungs)
          if (_toInt(dayung['id']) != null) _toInt(dayung['id'])!: dayung,
      };
      final percentages = <int, double>{};
      var missingUnitLocation = false;
      for (final rawRule in rules) {
        final rule = Map<String, dynamic>.from(rawRule as Map);
        final unitId = _toInt(rule['dayung_unit_id']);
        if (unitId == null) continue;

        final dayung = dayungsById[unitId];
        final latitude = _toDouble(dayung?['latitude']);
        final longitude = _toDouble(dayung?['longitude']);
        double? distanceKm;
        if (userLatitude != null &&
            userLongitude != null &&
            latitude != null &&
            longitude != null) {
          distanceKm = dayungDistanceKm(
            userLatitude,
            userLongitude,
            latitude,
            longitude,
          );
        } else {
          missingUnitLocation = true;
        }
        final score = computeHybridScore(
          userVector,
          buildDayungRuleVector(rule),
        );
        percentages[unitId] = hybridScoreAsPercentage(
          score.finalScore,
          distanceKm: distanceKm,
        );
      }

      if (!mounted) return;
      setState(() {
        _matchPercentages = percentages;
        _matchMessage = userLatitude == null || userLongitude == null
            ? 'Your location is unavailable. Percentages are based on preferences only.'
            : missingUnitLocation
            ? 'Match score combines preferences (70%) and distance (30% within 20 km). Some percentages are preference-only because a location is unavailable.'
            : 'Match score combines preference fit (70%) and distance (30% within 20 km).';
      });
    } catch (e, stackTrace) {
      debugPrint('Failed to load Dayung match percentages: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _matchPercentages = {};
        _matchMessage =
            'Unable to load match percentages. Refresh to try again.';
      });
    }
  }

  double? _matchPercentage(Map<String, dynamic> dayung) {
    final id = _toInt(dayung['id']);
    return id == null ? null : _matchPercentages[id];
  }

  Widget _buildMatchBadge(double? percentage) {
    if (percentage == null) {
      return const Text(
        'Not available',
        style: TextStyle(color: kSubText, fontWeight: FontWeight.w600),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${percentage.toStringAsFixed(0)}% match',
        style: const TextStyle(
          color: kAccent,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredDayungs {
    final q = _query.trim().toLowerCase();
    final dayungs = _allDayungs.where((d) {
      if (q.isEmpty && _isDayungApplied(d)) return false;
      if (q.isEmpty) return true;
      return (d['name'] ?? '').toString().toLowerCase().contains(q) ||
          (d['barangay'] ?? '').toString().toLowerCase().contains(q) ||
          (d['city'] ?? '').toString().toLowerCase().contains(q) ||
          (d['province'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
    if (_matchPercentages.isEmpty) return dayungs;

    dayungs.sort((a, b) {
      final percentageA = _matchPercentage(a);
      final percentageB = _matchPercentage(b);
      if (percentageA != null && percentageB != null) {
        final percentageComparison = percentageB.compareTo(percentageA);
        if (percentageComparison != 0) return percentageComparison;
      } else if (percentageA != null) {
        return -1;
      } else if (percentageB != null) {
        return 1;
      }
      return (a['name'] ?? '').toString().compareTo(
        (b['name'] ?? '').toString(),
      );
    });
    return dayungs;
  }

  Widget _buildModernHeader(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 20, 20, isWide ? 24 : 16, 24),
      decoration: const BoxDecoration(
        color: kPrimary,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _showSearchBar
                  ? SizedBox(
                      key: const ValueKey('searchBar'),
                      height: 48,
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search Dayung units',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Close search',
                            icon: const Icon(Icons.close, color: kSubText),
                            onPressed: () {
                              setState(() {
                                _showSearchBar = false;
                                _searchController.clear();
                                _query = '';
                              });
                            },
                          ),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(
                          fontSize: isWide ? 17 : 15,
                          color: kText,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    )
                  : Column(
                      key: const ValueKey('title'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find a Dayung',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: isWide ? 24 : 21,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Compare preference matches and explore Dayung locations.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: isWide ? 15 : 13,
                            height: 1.35,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _showSearchBar ? 'Close search' : 'Search',
            onPressed: () {
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) {
                  _searchController.clear();
                  _query = '';
                }
              });
            },
            icon: Icon(
              _showSearchBar ? Icons.close_rounded : Icons.search_rounded,
              color: Colors.white,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayungTable(
    BuildContext context,
    List<Map<String, dynamic>> dayungs, {
    required bool isWide,
  }) {
    if (!isWide) {
      return Column(
        children: [
          for (final rawDayung in dayungs)
            _buildDayungCard(context, _normalizeDayung(rawDayung)),
        ],
      );
    }

    return RecordDataTable(
      modernStyle: true,
      showCheckboxColumn: false,
      minWidth: 900,
      columnSpacing: 28,
      horizontalMargin: 20,
      dataRowMinHeight: 88,
      dataRowMaxHeight: 112,
      columns: const [
        DataColumn(label: Text('Dayung')),
        DataColumn(label: Text('Location')),
        DataColumn(label: Text('Match')),
        DataColumn(label: Text('Map')),
      ],
      rows: dayungs.map((dayung) {
        final normalized = _normalizeDayung(Map<String, dynamic>.from(dayung));
        final latitude = normalized['latitude'] as double?;
        final longitude = normalized['longitude'] as double?;
        final name = (dayung['name'] ?? 'Unnamed Dayung').toString();
        final address = _address(dayung);
        return DataRow(
          cells: [
            DataCell(
              SizedBox(
                width: 220,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: kPrimary,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: kText,
                            ),
                          ),
                          if (_isDayungApplied(dayung)) ...[
                            const SizedBox(height: 4),
                            _buildAppliedBadge(),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DataCell(
              SizedBox(
                width: 280,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: kPrimary,
                      size: 21,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        address.isEmpty ? 'Location not provided' : address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DataCell(_buildMatchBadge(_matchPercentage(normalized))),
            DataCell(
              latitude != null && longitude != null
                  ? FilledButton.icon(
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('View map'),
                      onPressed: () => _openDayungMap(context, normalized),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEAF2FC),
                        foregroundColor: kPrimary,
                        minimumSize: const Size(140, 48),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : const Text(
                      'Map unavailable',
                      style: TextStyle(
                        color: kSubText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDayungCard(BuildContext context, Map<String, dynamic> dayung) {
    final name = (dayung['name'] ?? 'Unnamed Dayung').toString();
    final address = _address(dayung);
    final latitude = dayung['latitude'] as double?;
    final longitude = dayung['longitude'] as double?;
    final hasCoordinates = latitude != null && longitude != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                    color: const Color(0xFFEAF2FC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: kPrimary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: kText,
                          height: 1.25,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      if (_isDayungApplied(dayung)) ...[
                        const SizedBox(height: 6),
                        _buildAppliedBadge(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildMatchBadge(_matchPercentage(dayung)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: kPrimary,
                  size: 22,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    address.isEmpty ? 'Location not provided' : address,
                    style: const TextStyle(
                      color: kText,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: hasCoordinates
                  ? FilledButton.icon(
                      onPressed: () => _openDayungMap(context, dayung),
                      icon: const Icon(Icons.map_outlined, size: 21),
                      label: const Text('View map location'),
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'OpenSans',
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.location_off_outlined, size: 21),
                      label: const Text('Map location unavailable'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDayungMap(
    BuildContext context,
    Map<String, dynamic> dayung,
  ) async {
    final navigator = Navigator.of(context);
    final result = await navigator.push(
      MaterialPageRoute(
        builder: (_) => DayungMapPage(
          dayung: dayung,
          isApplied: _isDayungApplied(dayung),
          isMember: false,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) navigator.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 720;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildModernHeader(context, isWide),
            Expanded(
              child: Container(
                margin: EdgeInsets.fromLTRB(
                  isWide ? 24 : 12,
                  isWide ? 24 : 16,
                  isWide ? 24 : 12,
                  0,
                ),
                decoration: BoxDecoration(
                  color: kCardBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  border: Border.all(color: kBorderColor),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: _buildBody(context, isWide),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isWide) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 40,
                  color: kDanger,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Could not load Dayung units',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kSubText,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _fetchDayungs,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  side: const BorderSide(color: kPrimary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
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

    if (_filteredDayungs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  size: 40,
                  color: kPrimary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _query.trim().isEmpty
                    ? _allDayungs.isEmpty
                          ? 'No Dayung units available'
                          : 'No Dayung units to explore'
                    : 'No matching Dayung units',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _query.trim().isEmpty
                    ? _allDayungs.isEmpty
                          ? 'Please check back later.'
                          : 'Search by name or location to find a Dayung you have already applied to.'
                    : 'Try another name or location.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kSubText,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (_query.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _query = '';
                      _searchController.clear();
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Clear search'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDayungs,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isWide ? 28 : 16,
          20,
          isWide ? 28 : 16,
          24,
        ),
        children: [
          if (_matchMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: kPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _matchMessage!,
                        style: const TextStyle(
                          color: kText,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_query.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '${_filteredDayungs.length} ${_filteredDayungs.length == 1 ? 'unit' : 'units'} to explore',
                style: const TextStyle(
                  color: kSubText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          _buildDayungTable(context, _filteredDayungs, isWide: isWide),
        ],
      ),
    );
  }
}
