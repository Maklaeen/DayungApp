import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);

class SuperAdminAuditLogsPage extends StatelessWidget {
  const SuperAdminAuditLogsPage({super.key});

  Future<List<Map<String, dynamic>>> _fetchLogs() async {
    final sb = Supabase.instance.client;
    final res = await sb
        .from('audit_logs')
        .select('action, created_at, user:user_id(full_name, email)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: themeBg,
      appBar: AppBar(
        title: const Text('Audit Logs'),
        backgroundColor: kPrimary,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchLogs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No audit logs found.'));
          }
          final logs = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Audit Logs',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 16),
              ...logs.map(
                (log) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: kCardBg,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 1,
                    child: ListTile(
                      leading: Container(
                        decoration: BoxDecoration(
                          color: kPrimary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.history, color: kPrimary),
                      ),
                      title: Text(
                        '${log['user']?['full_name'] ?? 'Unknown'}: ${log['action']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        log['created_at'] != null
                            ? DateTime.tryParse(log['created_at'].toString()) !=
                                      null
                                  ? '${DateTime.parse(log['created_at']).toLocal()}'
                                  : log['created_at'].toString()
                            : '',
                        style: const TextStyle(fontSize: 13, color: kSubText),
                      ),
                      trailing: log['user']?['email'] != null
                          ? Tooltip(
                              message: log['user']['email'],
                              child: const Icon(
                                Icons.email,
                                color: kPrimary,
                                size: 20,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
