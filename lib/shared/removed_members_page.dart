import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPrimary = Color(0xFF0D47A1);
const Color _kPrimaryDark = Color(0xFF083366);
const Color _kNeutralText = Color(0xFF1F2937);
const Color _kSubText = Color(0xFF4B5563);
const Color _kDanger = Color(0xFFC62828);
const Color _kSuccess = Color(0xFF10B981);

class RemovedMembersPage extends StatefulWidget {
  final int dayungUnitId;
  const RemovedMembersPage({super.key, required this.dayungUnitId});

  @override
  State<RemovedMembersPage> createState() => _RemovedMembersPageState();
}

class _RemovedMembersPageState extends State<RemovedMembersPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _members = [];
  String _search = '';
  final Set<String> _removingUserIds = <String>{};

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
          .from('applications')
          .select(
            'id, user_id, approved_at, updated_at, status, '
            'user:users(id, full_name, profile_url, email)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved')
          .order('approved_at', ascending: false);

      if (mounted) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(rows);
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

  Future<void> _confirmRemove(Map<String, dynamic> member) async {
    final u = member['user'] as Map?;
    final memberName = (u?['full_name'] ?? 'this member').toString();

    final confirmed = await showDialog<bool>(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeMember(member);
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final applicationId = member['id'];
    final userId = (member['user_id'] ?? '').toString();
    if (applicationId == null || userId.isEmpty || _removingUserIds.contains(userId)) {
      return;
    }

    setState(() => _removingUserIds.add(userId));

    try {
      await _sb
          .from('applications')
          .update({
            'status': 'removed',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', applicationId)
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('user_id', userId)
          .eq('status', 'approved');

      final stillApproved = await _sb
          .from('applications')
          .select('id')
          .eq('id', applicationId)
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('user_id', userId)
          .eq('status', 'approved')
          .maybeSingle();

      if (stillApproved != null) {
        throw StateError('Application status was not updated.');
      }

      if (!mounted) return;

      setState(() {
        _members.removeWhere((row) => row['id'] == applicationId);
        _removingUserIds.remove(userId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member removed.')),
      );
      _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _removingUserIds.remove(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove member: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _removingUserIds.remove(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove member: $e')),
      );
    }
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
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Approved Members',
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
                  hintText: 'Search approved member or user ID...',
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
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) => setState(() => _search = v.trim()),
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
                              color: _kDanger.withValues(alpha: 0.8),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Failed to load approved members',
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
                            'No approved members found',
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
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _memberCard(_filtered[i]),
                      ),
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
    final isRemoving = _removingUserIds.contains(userId);
    final approvedAt =
        (r['approved_at'] ?? r['updated_at'] ?? '').toString();
    String dateStr = '';
    if (approvedAt.isNotEmpty) {
      final dt = DateTime.tryParse(approvedAt);
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
        trailing: TextButton.icon(
          onPressed: isRemoving ? null : () => _confirmRemove(r),
          style: TextButton.styleFrom(
            foregroundColor: _kDanger,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(0, 32),
          ),
          icon: isRemoving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_remove_rounded, size: 16),
          label: Text(
            isRemoving ? 'Removing' : 'Remove',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ),
    );
  }
}
