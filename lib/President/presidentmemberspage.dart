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

class PresidentMembersPage extends StatefulWidget {
  final List<int> dayungUnitIds;
  const PresidentMembersPage({super.key, required this.dayungUnitIds});

  @override
  State<PresidentMembersPage> createState() => _PresidentMembersPageState();
}

class _PresidentMembersPageState extends State<PresidentMembersPage>
    with SingleTickerProviderStateMixin {
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

      final dayungIds = widget.dayungUnitIds;
      if (dayungIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _infoMsg = 'No units selected.';
          _rows = [];
          _dayungNames.clear();
        });
        return;
      }

      final dayungs = await _sb
          .from('dayung_units')
          .select('id,name')
          .inFilter('id', dayungIds);

      for (final d in List<Map<String, dynamic>>.from(dayungs)) {
        _dayungNames[d['id'] as int] = (d['name'] ?? 'Dayung') as String;
      }

      final apps = await _sb
          .from('applications')
          .select(
            'id, user_id, status, name, dayung_unit_id, approved_at, applied_at, '
            'user:users(id, full_name, email, profile_url)',
          )
          .inFilter('dayung_unit_id', dayungIds)
          .inFilter('status', ['approved', 'pending'])
          .order('approved_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(apps);
      final userIds = list
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final deathRows = userIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _sb
                  .from('death_notices')
                  .select('user_id, date_of_death, deceased_type')
                  .inFilter('user_id', userIds)
                  .or('deceased_type.is.null,deceased_type.eq.member'),
            );

      final deathInfo = <String, Map<String, dynamic>>{};
      for (final row in deathRows) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;
        final previous = deathInfo[userId];
        final currentDate = DateTime.tryParse('${row['date_of_death'] ?? ''}');
        final previousDate = previous == null
            ? null
            : DateTime.tryParse('${previous['date_of_death'] ?? ''}');
        if (previous == null ||
            (currentDate != null &&
                (previousDate == null || currentDate.isAfter(previousDate)))) {
          deathInfo[userId] = row;
        }
      }

      final byKey = <String, Map<String, dynamic>>{};
      for (final r in list) {
        final u = r['user'] as Map<String, dynamic>?;
        final userId = (u?['id'] ?? r['user_id']).toString();
        final dayungId = r['dayung_unit_id'] as int;
        final key = '$userId-$dayungId';
        final memberName = ((u?['full_name'] ?? r['name']) ?? '')
            .toString()
            .trim();
        final normalized = {
          ...r,
          'member_name': memberName,
          'profile_url': (u?['profile_url'] ?? '').toString().trim(),
          'is_deceased': deathInfo.containsKey(userId),
          'date_of_death': deathInfo[userId]?['date_of_death'],
        };
        if (!byKey.containsKey(key)) {
          byKey[key] = normalized;
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
            byKey[key] = normalized;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _infoMsg = 'Unexpected error loading members';
      });
    }
  }

  List<Map<String, dynamic>> get _approved => _rows.where((r) {
    final status = (r['status'] ?? '').toString();
    final deceased = r['is_deceased'] == true;
    return status == 'approved' && !deceased;
  }).toList();

  List<Map<String, dynamic>> get _pending => _rows.where((r) {
    final status = (r['status'] ?? '').toString();
    final deceased = r['is_deceased'] == true;
    return status == 'pending' && !deceased;
  }).toList();

  List<Map<String, dynamic>> get _deceased => _rows.where((r) {
    return r['is_deceased'] == true;
  }).toList();

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
                String fmtDate(String iso) =>
                    iso.isEmpty ? '—' : (iso.split('T').first);

                return Container(
                  height: MediaQuery.of(context).size.height * 0.8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
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
                          color: Colors.grey.shade400,
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
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFE0E7FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white54,
                                    blurRadius: 20,
                                    offset: Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: Color(0xFF1E40AF),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                color: Color(0xFF1E40AF),
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
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1E40AF),
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Member Details',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF6B7280),
                                      fontFamily: 'OpenSans',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Color(0xFF6B7280),
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
                                            : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: ok
                                              ? const Color(
                                                  0xFF10B981,
                                                ).withValues(alpha: 0.3)
                                              : Colors.grey.shade300,
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
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF6B7280),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: ok
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFF374151),
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
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
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
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF1E40AF,
                                                  ).withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Icon(
                                                  Icons.person_rounded,
                                                  color: Color(0xFF1E40AF),
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
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 16,
                                                        color: Color(
                                                          0xFF374151,
                                                        ),
                                                        fontFamily:
                                                            'Montserrat',
                                                      ),
                                                    ),
                                                    if (phone.isNotEmpty)
                                                      Text(
                                                        phone,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                            0xFF6B7280,
                                                          ),
                                                          fontFamily:
                                                              'OpenSans',
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          const Text(
                                            'Last Contribution:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Color(0xFF374151),
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
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                );
                                              }
                                              final data =
                                                  cSnap.data ?? const [];
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
                                          const SizedBox(height: 16),
                                          const Text(
                                            'Required Documents',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Color(0xFF374151),
                                              fontFamily: 'Montserrat',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          docItem(
                                            'Birth Certificate',
                                            hasBirth,
                                          ),
                                          const SizedBox(height: 8),
                                          docItem(
                                            'Marriage Certificate',
                                            hasMarriage,
                                          ),
                                          const SizedBox(height: 8),
                                          docItem(
                                            'Death Certificate',
                                            hasDeath,
                                          ),
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
                                        const Text(
                                          'Last Contributions',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
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
                                            final dod =
                                                (c['date_of_death'] ?? '')
                                                    .toString();
                                            return Card(
                                              margin:
                                                  const EdgeInsets.symmetric(
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                    fontSize: 12,
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
                                                Uri.parse(
                                                  b['birth_certificate'],
                                                ),
                                              ),
                                              child: const Padding(
                                                padding: EdgeInsets.only(
                                                  top: 4.0,
                                                ),
                                                child: Text(
                                                  'View Birth Certificate',
                                                  style: TextStyle(
                                                    color: Colors.blue,
                                                    decoration: TextDecoration
                                                        .underline,
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
            'id, amount, status, created_at, dayung_unit_id, claim_id, userdeceased',
          )
          .eq('user_id', uid)
          .eq('status', 'paid')
          .order('created_at', ascending: false)
          .limit(max),
    );

    if (payments.isEmpty) return const [];

    final claimIds = payments
        .map((p) => (p['claim_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    Map<String, Map<String, dynamic>> claimById = {};
    if (claimIds.isNotEmpty) {
      final claims = List<Map<String, dynamic>>.from(
        await supabase
            .from('claims')
            .select('id, title, user_id, beneficiary_id, date_of_death')
            .inFilter('id', claimIds),
      );
      claimById = {for (final c in claims) c['id'].toString(): c};
    }

    return payments.map((p) {
      final claimId = (p['claim_id'] ?? '').toString();
      final claim = claimId.isNotEmpty ? claimById[claimId] : null;
      final amount = (p['amount'] is num)
          ? (p['amount'] as num).toDouble()
          : double.tryParse('${p['amount']}') ?? 0.0;
      final deceasedId = (p['userdeceased'] ?? '').toString();
      return {
        'date': (p['created_at'] ?? '').toString(),
        'amount': amount,
        'notice_name': (claim?['title'] ?? '').toString().trim().isNotEmpty
            ? (claim?['title'] ?? '').toString()
            : (deceasedId.isNotEmpty ? deceasedId : 'Contribution'),
        'date_of_death': claim?['date_of_death'],
      };
    }).toList();
  }

  Future<void> _refresh() => _load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(8, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kPrimaryDark,
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
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.people_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Members',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search member...',
                  hintStyle: const TextStyle(
                    color: kSubtleText,
                    fontFamily: 'OpenSans',
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: kPrimary,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kPrimary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: kNeutralText,
                  fontFamily: 'OpenSans',
                  fontWeight: FontWeight.w600,
                ),
                onChanged: (q) =>
                    setState(() => _searchQuery = q.trim().toLowerCase()),
              ),
            ),

            // Tabs
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: const Color(0xFFF1F5F9),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_list_rounded,
                    color: kSubtleText,
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
                              label: 'Pending',
                              icon: Icons.schedule_rounded,
                              selected: _tabController.index == 1,
                              onTap: () => _tabController.animateTo(1),
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
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade300,
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
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: kPrimary,
                              strokeWidth: 3,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Loading members...',
                              style: TextStyle(
                                color: kSubtleText,
                                fontSize: 14,
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : (_infoMsg != null)
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade300,
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
                          style: const TextStyle(
                            fontSize: 16,
                            color: kNeutralText,
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1000,
                                  ),
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
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberList(
    List<Map<String, dynamic>> list, {
    String mode = 'active',
    required BoxConstraints constraints,
  }) {
    List<Map<String, dynamic>> filtered = list;
    if (_searchQuery.isNotEmpty) {
      filtered = list.where((r) {
        final name = _memberNameOf(r).toLowerCase();
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
            Icon(Icons.people_outline, size: 48, color: kSubtleText),
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
    final profileUrl = (r['profile_url'] as String?)?.trim();
    final dayungId = r['dayung_unit_id'] as int?;
    final dayungName = dayungId != null
        ? (_dayungNames[dayungId] ?? 'Dayung')
        : 'Dayung';

    String chipText;
    Color chipColor;
    if (mode == 'deceased') {
      chipText = 'deceased';
      chipColor = kDanger;
    } else {
      final status = (r['status'] ?? '').toString();
      chipText = status;
      chipColor = status == 'approved'
          ? kAccent
          : status == 'pending'
          ? kWarn
          : Colors.grey;
    }

    final title = _memberNameOf(r);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundImage: (profileUrl != null && profileUrl.isNotEmpty)
              ? NetworkImage(profileUrl)
              : null,
          backgroundColor: kBg,
          radius: 16,
          child: (profileUrl == null || profileUrl.isEmpty)
              ? Text(
                  _initialOf(title),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: kPrimaryDark,
                  ),
                )
              : null,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: kPrimaryDark,
            fontFamily: 'Montserrat',
          ),
        ),
        subtitle: Text(
          dayungName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            color: kSubtleText,
            fontFamily: 'OpenSans',
          ),
        ),
        trailing: Container(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: chipColor),
                ),
                child: Text(
                  chipText,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: chipColor,
                  ),
                ),
              ),
              if (mode == 'active' && dayungId != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Remove member',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.person_remove_rounded,
                    size: 18,
                    color: kDanger,
                  ),
                  onPressed: () => _showRemoveMemberDialog(
                    applicationId: (r['id'] as num).toInt(),
                    dayungUnitId: dayungId,
                    userId: (u?['id'] as String?)?.trim().isNotEmpty == true
                        ? (u?['id'] as String).trim()
                        : (r['user_id']?.toString().trim() ?? ''),
                    memberName: title,
                  ),
                ),
              ],
            ],
          ),
        ),
        // President can click any member (active, pending, deceased)
        onTap: () {
          final uuid = (u?['id'] as String?)?.trim().isNotEmpty == true
              ? (u?['id'] as String).trim()
              : (r['user_id']?.toString().trim());
          _showBeneficiariesModal(context, uuid, title);
        },
      ),
    );
  }

  void _showRemoveMemberDialog({
    required int applicationId,
    required int dayungUnitId,
    required String userId,
    required String memberName,
  }) {
    if (userId.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove Member',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
        content: Text(
          'Move $memberName to removed members?',
          style: const TextStyle(fontFamily: 'OpenSans'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _removeMember(
                applicationId: applicationId,
                dayungUnitId: dayungUnitId,
                userId: userId,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kDanger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Remove',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeMember({
    required int applicationId,
    required int dayungUnitId,
    required String userId,
  }) async {
    try {
      await _sb.rpc(
        'remove_member_application',
        params: {'p_application_id': applicationId},
      );

      final stillApproved = await _sb
          .from('applications')
          .select('id')
          .eq('id', applicationId)
          .eq('dayung_unit_id', dayungUnitId)
          .eq('user_id', userId)
          .eq('status', 'approved')
          .maybeSingle();

      if (stillApproved != null) {
        throw StateError('Application status was not updated.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Member removed.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove member: $e')));
    }
  }

  String _memberNameOf(Map<String, dynamic> row) {
    final name = (row['member_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final fallback = (row['name'] ?? '').toString().trim();
    if (fallback.isNotEmpty) return fallback;
    return 'Member';
  }

  String _initialOf(dynamic name) {
    if (name is String) {
      final t = name.trim();
      if (t.isNotEmpty) return t.substring(0, 1).toUpperCase();
    }
    return 'M';
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: selected ? kPrimary : kSubtleText),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? kPrimary : kSubtleText,
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
                color: kPrimary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
