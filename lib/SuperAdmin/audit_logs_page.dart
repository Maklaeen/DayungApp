import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/widgets/record_data_table.dart';

class SuperAdminAuditLogsPage extends StatefulWidget {
  const SuperAdminAuditLogsPage({super.key});

  @override
  State<SuperAdminAuditLogsPage> createState() =>
      _SuperAdminAuditLogsPageState();
}

class _SuperAdminAuditLogsPageState extends State<SuperAdminAuditLogsPage> {
  final _searchController = TextEditingController();

  bool _loading = true;
  String _selectedCategory = 'All';
  List<String> _categories = const ['All'];
  List<Map<String, dynamic>> _logs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final query = _searchController.text.trim();
      final path = StringBuffer('/superadmin/audit-logs?limit=180');
      if (query.isNotEmpty) {
        path.write('&q=${Uri.encodeQueryComponent(query)}');
      }
      if (_selectedCategory != 'All') {
        path.write('&category=${Uri.encodeQueryComponent(_selectedCategory)}');
      }

      final result = await superAdminGetJson(path.toString());
      if (!mounted) return;
      setState(() {
        _logs = List<Map<String, dynamic>>.from(result['logs'] ?? const []);
        _categories = [
          'All',
          ...List<String>.from(result['categories'] ?? const []),
        ];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SuperAdminAccessGuard(
      title: 'Audit Logs',
      child: Scaffold(
        backgroundColor: superAdminBackground(context),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      const _AuditHero(),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: kSuperAdminCard,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: kSuperAdminBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // TextField(
                            //   controller: _searchController,
                            //   decoration: InputDecoration(
                            //     hintText:
                            //         'Search actor, target, category, or action text',
                            //     filled: true,
                            //     fillColor: const Color(0xFFF8FAFC),
                            //     prefixIcon: const Icon(Icons.search_rounded),
                            //     suffixIcon: IconButton(
                            //       onPressed: _load,
                            //       icon: const Icon(Icons.arrow_forward_rounded),
                            //     ),
                            //     border: OutlineInputBorder(
                            //       borderRadius: BorderRadius.circular(18),
                            //       borderSide: const BorderSide(
                            //         color: kSuperAdminBorder,
                            //       ),
                            //     ),
                            //     enabledBorder: OutlineInputBorder(
                            //       borderRadius: BorderRadius.circular(18),
                            //       borderSide: const BorderSide(
                            //         color: kSuperAdminBorder,
                            //       ),
                            //     ),
                            //     focusedBorder: OutlineInputBorder(
                            //       borderRadius: BorderRadius.circular(18),
                            //       borderSide: const BorderSide(
                            //         color: kSuperAdminPrimary,
                            //         width: 1.8,
                            //       ),
                            //     ),
                            //   ),
                            //   onSubmitted: (_) => _load(),
                            // ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _categories.map((category) {
                                final selected = _selectedCategory == category;
                                return ChoiceChip(
                                  label: Text(category),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(
                                      () => _selectedCategory = category,
                                    );
                                    _load();
                                  },
                                  selectedColor: kSuperAdminPrimary.withValues(
                                    alpha: 0.14,
                                  ),
                                  side: BorderSide(
                                    color: selected
                                        ? kSuperAdminPrimary
                                        : kSuperAdminBorder,
                                  ),
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? kSuperAdminPrimary
                                        : kSuperAdminText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_error != null)
                        _ErrorState(message: _error!, onRetry: _load)
                      else if (_logs.isEmpty)
                        const _EmptyState()
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: kSuperAdminCard,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: kSuperAdminBorder),
                          ),
                          child: RecordDataTable(
                            minWidth: 900,
                            columns: const [
                              DataColumn(label: Text('Activity')),
                              DataColumn(label: Text('Category')),
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Actor')),
                              DataColumn(label: Text('Details')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: _logs.map(_auditRow).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  DataRow _auditRow(Map<String, dynamic> log) {
    final fields = Map<String, dynamic>.from(log['fields'] ?? const {});
    final fieldEntries = fields.entries
        .where(
          (entry) => entry.value != null && '${entry.value}'.trim().isNotEmpty,
        )
        .map((entry) => '${_humanize(entry.key)}: ${entry.value}')
        .join('\n');
    final actorEmail = log['actor_email']?.toString() ?? '';

    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 180,
            child: Text(
              log['title']?.toString() ?? 'Activity',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: kSuperAdminText,
              ),
            ),
          ),
        ),
        DataCell(Text(log['category']?.toString() ?? 'General')),
        DataCell(Text(_formatDateTime(log['created_at']?.toString()))),
        DataCell(
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  log['actor_name']?.toString() ?? 'Unknown user',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (actorEmail.isNotEmpty)
                  Text(
                    actorEmail,
                    style: const TextStyle(color: kSuperAdminMuted),
                  ),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 240,
            child: Text(fieldEntries, softWrap: true),
          ),
        ),
        DataCell(
          SizedBox(
            width: 260,
            child: Text(
              log['raw_action']?.toString() ?? '',
              softWrap: true,
              style: const TextStyle(color: kSuperAdminMuted, height: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditHero extends StatelessWidget {
  const _AuditHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17326B), Color(0xFF2756A4), Color(0xFFC73A2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeroIcon(),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Audit Logs',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Text(
          //   'Review sensitive actions across accounts, settings, broadcasts, and unit assignments with searchable detail.',
          //   style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          // ),
        ],
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(
        Icons.history_edu_rounded,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSuperAdminCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: kSuperAdminDanger,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kSuperAdminMuted, height: 1.5),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuperAdminPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSuperAdminCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, color: kSuperAdminMuted, size: 44),
          SizedBox(height: 12),
          Text(
            'No audit log entries matched the current filter.',
            style: TextStyle(color: kSuperAdminMuted, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(String? raw) {
  final parsed = DateTime.tryParse(raw ?? '');
  if (parsed == null) return 'Unknown';
  final local = parsed.toLocal();
  final hour = local.hour > 12
      ? local.hour - 12
      : (local.hour == 0 ? 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.month}/${local.day}/${local.year} $hour:$minute $suffix';
}

String _humanize(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
