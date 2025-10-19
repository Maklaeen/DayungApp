import 'dart:async';
import 'package:capstone_app/screens/dayung_suggestions.dart' hide kPrimary;
import 'package:flutter/material.dart';
import 'package:capstone_app/pages/deathnoticedetail.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Additional colors for modern design
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kDanger = Color(0xFFEF4444);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF047857);
const double kEdge = 16;

class RecentDeathNotices extends StatefulWidget {
  final int? dayungUnitId;
  const RecentDeathNotices({Key? key, this.dayungUnitId}) : super(key: key);

  @override
  State<RecentDeathNotices> createState() => _RecentDeathNoticesState();
}

class _RecentDeathNoticesState extends State<RecentDeathNotices> {
  bool _loading = true;

  // Split lists
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _beneficiaries = [];

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();

    if (widget.dayungUnitId == null) {
      setState(() => _loading = false);
      return;
    }

    _fetchDeathNotices();

    // Realtime stream filtered by dayung
    final client = Supabase.instance.client;
    _sub = client
        .from('death_notices')
        .stream(primaryKey: ['id'])
        .eq('dayung_unit_id', widget.dayungUnitId as Object)
        .listen((data) {
          _applySplit(List<Map<String, dynamic>>.from(data));
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _applySplit(List<Map<String, dynamic>> rows) {
    final unitId = widget.dayungUnitId;

    // Filter by dayung_unit_id before splitting
    final filtered = rows.where((r) {
      final v = r['dayung_unit_id'];
      final asInt = v is int ? v : int.tryParse('$v');
      return asInt == unitId;
    }).toList();

    filtered.sort((a, b) {
      final ad = (a['date_of_death'] ?? '').toString();
      final bd = (b['date_of_death'] ?? '').toString();
      return bd.compareTo(ad); // desc
    });

    final members = filtered
        .where((r) => (r['deceased_type'] ?? 'member') == 'member')
        .toList();
    final beneficiaries = filtered
        .where((r) => r['deceased_type'] == 'beneficiary')
        .toList();

    setState(() {
      _members = members;
      _beneficiaries = beneficiaries;
      _loading = false;
    });
  }

  Future<void> _fetchDeathNotices() async {
    if (widget.dayungUnitId == null) {
      setState(() {
        _members = [];
        _beneficiaries = [];
        _loading = false;
      });
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('death_notices')
          .select(
            'id, name, date_of_death, barangay, dayung_unit_id, deceased_type, dob, deceased_age',
          )
          .eq('dayung_unit_id', widget.dayungUnitId as Object)
          .order('date_of_death', ascending: false);

      _applySplit(List<Map<String, dynamic>>.from(response as List));
    } catch (_) {
      setState(() {
        _members = [];
        _beneficiaries = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final textScale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

    // Modern "No Dayung" UI
    if (widget.dayungUnitId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E40AF), Color(0xFF3B82F6), Color(0xFFF8FAFC)],
              stops: [0.0, 0.15, 0.15],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Modern Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFFFFF), Color(0xFFE0E7FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: const Color(0xFF1E40AF).withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Color(0xFF1E40AF),
                            size: 24,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          'Recent Deaths',
                          style: TextStyle(
                            fontSize: isWide ? 32 : 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontFamily: 'Montserrat',
                            letterSpacing: 0.5,
                            shadows: [
                              const Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 2),
                                blurRadius: 4,
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
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: kBorderColor.withOpacity(0.3),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        kPrimary.withOpacity(0.1),
                                        kPrimary.withOpacity(0.05),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: kPrimary.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.home_rounded,
                                    color: kPrimary,
                                    size: 48,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'No Dayung Assigned',
                                  style: TextStyle(
                                    fontSize: isWide ? 24 : 20,
                                    fontWeight: FontWeight.w800,
                                    color: kText,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Please apply for a Dayung first to view death notices and vigil locations.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: isWide ? 16 : 14,
                                    color: kSubText,
                                    fontFamily: 'OpenSans',
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [kPrimary, kPrimaryLight],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: kPrimary.withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const DayungSuggestionsPage(),
                                          ),
                                        );
                                      },
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.add_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Apply a Dayung',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              fontFamily: 'Montserrat',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

    // Modernized tabbed UI
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E40AF), Color(0xFF3B82F6), Color(0xFFF8FAFC)],
              stops: [0.0, 0.15, 0.15],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Modern Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFFFFF), Color(0xFFE0E7FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: const Color(0xFF1E40AF).withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Color(0xFF1E40AF),
                            size: 24,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          'Deaths and Vigil locations',
                          style: TextStyle(
                            fontSize: isWide ? 32 : 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontFamily: 'Montserrat',
                            letterSpacing: 0.5,
                            shadows: [
                              const Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Tabs
                const TabBar(
                  labelColor: kPrimary,
                  unselectedLabelColor: Colors.black54,
                  indicatorColor: kPrimary,
                  tabs: [
                    Tab(text: 'Members'),
                    Tab(text: 'Beneficiaries'),
                  ],
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
                    child: _loading
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFF8FAFC),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: kBorderColor.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        color: kPrimary,
                                        strokeWidth: 3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Loading death notices...',
                                    style: TextStyle(
                                      color: kPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : TabBarView(
                            children: [
                              _modernList(context, _members, textScale, isWide),
                              _modernList(
                                context,
                                _beneficiaries,
                                textScale,
                                isWide,
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
    );
  }

  // Modernized list UI
  Widget _modernList(
    BuildContext context,
    List<Map<String, dynamic>> items,
    double textScale,
    bool isWide,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kBorderColor.withOpacity(0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kSubText.withOpacity(0.1),
                      kSubText.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kSubText.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Icon(Icons.inbox_rounded, color: kSubText, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                'No Death Notices Found',
                style: TextStyle(
                  fontSize: isWide ? 24 : 20,
                  fontWeight: FontWeight.w800,
                  color: kText,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'There are currently no death notices for your Dayung unit.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isWide ? 16 : 14,
                  color: kSubText,
                  fontFamily: 'OpenSans',
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final notice = items[index];
          final name = (notice['name'] ?? '').toString();
          final dod = (notice['date_of_death'] ?? '').toString();
          final barangay = notice['barangay']?.toString();

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: kBorderColor.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => DeathNoticeDetail.byNoticeId(
                      noticeId: notice['id'] as int,
                      dayungUnitId: widget.dayungUnitId,
                      name: notice['name']?.toString(),
                      date: notice['date_of_death']?.toString(),
                      barangay: notice['barangay']?.toString(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [kPrimary, kPrimaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: kPrimary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                fontWeight: FontWeight.w700,
                                color: kText,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$dod${barangay != null && barangay.isNotEmpty ? ' • $barangay' : ''}',
                              style: TextStyle(
                                fontSize: isWide ? 14 : 12,
                                color: kSubText,
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kSubText.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: kSubText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
