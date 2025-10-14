import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class SecretaryMembersPage extends StatefulWidget {
  final int dayungUnitId; // NEW
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
  // Responsive breakpoints and max content width
  static const double _kTablet = 700; // >= tablet
  static const double _kDesktop = 1100; // >= desktop
  static const double _kMaxContentWidth = 1000;

  final supabase = Supabase.instance.client;
  bool _loading = true;
  String? _infoMsg;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late TabController _tabController;

  // Raw fetched members (approved + pending) for secretary’s dayungs
  List<Map<String, dynamic>> _rows = [];
  final Map<int, String> _dayungNames = {};
  List<int> _managedDayungIds = [];
  List<Map<String, dynamic>> _members = [];

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
      final unitId = widget.dayungUnitId;

      // Fetch approved + pending applications for this unit with embedded user
      final apps = await supabase
          .from('applications')
          .select(
            'id, status, dayung_unit_id, user:users(id, full_name, email, profile_url, is_deceased)',
          )
          .eq('dayung_unit_id', unitId)
          .inFilter('status', ['approved', 'pending'])
          .order('approved_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(
        apps,
      ).where((r) => r['user'] != null).toList();

      if (!mounted) return;
      setState(() {
        _rows = list;
        if (_rows.isEmpty) {
          _infoMsg = 'No members found for this Dayung.';
        }
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _infoMsg = 'Failed to load members: ${e.message}';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _infoMsg = 'Unexpected error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => _load();

  // Derived lists
  List<Map<String, dynamic>> get _approved => _rows.where((r) {
    final status = (r['status'] ?? '').toString();
    final u = r['user'] as Map<String, dynamic>?;
    return status == 'approved' && (u?['is_deceased'] != true);
  }).toList();

  List<Map<String, dynamic>> get _pending => _rows.where((r) {
    final status = (r['status'] ?? '').toString();
    final u = r['user'] as Map<String, dynamic>?;
    return status == 'pending' && (u?['is_deceased'] != true);
  }).toList();

  List<Map<String, dynamic>> get _deceased => _rows.where((r) {
    final u = r['user'] as Map<String, dynamic>?;
    return u?['is_deceased'] == true;
  }).toList();

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _approved.length;
    final pendingCount = _pending.length;
    final deceasedCount = _deceased.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'Active ($activeCount)'),
            Tab(text: 'Pending ($pendingCount)'),
            Tab(text: 'Deceased ($deceasedCount)'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_infoMsg != null)
          ? RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text(_infoMsg!)),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final padH = width >= 700 ? 24.0 : 12.0;
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(padH, 12, padH, 0),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search member...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: kPrimaryDark,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: kPrimary.withOpacity(.2),
                            ),
                          ),
                        ),
                        onChanged: (q) => setState(() {
                          _searchQuery = q.trim().toLowerCase();
                        }),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _memberList(
                            _approved,
                            mode: 'active',
                            constraints: constraints,
                          ),
                          _memberList(
                            _pending,
                            mode: 'pending',
                            constraints: constraints,
                          ),
                          _memberList(
                            _deceased,
                            mode: 'deceased',
                            constraints: constraints,
                          ),
                        ],
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
    required String mode,
    required BoxConstraints constraints,
  }) {
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
          children: const [
            SizedBox(height: 120),
            Icon(Icons.people_outline, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Center(child: Text('No members in this status')),
          ],
        ),
      );
    }

    final width = constraints.maxWidth;
    final useGrid = width >= 700;
    final crossAxisCount = width >= 1100 ? 3 : 2;

    if (!useGrid) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: filtered.length,
          itemBuilder: (_, i) => _memberTileCard(filtered[i], mode: mode),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.9,
        ),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _memberTileCard(filtered[i], mode: mode),
      ),
    );
  }

  Widget _memberTileCard(Map<String, dynamic> r, {required String mode}) {
    final u = r['user'] as Map<String, dynamic>?;
    final profileUrl = (u?['profile_url'] as String?)?.trim();
    final status = (r['status'] ?? '').toString();

    String chipText;
    Color chipColor;
    if (mode == 'deceased') {
      chipText = 'deceased';
      chipColor = Colors.red;
    } else {
      chipText = status;
      chipColor = status == 'approved'
          ? Colors.green
          : status == 'pending'
          ? Colors.orange
          : Colors.grey;
    }

    final title = (u?['full_name'] ?? 'Member').toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: (profileUrl != null && profileUrl.isNotEmpty)
              ? NetworkImage(profileUrl)
              : null,
          child: (profileUrl == null || profileUrl.isEmpty)
              ? Text(
                  _initialOf(u?['full_name']),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: kPrimaryDark,
                  ),
                )
              : null,
          backgroundColor: kBg,
          radius: 26,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: kPrimaryDark,
            fontFamily: 'Montserrat',
          ),
        ),
        subtitle: Text(
          status == 'approved' ? 'Active Member' : status.capitalize(),
          style: const TextStyle(fontSize: 14, color: kSubtleText),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: chipColor.withOpacity(.15),
            borderRadius: BorderRadius.circular(20),
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
        onTap: mode == 'active'
            ? () {
                final uuid = (u?['id'] as String?)?.trim();
                if (uuid != null && uuid.isNotEmpty) {
                  _showBeneficiariesModal(context, uuid, u?['full_name']);
                }
              }
            : null,
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
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      // BENEFICIARIES
      final futureBeneficiaries = Supabase.instance.client
          .from('beneficiaries')
          .select(
            'id, full_name, relationship, dob, status, birth_certificate, user_id',
          )
          .eq('user_id', uuid)
          .order('full_name', ascending: true);

      // NEW: last contributions (limit 5)
      final futureContribs = _fetchLastContributionsForUser(uuid, max: 5);

      return FutureBuilder<dynamic>(
        future: futureBeneficiaries,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
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

          // USER HEADER future above
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
              final width = constraints.maxWidth;
              final padH = width >= 700 ? 24.0 : 18.0;
              final heightFactor = width >= 1100
                  ? 0.75
                  : width >= 700
                  ? 0.85
                  : 0.92;

              String fmtDate(String iso) =>
                  iso.isEmpty ? '—' : (iso.split('T').first);

              return SafeArea(
                top: false,
                child: FractionallySizedBox(
                  heightFactor: heightFactor,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: padH,
                      right: padH,
                      top: 18,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header card (non-blocking)
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

                                  Widget docItem(String label, bool ok) => Row(
                                    children: [
                                      Icon(
                                        ok
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: ok ? kAccent : kSubtleText,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: kNeutralText,
                                        ),
                                      ),
                                    ],
                                  );

                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE1E4E8),
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x0F000000),
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const CircleAvatar(
                                              radius: 22,
                                              backgroundColor: Color(
                                                0xFF3B82F6,
                                              ),
                                              child: Icon(
                                                Icons.person,
                                                color: Colors.white,
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
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 18,
                                                      color: kNeutralText,
                                                      fontFamily: 'Montserrat',
                                                    ),
                                                  ),
                                                  if (phone.isNotEmpty)
                                                    Text(
                                                      phone,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        color: kSubtleText,
                                                        fontFamily: 'OpenSans',
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Close',
                                              icon: const Icon(Icons.close),
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),

                                        // Last Contribution (now real)
                                        const Text(
                                          'Last Contribution:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            color: kNeutralText,
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
                                                  color: Colors.grey.shade200,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                              );
                                            }
                                            final data = cSnap.data ?? const [];
                                            if (data.isEmpty) {
                                              return const Text(
                                                '—',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  color: kNeutralText,
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
                                              style: const TextStyle(
                                                fontSize: 15,
                                                color: kNeutralText,
                                                fontFamily: 'OpenSans',
                                                fontWeight: FontWeight.w700,
                                              ),
                                            );
                                          },
                                        ),

                                        const SizedBox(height: 18),
                                        const Text(
                                          'Required Documents',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            color: kNeutralText,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        docItem('Birth Certificate', hasBirth),
                                        const SizedBox(height: 10),
                                        docItem(
                                          'Marriage Certificate',
                                          hasMarriage,
                                        ),
                                        const SizedBox(height: 10),
                                        docItem('Death Certificate', hasDeath),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 18),

                              // NEW: Last Contributions section (top 5)
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
                                      const Text(
                                        'Last Contributions',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                          color: kPrimaryDark,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (contribs.isEmpty)
                                        const Text(
                                          'No paid contributions yet.',
                                          style: TextStyle(
                                            color: kSubtleText,
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
                                              leading: const CircleAvatar(
                                                backgroundColor: Color(
                                                  0xFFE3F2FD,
                                                ),
                                                child: Icon(
                                                  Icons.receipt_long,
                                                  color: Color(0xFF1976D2),
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
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: kSubtleText,
                                                    ),
                                                  ),
                                                  if (dod.isNotEmpty)
                                                    Text(
                                                      'Date of Death: $dod',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: kSubtleText,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              trailing: Text(
                                                '₱ $amt',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: kPrimaryDark,
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
                              const Text(
                                'Beneficiaries',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: kPrimaryDark,
                                ),
                              ),
                              const SizedBox(height: 12),

                              if (list.isEmpty)
                                const Text(
                                  'No beneficiaries found.',
                                  style: TextStyle(
                                    color: kSubtleText,
                                    fontSize: 16,
                                  ),
                                ),

                              ...list.map(
                                (b) => Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.person,
                                      color: Colors.blue,
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
                                            child: const Padding(
                                              padding: EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                'View Birth Certificate',
                                                style: TextStyle(
                                                  color: Colors.blue,
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
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}

// NEW: shared helper using the same logic as contributionhistory.dart
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

  Map<int, Map<String, dynamic>> noticeById = {};
  if (noticeIds.isNotEmpty) {
    final notices = List<Map<String, dynamic>>.from(
      await supabase
          .from('death_notices')
          .select('id, name, date_of_death')
          .inFilter('id', noticeIds),
    );
    noticeById = {for (final n in notices) (n['id'] as int): n};
  }

  return payments.map((p) {
    final nid = p['death_notice_id'] as int?;
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

extension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
