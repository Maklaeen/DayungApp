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
  const SecretaryMembersPage({super.key});

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
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _infoMsg;
  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late TabController _tabController;

  // Raw fetched members (approved + pending) for secretary’s dayungs
  List<Map<String, dynamic>> _rows = [];
  final Map<int, String> _dayungNames = {};
  List<int> _managedDayungIds = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        setState(() {
          _loading = false;
          _infoMsg = 'Please log in.';
          _rows = [];
          _managedDayungIds = [];
          _dayungNames.clear();
        });
        return;
      }

      // 1) Dayungs this secretary manages
      final dayungs = await _sb
          .from('dayung_units')
          .select('id,name')
          .eq('secretary_id', uid);

      final ids = List<Map<String, dynamic>>.from(
        dayungs,
      ).map<int>((e) => e['id'] as int).toList();

      if (ids.isEmpty) {
        setState(() {
          _loading = false;
          _infoMsg = 'You are not assigned to any Dayung.';
          _rows = [];
          _managedDayungIds = [];
          _dayungNames.clear();
        });
        return;
      }

      _dayungNames
        ..clear()
        ..addEntries(
          List<Map<String, dynamic>>.from(dayungs).map(
            (e) => MapEntry(e['id'] as int, (e['name'] ?? 'Dayung') as String),
          ),
        );

      // Fetch users with status approved OR pending in those dayungs
      final apps = await _sb
          .from('applications')
          .select(
            'user_id, status, dayung_unit_id, approved_at, user:users(id, full_name, email, profile_url)',
          )
          .inFilter('dayung_unit_id', ids)
          .inFilter('status', ['approved', 'pending'])
          .order('approved_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(apps);

      // Optional: dedupe multiple applications for same user-dayung by latest approved_at
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

      setState(() {
        _managedDayungIds = ids;
        _rows = byKey.values.toList()
          ..sort((a, b) {
            // Sort: approved first, then by approved_at desc
            final sa = (a['status'] ?? '').toString();
            final sb = (b['status'] ?? '').toString();
            if (sa != sb) {
              return sa == 'approved' ? -1 : 1;
            }
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
      setState(() {
        _loading = false;
        _infoMsg = e.message.isEmpty ? 'Load failed (policies?)' : e.message;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _infoMsg = 'Unexpected error loading members';
      });
    }
  }

  List<Map<String, dynamic>> get _approved =>
      _rows.where((r) => (r['status'] ?? '').toString() == 'approved').toList();

  List<Map<String, dynamic>> get _pending =>
      _rows.where((r) => (r['status'] ?? '').toString() == 'pending').toList();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() => _load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Active (${_approved.length})'),
            Tab(text: 'Pending (${_pending.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_infoMsg != null)
          ? Center(child: Text(_infoMsg!))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search active member...',
                      prefixIcon: const Icon(Icons.search, color: kPrimaryDark),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: kPrimary.withOpacity(.2)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 18, color: kNeutralText),
                    onChanged: (q) {
                      setState(() => _searchQuery = q.trim().toLowerCase());
                    },
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _memberList(_approved, isActive: true),
                      _memberList(_pending, isActive: false),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _initialOf(dynamic name) {
    if (name is String) {
      final t = name.trim();
      if (t.isNotEmpty) return t.substring(0, 1).toUpperCase();
    }
    return 'M';
  }

  Widget _memberList(List<Map<String, dynamic>> list, {bool isActive = false}) {
    List<Map<String, dynamic>> filtered = list;
    if (isActive && _searchQuery.isNotEmpty) {
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
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final r = filtered[i];
          final u = r['user'] as Map<String, dynamic>?;
          final profileUrl = (u?['profile_url'] as String?)?.trim();
          final status = (r['status'] ?? '').toString();
          final dayungId = r['dayung_unit_id'] as int?;
          final dayungName = dayungId != null
              ? (_dayungNames[dayungId] ?? 'Dayung')
              : 'Dayung';

          Color chipColor;
          if (status == 'approved') {
            chipColor = Colors.green;
          } else if (status == 'pending') {
            chipColor = Colors.orange;
          } else {
            chipColor = Colors.grey;
          }

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                (u?['full_name'] as String?)?.trim().isNotEmpty == true
                    ? (u?['full_name'] as String).trim()
                    : 'Member',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: kPrimaryDark,
                  fontFamily: 'Montserrat',
                ),
              ),
              subtitle: Text(
                dayungName,
                style: const TextStyle(
                  fontSize: 15,
                  color: kSubtleText,
                  fontFamily: 'OpenSans',
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: chipColor),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: chipColor,
                  ),
                ),
              ),
              onTap: isActive
                  ? () {
                      // Ensure we pass a valid UUID string
                      final u = r['user'] as Map<String, dynamic>?;
                      final uuid =
                          (u?['id'] as String?)?.trim().isNotEmpty == true
                          ? (u?['id'] as String).trim()
                          : (r['user_id']?.toString().trim());
                      _showBeneficiariesModal(context, uuid, u?['full_name']);
                    }
                  : null,
            ),
          );
        },
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
      // BENEFICIARIES: keep the exact working pattern
      final futureBeneficiaries = Supabase.instance.client
          .from('beneficiaries')
          .select(
            'id, full_name, relationship, dob, status, birth_certificate, user_id',
          )
          .eq('user_id', uuid)
          .order('full_name', ascending: true);

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

          // USER HEADER: load separately so it never blocks beneficiaries
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

          return Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
            ),
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
                      final phone = (u['mobile_number'] ?? '').toString();
                      final hasBirth = (u['birth_certificate_url'] ?? '')
                          .toString()
                          .isNotEmpty;
                      final hasMarriage = (u['marriage_certificate_url'] ?? '')
                          .toString()
                          .isNotEmpty;
                      final hasDeath = (u['death_certificate_url'] ?? '')
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
                          border: Border.all(color: const Color(0xFFE1E4E8)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0F000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Color(0xFF3B82F6),
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
                                          fontWeight: FontWeight.w800,
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
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Eligible',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Last Contribution:',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: kNeutralText,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '—',
                              style: TextStyle(
                                fontSize: 15,
                                color: kNeutralText,
                                fontFamily: 'OpenSans',
                              ),
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
                            docItem('Marriage Certificate', hasMarriage),
                            const SizedBox(height: 10),
                            docItem('Death Certificate', hasDeath),
                          ],
                        ),
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
                      style: TextStyle(color: kSubtleText, fontSize: 16),
                    ),

                  ...list.map(
                    (b) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.person, color: Colors.blue),
                        title: Text(
                          b['full_name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Relationship: ${b['relationship'] ?? ''}'),
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
                                  padding: EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    'View Birth Certificate',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      decoration: TextDecoration.underline,
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
          );
        },
      );
    },
  );
} 