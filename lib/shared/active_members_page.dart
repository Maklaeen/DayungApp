import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Clipboard copy removed; no services import needed

const Color _kPrimary = Color(0xFF0D47A1);
const Color _kPrimaryDark = Color(0xFF083366);
const Color _kNeutralText = Color(0xFF1F2937);
const Color _kSubText = Color(0xFF4B5563);
const Color _kSuccess = Color(0xFF10B981);

class ActiveMembersPage extends StatefulWidget {
  final int dayungUnitId;
  const ActiveMembersPage({super.key, required this.dayungUnitId});

  @override
  State<ActiveMembersPage> createState() => _ActiveMembersPageState();
}

class _ActiveMembersPageState extends State<ActiveMembersPage> {
  static const int _pageSize = 10;

  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _members = [];
  String _search = '';
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _sb
          .from('payments')
          .select(
            'id, user_id, amount, paid_at, created_at, status, type, '
            'user:users!payments_user_id_fkey(id, full_name, profile_url, email)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('type', 'membership_payment')
          .eq('status', 'paid')
          .order('paid_at', ascending: false)
          .order('created_at', ascending: false);

      final paymentRows = List<Map<String, dynamic>>.from(rows);
      final uniqueMembers = <String, Map<String, dynamic>>{};

      for (final row in paymentRows) {
        final userId = (row['user_id'] ?? '').toString().trim();
        if (userId.isEmpty) continue;

        final existing = uniqueMembers[userId];
        if (existing == null) {
          uniqueMembers[userId] = row;
          continue;
        }

        final currentPaidAt = DateTime.tryParse(
          (row['paid_at'] ?? row['created_at'] ?? '').toString(),
        );
        final existingPaidAt = DateTime.tryParse(
          (existing['paid_at'] ?? existing['created_at'] ?? '').toString(),
        );
        if (currentPaidAt != null &&
            (existingPaidAt == null || currentPaidAt.isAfter(existingPaidAt))) {
          uniqueMembers[userId] = row;
        }
      }

      final unitRow = await _sb
          .from('dayung_units')
          .select('president_id, secretary_id, treasurer_id')
          .eq('id', widget.dayungUnitId)
          .maybeSingle();

      if (unitRow != null) {
        final officerIds = <String>{};
        for (final key in ['president_id', 'secretary_id', 'treasurer_id']) {
          final value = unitRow[key];
          if (value != null) officerIds.add(value.toString().trim());
        }

        final missingOfficerIds = officerIds
            .where((id) => id.isNotEmpty && !uniqueMembers.containsKey(id))
            .toList();

        if (missingOfficerIds.isNotEmpty) {
          for (final id in missingOfficerIds) {
            final userRow = await _sb
                .from('users')
                .select('id, full_name, profile_url, email')
                .eq('id', id)
                .maybeSingle();

            if (userRow == null) continue;
            final userId = (userRow['id'] ?? '').toString().trim();
            if (userId.isEmpty) continue;
            uniqueMembers[userId] = {
              'user_id': userId,
              'paid_at': null,
              'created_at': null,
              'status': 'officer',
              'type': 'membership_payment',
              'user': userRow,
            };
          }
        }
      }

      if (mounted) {
        final membersList = uniqueMembers.values.toList();
        membersList.sort((a, b) {
          final aName = ((a['user'] as Map?)?['full_name'] ?? '')
              .toString()
              .toLowerCase();
          final bName = ((b['user'] as Map?)?['full_name'] ?? '')
              .toString()
              .toLowerCase();
          return aName.compareTo(bName);
        });

        setState(() {
          _members = membersList;
          _pageIndex = 0;
          _loading = false;
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _members;
    final q = _search.toLowerCase();
    return _members.where((r) {
      final u = r['user'] as Map?;
      final name = (u?['full_name'] ?? '').toString().toLowerCase();
      final userId = (r['user_id'] ?? '').toString().toLowerCase();
      return name.contains(q) || userId.contains(q);
    }).toList();
  }

  int get _pageCount {
    if (_filtered.isEmpty) return 1;
    return (_filtered.length / _pageSize).ceil();
  }

  List<Map<String, dynamic>> get _pagedFiltered {
    final start = _pageIndex * _pageSize;
    if (start >= _filtered.length) return const <Map<String, dynamic>>[];
    final end = (start + _pageSize).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  void _goToPreviousPage() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex -= 1);
  }

  void _goToNextPage() {
    if (_pageIndex >= _pageCount - 1) return;
    setState(() => _pageIndex += 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 36, 20, 28),
              decoration: const BoxDecoration(
                color: _kPrimaryDark,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
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
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Active Members',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_members.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search member',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: _kPrimary,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) => setState(() {
                  _search = v.trim();
                  _pageIndex = 0;
                }),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPrimary),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: _kPrimary.withValues(alpha: 0.8),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Failed to load active members',
                              style: TextStyle(
                                color: _kNeutralText,
                                fontSize: 16,
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: _kSubText,
                                fontSize: 12,
                                fontFamily: 'OpenSans',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _load,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kPrimary,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 56,
                            color: _kSubText.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No active members found',
                            style: TextStyle(
                              color: _kSubText,
                              fontSize: 16,
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _pagedFiltered.length,
                              itemBuilder: (_, i) =>
                                  _memberCard(_pagedFiltered[i]),
                            ),
                          ),
                        ),
                        if (_filtered.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  onPressed: _pageIndex == 0
                                      ? null
                                      : _goToPreviousPage,
                                  icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                  ),
                                  color: _kPrimary,
                                ),
                                Text(
                                  'Page ${_pageIndex + 1} of $_pageCount',
                                  style: const TextStyle(
                                    color: _kNeutralText,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                IconButton(
                                  onPressed: _pageIndex >= _pageCount - 1
                                      ? null
                                      : _goToNextPage,
                                  icon: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                  ),
                                  color: _kPrimary,
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
    );
  }

  Widget _memberCard(Map<String, dynamic> r) {
    final u = r['user'] as Map?;
    final name = (u?['full_name'] ?? 'Member').toString();
    final profileUrl = (u?['profile_url'] ?? '').toString();
    final userId = (r['user_id'] ?? '').toString();
    final paidAt = (r['paid_at'] ?? r['created_at'] ?? '').toString();
    String dateStr = '';
    if (paidAt.isNotEmpty) {
      final dt = DateTime.tryParse(paidAt);
      if (dt != null) dateStr = '${dt.month}/${dt.day}/${dt.year}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 22,
          backgroundImage: profileUrl.isNotEmpty
              ? NetworkImage(profileUrl)
              : null,
          backgroundColor: _kSuccess.withValues(alpha: 0.1),
          child: profileUrl.isEmpty
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'M',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kSuccess,
                  ),
                )
              : null,
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _kNeutralText,
            fontFamily: 'Montserrat',
          ),
        ),
        subtitle: dateStr.isNotEmpty
            ? Text(
                'Approved: $dateStr',
                style: const TextStyle(
                  fontSize: 12,
                  color: _kSubText,
                  fontFamily: 'OpenSans',
                ),
              )
            : null,
        // trailing action removed (copy UID)
      ),
    );
  }
}
