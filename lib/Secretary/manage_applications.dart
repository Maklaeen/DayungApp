import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecretaryApplicationsPage extends StatefulWidget {
  const SecretaryApplicationsPage({super.key});

  @override
  State<SecretaryApplicationsPage> createState() =>
      _SecretaryApplicationsPageState();
}

class _SecretaryApplicationsPageState extends State<SecretaryApplicationsPage> {
  final _supabase = Supabase.instance.client;

  String _filter = 'pending'; // pending | approved | rejected
  bool _loading = true;
  List<Map<String, dynamic>> _apps = [];

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _fetchApplications();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime() {
    // ...existing code...
    _channel?.unsubscribe();
    _channel = _supabase.channel('secretary_apps');

    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all, // INSERT/UPDATE/DELETE
      schema: 'public',
      table: 'applications',
      callback: (payload) {
        _fetchApplications();
      },
    );

    _channel!.subscribe();
  }

  Future<void> _fetchApplications() async {
    setState(() => _loading = true);
    try {
      // Requires a SELECT policy like:
      // Secretaries can read applications where dayung_units.secretary_id = auth.uid()
      final data = await _supabase
          .from('applications')
          .select(
            'id, status, applied_at, dayung_units(name), users(full_name, email, profile_url)',
          )
          .eq('status', _filter)
          .order('applied_at', ascending: false);

      setState(() {
        _apps = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Load failed: ${e.message.isEmpty ? 'RLS or policy issue' : e.message}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error loading applications')),
      );
    }
  }

  Future<void> _approve(int applicationId) async {
    try {
      await _supabase.rpc(
        'approve_application',
        params: {'p_application_id': applicationId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Application approved')));
      _fetchApplications();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Approve failed: ${e.message.isEmpty ? 'Check RPC/Policies' : e.message}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unexpected error')));
    }
  }

  Future<void> _reject(int applicationId) async {
    try {
      await _supabase.rpc(
        'reject_application',
        params: {'p_application_id': applicationId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Application rejected')));
      _fetchApplications();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reject failed: ${e.message.isEmpty ? 'Check RPC/Policies' : e.message}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unexpected error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Applications Inbox')),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Pending'),
                selected: _filter == 'pending',
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _filter = 'pending');
                  _fetchApplications();
                },
              ),
              ChoiceChip(
                label: const Text('Approved'),
                selected: _filter == 'approved',
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _filter = 'approved');
                  _fetchApplications();
                },
              ),
              ChoiceChip(
                label: const Text('Rejected'),
                selected: _filter == 'rejected',
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _filter = 'rejected');
                  _fetchApplications();
                },
              ),
            ],
          ),
          const Divider(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchApplications,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _apps.isEmpty
                  ? const Center(child: Text('No applications found'))
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _apps.length,
                      itemBuilder: (context, i) {
                        final app = _apps[i];
                        final user = app['users'] as Map<String, dynamic>?;
                        final dayung =
                            app['dayung_units'] as Map<String, dynamic>?;
                        final status = (app['status'] ?? '').toString();
                        final appliedAt = DateTime.tryParse(
                          app['applied_at']?.toString() ?? '',
                        );

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                (user?['full_name'] ?? 'M')[0]
                                    .toString()
                                    .toUpperCase(),
                              ),
                            ),
                            title: Text(user?['full_name'] ?? 'Member'),
                            subtitle: Text(
                              '${dayung?['name'] ?? 'Dayung'}'
                              '${appliedAt != null ? '\nApplied: ${appliedAt.toLocal()}' : ''}',
                            ),
                            trailing: _buildActions(status, app['id'] as int),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(String status, int applicationId) {
    if (status == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Reject',
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _reject(applicationId),
          ),
          IconButton(
            tooltip: 'Approve',
            icon: const Icon(Icons.check_circle, color: Colors.green),
            onPressed: () => _approve(applicationId),
          ),
        ],
      );
    }
    if (status == 'approved') {
      return const Icon(Icons.verified, color: Colors.green);
    }
    if (status == 'rejected') {
      return const Icon(Icons.cancel, color: Colors.redAccent);
    }
    return Text(status);
  }
}
