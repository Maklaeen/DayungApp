import 'dart:async';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart' hide kPrimary;
import 'package:flutter/material.dart';
import 'package:capstone_app/pages/deathnoticedetail.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:provider/provider.dart';
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
  const RecentDeathNotices({super.key, this.dayungUnitId});

  @override
  State<RecentDeathNotices> createState() => _RecentDeathNoticesState();
}

class _RecentDeathNoticesState extends State<RecentDeathNotices> {
  bool _loading = true;

  // Split lists
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _beneficiaries = [];

  // Map of user_id to full_name
  Map<String, String> _userNames = {};

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    if (widget.dayungUnitId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final navigator = Navigator.of(context);
        final roleProv = context.read<DayungRoleProvider>();
        final unitProv = context.read<DayungUnitProvider>();
        int? fallback = roleProv.unitId ?? unitProv.currentUnitId;
        if (!mounted || fallback == null) return;
        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (_) => RecentDeathNotices(dayungUnitId: fallback),
          ),
        );
      });
      return;
    }
    _fetchDeathClaims();
    _sub = Supabase.instance.client
        .from('claims')
        .stream(primaryKey: ['id'])
        .eq('dayung_unit_id', widget.dayungUnitId!)
        .listen((data) => _applySplit(List<Map<String, dynamic>>.from(data)));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _applySplit(List<Map<String, dynamic>> rows) async {
    final unitId = widget.dayungUnitId;

    // Filter by dayung_unit_id before splitting
    final filtered = rows.where((r) {
      final v = r['dayung_unit_id'];
      final asInt = v is int ? v : int.tryParse('$v');
      return asInt == unitId && r['status'] == 'Approved';
    }).toList();

    filtered.sort((a, b) {
      final ad = (a['datesetamount'] ?? '').toString();
      final bd = (b['datesetamount'] ?? '').toString();
      return bd.compareTo(ad); // desc
    });

    final recentClaims = filtered.take(5).toList();

    final members = recentClaims
        .where((r) => (r['deceased_type'] ?? 'member') == 'member')
        .toList();
    final beneficiaries = recentClaims
        .where((r) => r['deceased_type'] == 'beneficiary')
        .toList();

    // Collect unique user_ids from members
    final userIds = members
        .map((m) => m['user_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    Map<String, String> userNames = {};
    if (userIds.isNotEmpty) {
      try {
        final userRows = await Supabase.instance.client
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds.toList())
            .limit(userIds.length);
        for (final row in userRows) {
          final id = row['id']?.toString();
          final name = row['full_name']?.toString();
          if (id != null && name != null) {
            userNames[id] = name;
          }
        }
      } catch (_) {}
    }

    // Attach full_name to each member
    final membersWithNames = members.map((m) {
      final userId = m['user_id']?.toString();
      if (userId != null && userNames.containsKey(userId)) {
        return {...m, 'full_name': userNames[userId]};
      }
      return m;
    }).toList();

    // Collect unique beneficiary_ids from beneficiaries
    final beneficiaryIds = beneficiaries
        .map((b) => b['beneficiary_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    Map<String, String> beneficiaryNames = {};
    if (beneficiaryIds.isNotEmpty) {
      try {
        final benRows = await Supabase.instance.client
            .from('beneficiaries')
            .select('id, full_name')
            .inFilter('id', beneficiaryIds.toList())
            .limit(beneficiaryIds.length);
        for (final row in benRows) {
          final id = row['id']?.toString();
          final name = row['full_name']?.toString();
          if (id != null && name != null) {
            beneficiaryNames[id] = name;
          }
        }
      } catch (_) {}
    }

    // Attach full_name to each beneficiary
    final beneficiariesWithNames = beneficiaries.map((b) {
      final benId = b['beneficiary_id']?.toString();
      if (benId != null && beneficiaryNames.containsKey(benId)) {
        return {...b, 'full_name': beneficiaryNames[benId]};
      }
      return b;
    }).toList();

    setState(() {
      _members = membersWithNames;
      _beneficiaries = beneficiariesWithNames;
      _userNames = userNames;
      _loading = false;
    });
  }

  Future<void> _fetchDeathClaims() async {
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
          .from('claims')
          .select(
            'id, PassedAway, date_of_death, datesetamount, vigil_barangay, dayung_unit_id, deceased_type, dob, deceased_age, user_id, beneficiary_id, status, title, vigil_address, vigil_latitude, vigil_longitude, death_certificate_url, valid_ids_url, amount, paid_count, unpaid_count, total_paid_amount, total_payment_amount',
          )
          .eq('dayung_unit_id', widget.dayungUnitId as Object)
          .ilike('status', 'approved')
          .order('datesetamount', ascending: false)
          .limit(5);

      await _applySplit(List<Map<String, dynamic>>.from(response as List));
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
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);

    // Modern "No Dayung" UI
    if (widget.dayungUnitId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // Modern Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
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
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: IconButton(
                        tooltip: 'Back',
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
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
                              color: kBorderColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
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
                                      kPrimary.withValues(alpha: 0.1),
                                      kPrimary.withValues(alpha: 0.05),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: kPrimary.withValues(alpha: 0.2),
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
                                      color: kPrimary.withValues(alpha: 0.3),
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
      );
    }

    // Modernized tabbed UI
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // Modern Header
              Container(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 28 : 16,
                  isWide ? 24 : 16,
                  isWide ? 28 : 16,
                  isWide ? 22 : 16,
                ),
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
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: IconButton(
                        tooltip: 'Back',
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ),
                    SizedBox(width: isWide ? 20 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Death Notices',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isWide ? 30 : 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                          const SizedBox(height: 3),
                          // Text(
                          //   'Vigil locations',
                          //   style: TextStyle(
                          //     fontSize: isWide ? 15 : 13,
                          //     fontWeight: FontWeight.w600,
                          //     color: Colors.white.withValues(alpha: 0.78),
                          //     fontFamily: 'OpenSans',
                          //   ),
                          // ),
                        ],
                      ),
                    ),
                    if (isWide)
                      const SizedBox(width: 64)
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
              const SizedBox(height: 14),
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
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          isWide ? 28 : 16,
                          14,
                          isWide ? 28 : 16,
                          0,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TabBar(
                            labelColor: kPrimary,
                            unselectedLabelColor: kSubText,
                            indicatorColor: kPrimary,
                            indicatorSize: TabBarIndicatorSize.label,
                            indicatorWeight: 3,
                            dividerColor: Colors.transparent,
                            labelStyle: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            tabs: const [
                              Tab(text: 'Members'),
                              Tab(text: 'Beneficiaries'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _loading
                            ? const DayungPageSkeleton(
                                layout: DayungSkeletonLayout.list,
                                itemCount: 5,
                              )
                            : TabBarView(
                                children: [
                                  _modernList(
                                    context,
                                    _members,
                                    textScale,
                                    isWide,
                                  ),
                                  _modernList(
                                    context,
                                    _beneficiaries,
                                    textScale,
                                    isWide,
                                    isBeneficiaryTab: true,
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
    bool isWide, {
    bool isBeneficiaryTab = false,
  }) {
    // All users can now see beneficiary full_name
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
            border: Border.all(
              color: kBorderColor.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
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
                      kSubText.withValues(alpha: 0.1),
                      kSubText.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kSubText.withValues(alpha: 0.2),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 12, endIndent: 12),
            itemBuilder: (context, index) =>
                _noticeMobileRow(context, items[index]),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          children: [
            RecordDataTable(
              modernStyle: true,
              minWidth: constraints.maxWidth > 1000
                  ? constraints.maxWidth
                  : 1000,
              dataRowMinHeight: 88,
              dataRowMaxHeight: 120,
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Date of death')),
                DataColumn(label: Text('Vigil Details')),
              ],
              rows: items
                  .map((notice) => _noticeDataRow(context, notice))
                  .toList(),
            ),
          ],
        );
      },
    );
  }

  String _noticeName(Map<String, dynamic> notice) {
    final name = (notice['full_name'] ?? notice['PassedAway'] ?? '')
        .toString()
        .trim();
    return name.isEmpty ? 'Unknown' : name;
  }

  String _noticeVigilLocation(Map<String, dynamic> notice) {
    final location = (notice['vigil_barangay'] ?? notice['vigil_address'] ?? '')
        .toString()
        .trim();
    return location.isEmpty ? '—' : location;
  }

  void _showNoticeDetails(BuildContext context, Map<String, dynamic> notice) {
    DeathNoticeDetail.showVigilDetails(
      context: context,
      noticeId: notice['id']?.toString(),
      dayungUnitId: widget.dayungUnitId,
      name: _noticeName(notice),
      date: notice['date_of_death']?.toString(),
      birthDate: notice['dob']?.toString(),
      latitude: _toDouble(notice['vigil_latitude']),
      longitude: _toDouble(notice['vigil_longitude']),
      barangay:
          notice['vigil_barangay']?.toString() ??
          notice['vigil_address']?.toString(),
    );
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  Widget _noticeMobileRow(BuildContext context, Map<String, dynamic> notice) {
    final name = _noticeName(notice);
    final isBeneficiary = notice['deceased_type'] == 'beneficiary';
    final date = (notice['date_of_death'] ?? '').toString();

    return InkWell(
      onTap: () => _showNoticeDetails(context, notice),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isBeneficiary ? 'Beneficiary' : 'Member',
                    style: const TextStyle(
                      fontSize: 12,
                      color: kSubText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _noticeMobileDetail(
                    'Date of death',
                    date.isEmpty ? '—' : date,
                  ),
                  const SizedBox(height: 4),
                  _vigilDetailsMobile(context, notice),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: kSubText),
          ],
        ),
      ),
    );
  }

  Widget _noticeMobileDetail(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: kSubText),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: kText),
          ),
        ),
      ],
    );
  }

  Widget _vigilDetailsMobile(
    BuildContext context,
    Map<String, dynamic> notice,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _noticeMobileDetail('Location', _noticeVigilLocation(notice)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showNoticeDetails(context, notice),
          icon: const Icon(Icons.map_outlined, size: 18),
          label: const Text('View Vigil Details'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kPrimary,
            side: const BorderSide(color: kPrimaryLight),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _vigilDetailsTableCell(
    BuildContext context,
    Map<String, dynamic> notice,
  ) {
    return SizedBox(
      width: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: kPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _noticeVigilLocation(notice),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showNoticeDetails(context, notice),
            icon: const Icon(Icons.map_outlined, size: 17),
            label: const Text('View Vigil Details'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: const BorderSide(color: kPrimaryLight),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  DataRow _noticeDataRow(BuildContext context, Map<String, dynamic> notice) {
    final isBeneficiary = notice['deceased_type'] == 'beneficiary';
    final date = (notice['date_of_death'] ?? '').toString();
    return DataRow(
      onSelectChanged: (_) => _showNoticeDetails(context, notice),
      cells: [
        DataCell(Text(_noticeName(notice))),
        DataCell(Text(isBeneficiary ? 'Beneficiary' : 'Member')),
        DataCell(Text(date.isEmpty ? '—' : date)),
        DataCell(_vigilDetailsTableCell(context, notice)),
      ],
    );
  }
}
