import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NamesOnlyMembersPage extends StatefulWidget {
  final int dayungUnitId;
  final String title;
  final List<String> statuses;

  const NamesOnlyMembersPage({
    super.key,
    required this.dayungUnitId,
    required this.title,
    required this.statuses,
  });

  @override
  State<NamesOnlyMembersPage> createState() => _NamesOnlyMembersPageState();
}

class _NamesOnlyMembersPageState extends State<NamesOnlyMembersPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  String _search = '';
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final baseQuery = _sb.from('applications').select(
            'user_id, status, user:users(id, full_name, profile_url)',
          )
        .eq('dayung_unit_id', widget.dayungUnitId);

      final query = (widget.statuses.length == 1 && widget.statuses.first == 'removed')
          ? baseQuery.isFilter('isRemovedInDayung', true)
          : baseQuery.inFilter('status', widget.statuses);

      final rows = await query.order('user_id', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows);
      final members = <Map<String, dynamic>>[];
      for (final row in list) {
        final user = row['user'] as Map<String, dynamic>?;
        final fullName = (user?['full_name'] ?? '').toString().trim();
        if (fullName.isEmpty) continue;
        members.add(
          {
            'user_id': (row['user_id'] ?? '').toString(),
            'full_name': fullName,
            'status': (row['status'] ?? '').toString(),
          },
        );
      }

      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load members: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredMembers {
    if (_search.trim().isEmpty) return _members;
    final query = _search.trim().toLowerCase();
    return _members.where((member) {
      final name = (member['full_name'] ?? '').toString().toLowerCase();
      final id = (member['user_id'] ?? '').toString().toLowerCase();
      return name.contains(query) || id.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search members',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  setState(() {
                    _search = value;
                  });
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        )
                      : _filteredMembers.isEmpty
                          ? const Center(
                              child: Text(
                                'No members found.',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _filteredMembers.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: Color(0xFFE5E7EB),
                              ),
                              itemBuilder: (context, index) {
                                final member = _filteredMembers[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        const Color(0xFF0D47A1).withOpacity(0.12),
                                    child: const Icon(
                                      Icons.person,
                                      color: Color(0xFF0D47A1),
                                    ),
                                  ),
                                  title: Text(
                                    member['full_name'] ?? 'Member',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'ID: ${member['user_id']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
