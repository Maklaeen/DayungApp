import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/widgets/record_data_table.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class SecretaryMembersPage extends StatefulWidget {
  final int dayungUnitId;
  const SecretaryMembersPage({super.key, required this.dayungUnitId});

  @override
  State<SecretaryMembersPage> createState() => _SecretaryMembersPageState();
}

String _initialOf(dynamic name) {
  if (name is String) {
    final t = name.trim();
    if (t.isNotEmpty) return t.substring(0, 1).toUpperCase();
  }
  return 'M';
}

class _SecretaryMembersPageState extends State<SecretaryMembersPage>
    with SingleTickerProviderStateMixin {
  static const double _kMaxContentWidth = 1000;

  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _infoMsg;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late TabController _tabController;

  List<Map<String, dynamic>> _rows = [];
  final Map<int, String> _dayungNames = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _infoMsg = null;
    });
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _infoMsg = 'Please log in.';
          _rows = [];
          _dayungNames.clear();
        });
        return;
      }

      // Only fetch the selected dayung unit
      final dayungId = widget.dayungUnitId;

      final dayung = await _sb
          .from('dayung_units')
          .select('id,name')
          .eq('id', dayungId)
          .single();

      _dayungNames
        ..clear()
        ..addEntries([
          MapEntry(dayungId, (dayung['name'] ?? 'Dayung') as String),
        ]);

      final apps = await _sb
          .from('applications')
          .select(
            'user_id, status, dayung_unit_id, approved_at, isRemovedInDayung, '
            'user:users(id, full_name, email, profile_url, is_deceased, date_of_death)',
          )
          .eq('dayung_unit_id', dayungId) // <--- strict filter!
          .inFilter('status', ['approved', 'pending'])
          .order('approved_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(apps);

      final byKey = <String, Map<String, dynamic>>{};
      for (final r in list) {
        final u = r['user'] as Map<String, dynamic>?;
        final userId = (u?['id'] ?? r['user_id']).toString();
        final dayungId = r['dayung_unit_id'] as int;
        final key = '$userId-$dayungId';
        if (!byKey.containsKey(key)) {
          byKey[key] = r;
        } else {
          final prev = byKey[key]!;
          final prevAt = prev['approved_at']?.toString();
          final currAt = r['approved_at']?.toString();
          if (currAt != null &&
              (prevAt == null ||
                  DateTime.tryParse(
                        currAt,
                      )?.isAfter(DateTime.tryParse(prevAt) ?? DateTime(0)) ==
                      true)) {
            byKey[key] = r;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = byKey.values.toList()
          ..sort((a, b) {
            final sa = (a['status'] ?? '').toString();
            final sb = (b['status'] ?? '').toString();
            if (sa != sb) return sa == 'approved' ? -1 : 1;
            final ta = DateTime.tryParse(a['approved_at']?.toString() ?? '');
            final tb = DateTime.tryParse(b['approved_at']?.toString() ?? '');
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _infoMsg = e.message.isEmpty ? 'Load failed (policies?)' : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _infoMsg = 'Unexpected error loading members';
      });
    }
  }

  List<Map<String, dynamic>> get _approved => _rows.where((r) {
    final status = (r['status'] ?? '').toString();
    final removedInDayung = r['isRemovedInDayung'] == true;
    final u = r['user'] as Map<String, dynamic>?;
    final deceased = (u?['is_deceased'] == true);
    return status == 'approved' && !removedInDayung && !deceased;
  }).toList();

  List<Map<String, dynamic>> get _pending => _rows.where((r) {
    final status = (r['status'] ?? '').toString();
    final u = r['user'] as Map<String, dynamic>?;
    final deceased = (u?['is_deceased'] == true);
    return status == 'pending' && !deceased;
  }).toList();

  List<Map<String, dynamic>> get _deceased => _rows.where((r) {
    final u = r['user'] as Map<String, dynamic>?;
    return (u?['is_deceased'] == true);
  }).toList();

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() => _load();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          final horizontalPadding = isWide ? constraints.maxWidth * 0.15 : 20.0;
          final headerFontSize = isWide ? 28.0 : 20.0;

          return Column(
            children: [
              // Responsive Modern Header (copied/adapted from beneficiaries_tab.dart)
              Container(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  isWide ? 60 : 32,
                  horizontalPadding,
                  isWide ? 48 : 32,
                ),
                decoration: BoxDecoration(
                  color: kPrimaryDark,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryDark.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
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
                    const Icon(
                      Icons.people_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Members',
                        style: TextStyle(
                          fontSize: headerFontSize,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search member...',
                    hintStyle: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontFamily: 'OpenSans',
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: kPrimary,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colors.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.onSurface,
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (q) =>
                      setState(() => _searchQuery = q.trim().toLowerCase()),
                ),
              ),

              // Tabs
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                color: colors.surfaceContainerHigh,
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_list_rounded,
                      color: colors.onSurfaceVariant,
                      size: 16,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, _) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _NavTab(
                                label: 'Active',
                                icon: Icons.check_circle_rounded,
                                selected: _tabController.index == 0,
                                onTap: () => _tabController.animateTo(0),
                              ),

                              _NavTab(
                                label: 'Deceased',
                                icon: Icons.person_off_rounded,
                                selected: _tabController.index == 2,
                                onTap: () => _tabController.animateTo(2),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: _loading
                    ? const DayungPageSkeleton(
                        layout: DayungSkeletonLayout.list,
                        padding: EdgeInsets.all(16),
                        itemCount: 3,
                      )
                    : (_infoMsg != null)
                    ? Center(
                        child: Container(
                          margin: const EdgeInsets.all(20),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colors.outlineVariant,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 15,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Text(
                            _infoMsg!,
                            style: TextStyle(
                              fontSize: 16,
                              color: colors.onSurface,
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, _) {
                          return Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: _kMaxContentWidth,
                                    ),
                                    child: TabBarView(
                                      controller: _tabController,
                                      children: [
                                        _memberList(_approved, mode: 'active'),
                                        _memberList(_pending, mode: 'pending'),
                                        _memberList(
                                          _deceased,
                                          mode: 'deceased',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _memberList(
    List<Map<String, dynamic>> list, {
    String mode = 'active',
  }) {
    final colors = Theme.of(context).colorScheme;
    List<Map<String, dynamic>> filtered = list;
    if (_searchQuery.isNotEmpty) {
      filtered = list.where((r) {
        final u = r['user'] as Map<String, dynamic>?;
        final name = (u?['full_name'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery);
      }).toList();
    }

    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 120),
            Icon(Icons.people_outline, size: 48, color: colors.onSurfaceVariant),
            SizedBox(height: 12),
            Center(
              child: Text(
                'No members in this status',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          RecordDataTable(
            minWidth: 720,
            columns: const [
              DataColumn(label: Text('Member')),
              DataColumn(label: Text('Dayung')),
              DataColumn(label: Text('Status')),
            ],
            rows: filtered
                .map((row) => _memberDataRow(row, mode: mode))
                .toList(),
          ),
        ],
      ),
    );
  }

  DataRow _memberDataRow(Map<String, dynamic> r, {required String mode}) {
    final colors = Theme.of(context).colorScheme;
    final u = r['user'] as Map<String, dynamic>?;
    final profileUrl = (u?['profile_url'] as String?)?.trim();
    final dayungId = r['dayung_unit_id'] as int?;
    final dayungName = dayungId != null
        ? (_dayungNames[dayungId] ?? 'Dayung')
        : 'Dayung';

    String chipText;
    Color chipColor;
    if (mode == 'deceased') {
      chipText = 'deceased';
      chipColor = colors.error;
    } else {
      final status = (r['status'] ?? '').toString();
      chipText = status;
      chipColor = status == 'approved'
          ? colors.secondary
          : status == 'pending'
          ? colors.tertiary
          : colors.onSurfaceVariant;
    }

    final title = (u?['full_name'] as String?)?.trim().isNotEmpty == true
        ? (u?['full_name'] as String).trim()
        : 'Member';
    final onTap = mode == 'active'
        ? () {
            final uuid = (u?['id'] as String?)?.trim().isNotEmpty == true
                ? (u?['id'] as String).trim()
                : r['user_id']?.toString().trim();
            _showBeneficiariesModal(context, uuid, u?['full_name']);
          }
        : null;

    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                backgroundImage: profileUrl != null && profileUrl.isNotEmpty
                    ? NetworkImage(profileUrl)
                    : null,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                radius: 18,
                child: profileUrl == null || profileUrl.isEmpty
                    ? Text(
                        _initialOf(u?['full_name']),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: colors.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: colors.onSurface,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          onTap: onTap,
        ),
        DataCell(
          Text(dayungName, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: onTap,
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: chipColor),
            ),
            child: Text(
              chipText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: chipColor,
              ),
            ),
          ),
          onTap: onTap,
        ),
      ],
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                  fontFamily: 'Montserrat',
                ),
              ),
            ],
          ),
          if (selected) ...[
            const SizedBox(height: 4),
            Container(
              height: 3,
              width: label.length * 8.0,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showBeneficiariesModal(
  BuildContext context,
  String? userId,
  String? userName,
) async {
  final String uuid = (userId ?? '').trim();
  if (uuid.isEmpty) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final futureBeneficiaries = Supabase.instance.client
          .from('beneficiaries')
          .select(
            'id, full_name, relationship, dob, status, birth_certificate, user_id',
          )
          .eq('user_id', uuid)
          .order('full_name', ascending: true);

      final futureContribs = _fetchLastContributionsForUser(uuid, max: 5);

      return FutureBuilder<dynamic>(
        future: futureBeneficiaries,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 300,
              child: DayungPageSkeleton(
                layout: DayungSkeletonLayout.list,
                padding: EdgeInsets.all(8),
                itemCount: 2,
              ),
            );
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load beneficiaries: ${snap.error}'),
            );
          }

          final list = (snap.data as List<dynamic>? ?? [])
              .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map),
              )
              .toList();

          final userFuture = Supabase.instance.client
              .from('users')
              .select(
                'mobile_number, birth_certificate_url, marriage_certificate_url, death_certificate_url',
              )
              .eq('id', uuid)
              .limit(1)
              .then<Map<String, dynamic>?>((rows) {
                final l = rows as List<dynamic>?;
                if (l == null || l.isEmpty) return null;
                return Map<String, dynamic>.from(l.first as Map);
              });

          return LayoutBuilder(
            builder: (context, constraints) {
              final colors = Theme.of(context).colorScheme;
              String fmtDate(String iso) =>
                  iso.isEmpty ? '—' : (iso.split('T').first);

              return Container(
                height: MediaQuery.of(context).size.height * 0.8,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colors.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.shadow.withValues(alpha: 0.12),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: colors.onPrimaryContainer,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName ?? 'Member',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: colors.onSurface,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Member Details',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.onSurfaceVariant,
                                    fontFamily: 'OpenSans',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: Icon(
                                Icons.close,
                                color: colors.onSurfaceVariant,
                                size: 20,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(32),
                            topRight: Radius.circular(32),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.shadow.withValues(alpha: 0.12),
                              blurRadius: 20,
                              offset: const Offset(0, -5),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FutureBuilder<Map<String, dynamic>?>(
                                future: userFuture,
                                builder: (ctx, uSnap) {
                                  final u = uSnap.data ?? const {};
                                  final phone = (u['mobile_number'] ?? '')
                                      .toString();
                                  final hasBirth =
                                      (u['birth_certificate_url'] ?? '')
                                          .toString()
                                          .isNotEmpty;
                                  final hasMarriage =
                                      (u['marriage_certificate_url'] ?? '')
                                          .toString()
                                          .isNotEmpty;
                                  final hasDeath =
                                      (u['death_certificate_url'] ?? '')
                                          .toString()
                                          .isNotEmpty;

                                  Widget docItem(
                                    String label,
                                    bool ok,
                                  ) => Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: ok
                                          ? const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.1)
                                          : colors.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: ok
                                            ? const Color(
                                                0xFF10B981,
                                              ).withValues(alpha: 0.3)
                                            : colors.outlineVariant,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          ok
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded,
                                          color: ok
                                              ? colors.secondary
                                              : colors.onSurfaceVariant,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: ok
                                                ? colors.secondary
                                                : colors.onSurface,
                                            fontFamily: 'OpenSans',
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: colors.outlineVariant,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.03,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: colors.primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                Icons.person_rounded,
                                                color: colors.onPrimaryContainer,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (userName ?? 'Member'),
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 16,
                                                      color: colors.onSurface,
                                                      fontFamily: 'Montserrat',
                                                    ),
                                                  ),
                                                  if (phone.isNotEmpty)
                                                    Text(
                                                      phone,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: colors.onSurfaceVariant,
                                                        fontFamily: 'OpenSans',
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          'Last Contribution:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: colors.onSurface,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        FutureBuilder<
                                          List<Map<String, dynamic>>
                                        >(
                                          future: futureContribs,
                                          builder: (ctx, cSnap) {
                                            if (cSnap.connectionState !=
                                                ConnectionState.done) {
                                              return Container(
                                                height: 18,
                                                width: 180,
                                                decoration: BoxDecoration(
                                                  color: colors.surfaceContainerHigh,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                              );
                                            }
                                            final data = cSnap.data ?? const [];
                                            if (data.isEmpty) {
                                              return Text(
                                                '—',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  color: colors.onSurface,
                                                  fontFamily: 'OpenSans',
                                                ),
                                              );
                                            }
                                            final last = data.first;
                                            final amt =
                                                (last['amount'] as double?) ??
                                                0.0;
                                            final date = (last['date'] ?? '')
                                                .toString();
                                            return Text(
                                              '₱ ${amt.toStringAsFixed(0)} on ${fmtDate(date)}',
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: colors.onSurface,
                                                fontFamily: 'OpenSans',
                                                fontWeight: FontWeight.w700,
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Required Documents',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: colors.onSurface,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        docItem('Birth Certificate', hasBirth),
                                        const SizedBox(height: 8),
                                        docItem(
                                          'Marriage Certificate',
                                          hasMarriage,
                                        ),
                                        const SizedBox(height: 8),
                                        docItem('Death Certificate', hasDeath),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: futureContribs,
                                builder: (ctx, cSnap) {
                                  if (cSnap.connectionState !=
                                      ConnectionState.done) {
                                    return const SizedBox.shrink();
                                  }
                                  final contribs = cSnap.data ?? const [];
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Last Contributions',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: colors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (contribs.isEmpty)
                                        Text(
                                          'No paid contributions yet.',
                                          style: TextStyle(
                                            color: colors.onSurfaceVariant,
                                            fontSize: 16,
                                          ),
                                        )
                                      else
                                        ...contribs.map((c) {
                                          final amt =
                                              (c['amount'] as double? ?? 0.0)
                                                  .toStringAsFixed(0);
                                          final date = (c['date'] ?? '')
                                              .toString();
                                          final name =
                                              (c['notice_name'] ??
                                                      'Death Notice')
                                                  .toString();
                                          final dod = (c['date_of_death'] ?? '')
                                              .toString();
                                          return Card(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor:
                                                    colors.primaryContainer,
                                                child: Icon(
                                                  Icons.receipt_long,
                                                  color: colors
                                                      .onPrimaryContainer,
                                                ),
                                              ),
                                              title: Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Paid on ${fmtDate(date)}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: colors.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  if (dod.isNotEmpty)
                                                    Text(
                                                      'Date of Death: $dod',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: colors.onSurfaceVariant,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              trailing: Text(
                                                '₱ $amt',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: colors.primary,
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 22),
                              Text(
                                'Beneficiaries',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: colors.primary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (list.isEmpty)
                                Text(
                                  'No beneficiaries found.',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 16,
                                  ),
                                ),
                              ...list.map(
                                (b) => Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.person,
                                      color: colors.primary,
                                    ),
                                    title: Text(
                                      b['full_name'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Relationship: ${b['relationship'] ?? ''}',
                                        ),
                                        Text('DOB: ${b['dob'] ?? ''}'),
                                        Text('Status: ${b['status'] ?? ''}'),
                                        if ((b['birth_certificate'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          InkWell(
                                            onTap: () => launchUrl(
                                              Uri.parse(b['birth_certificate']),
                                            ),
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                'View Birth Certificate',
                                                style: TextStyle(
                                                  color: colors.primary,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

Future<List<Map<String, dynamic>>> _fetchLastContributionsForUser(
  String uid, {
  int max = 5,
}) async {
  final supabase = Supabase.instance.client;

  final payments = List<Map<String, dynamic>>.from(
    await supabase
        .from('payments')
        .select(
          'id, amount, status, created_at, dayung_unit_id, death_notice_id',
        )
        .eq('user_id', uid)
        .eq('status', 'paid')
        .order('created_at', ascending: false)
        .limit(max),
  );

  if (payments.isEmpty) return const [];

  final noticeIds = payments
      .map((p) => p['death_notice_id'])
      .where((id) => id != null)
      .cast<int>()
      .toSet()
      .toList();

  Map<String, Map<String, dynamic>> noticeById = {};
  if (noticeIds.isNotEmpty) {
    final notices = List<Map<String, dynamic>>.from(
      await supabase
          .from('death_notices')
          .select('id, name, date_of_death')
          .inFilter('id', noticeIds),
    );
    noticeById = {for (final n in notices) n['id'].toString(): n};
  }

  return payments.map((p) {
    final nid = p['death_notice_id']?.toString();
    final n = nid != null ? noticeById[nid] : null;
    final amount = (p['amount'] is num)
        ? (p['amount'] as num).toDouble()
        : double.tryParse('${p['amount']}') ?? 0.0;
    return {
      'date': (p['created_at'] ?? '').toString(),
      'amount': amount,
      'notice_name': (n?['name'] ?? 'Death Notice #$nid').toString(),
      'date_of_death': n?['date_of_death'],
    };
  }).toList();
}
