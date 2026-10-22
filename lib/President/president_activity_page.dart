import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresidentActivityPage extends StatefulWidget {
  const PresidentActivityPage({super.key});

  @override
  State<PresidentActivityPage> createState() => _PresidentActivityPageState();
}

class _PresidentActivityPageState extends State<PresidentActivityPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Please sign in again to view your activity.');
      }

      final response = await _supabase
          .from('audit_logs')
          .select('id, action, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() {
        _entries = List<Map<String, dynamic>>.from(response);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0891B2);

    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: 'Refresh activity',
            onPressed: _loading ? null : _loadActivity,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ActivityMessage(
                icon: Icons.error_outline_rounded,
                title: 'Could not load activity',
                message: _error!,
                actionLabel: 'Try again',
                onAction: _loadActivity,
              )
            : _entries.isEmpty
            ? const _ActivityMessage(
                icon: Icons.history_rounded,
                title: 'No activity yet',
                message: 'Your recorded actions will appear here.',
              )
            : RefreshIndicator(
                onRefresh: _loadActivity,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: dayungSectionCardDecoration(context),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: dayungAccentCardDecoration(
                              context,
                              accent: accent,
                              radius: 14,
                            ),
                            child: const Icon(
                              Icons.history_rounded,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your activity history',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: dayungTextColor(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Showing your most recent recorded actions.',
                                  style: TextStyle(
                                    color: dayungSubtextColor(context),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final entry in _entries) ...[
                      _ActivityEntryCard(entry: entry),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _ActivityEntryCard extends StatelessWidget {
  const _ActivityEntryCard({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0891B2);
    final action = _parseAction(entry['action']?.toString());
    final createdAt = DateTime.tryParse('${entry['created_at'] ?? ''}');
    final dateLabel = createdAt == null
        ? 'Date unavailable'
        : DateFormat('MMM d, yyyy • h:mm a').format(createdAt.toLocal());
    final details = action.fields.entries
        .where((field) => field.value.trim().isNotEmpty)
        .map((field) => '${_humanize(field.key)}: ${field.value}')
        .join('  •  ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: dayungSectionCardDecoration(context, radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: dayungAccentCardDecoration(
              context,
              accent: accent,
              radius: 13,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: dayungTextColor(context),
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    details,
                    style: TextStyle(
                      color: dayungSubtextColor(context),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: dayungSubtextColor(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityMessage extends StatelessWidget {
  const _ActivityMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: dayungSectionCardDecoration(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: dayungSubtextColor(context)),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: dayungTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: dayungSubtextColor(context),
                  height: 1.5,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

({String title, Map<String, String> fields}) _parseAction(String? rawAction) {
  final parts = (rawAction ?? '')
      .split('|')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  final event = parts.isEmpty ? 'Activity' : _humanize(parts.first);
  final fields = <String, String>{};

  for (final part in parts.skip(1)) {
    final separator = part.indexOf('=');
    if (separator <= 0) continue;

    final key = part.substring(0, separator).trim();
    final rawValue = part.substring(separator + 1).trim();
    String value;
    try {
      value = Uri.decodeComponent(rawValue);
    } on FormatException {
      value = rawValue;
    }
    fields[key] = value;
  }

  return (title: event, fields: fields);
}

String _humanize(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
