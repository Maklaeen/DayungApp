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
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      appBar: AppBar(
        title: const Text('Activity history'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _loadActivity,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1100;
            final isCompact = constraints.maxWidth < 600;
            final horizontalPadding = isCompact ? 16.0 : 32.0;

            return RefreshIndicator(
              onRefresh: _loadActivity,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  20,
                  horizontalPadding,
                  36,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _ActivityHero(),
                          const SizedBox(height: 24),
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Expanded(
                                  child: _ActivityLogSection(
                                    number: '01',
                                    title: 'Announcement log',
                                    description:
                                        'A clear record of announcements shared with members.',
                                    icon: Icons.campaign_outlined,
                                    columns: [
                                      'Title',
                                      'Category',
                                      'Description',
                                      'Posted by',
                                      'Date and time',
                                    ],
                                    compact: false,
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: _ActivityLogSection(
                                    number: '02',
                                    title: 'User preferences',
                                    description:
                                        'A record of changes made to unit rules and preferences.',
                                    icon: Icons.tune_rounded,
                                    columns: [
                                      'Rule created by',
                                      'Last updated by',
                                      'Last updated at',
                                    ],
                                    compact: false,
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _ActivityLogSection(
                              number: '01',
                              title: 'Announcement log',
                              description:
                                  'A clear record of announcements shared with members.',
                              icon: Icons.campaign_outlined,
                              columns: const [
                                'Title',
                                'Category',
                                'Description',
                                'Posted by',
                                'Date and time',
                              ],
                              compact: isCompact,
                            ),
                            const SizedBox(height: 16),
                            _ActivityLogSection(
                              number: '02',
                              title: 'User preferences',
                              description:
                                  'A record of changes made to unit rules and preferences.',
                              icon: Icons.tune_rounded,
                              columns: const [
                                'Rule created by',
                                'Last updated by',
                                'Last updated at',
                              ],
                              compact: isCompact,
                            ),
                          ],
                          const SizedBox(height: 28),
                          _RecentActivitySection(
                            loading: _loading,
                            error: _error,
                            entries: _entries,
                            onRetry: _loadActivity,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActivityHero extends StatelessWidget {
  const _ActivityHero();

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF075985);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dayungAccentSurface(context, accent, lightAlpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'President activity',
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: dayungTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Review announcement and preference records, then check your recent actions below.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: dayungSubtextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityLogSection extends StatelessWidget {
  const _ActivityLogSection({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    required this.columns,
    required this.compact,
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;
  final List<String> columns;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF075985);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dayungSectionCardDecoration(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: dayungAccentCardDecoration(
                  context,
                  accent: accent,
                  radius: 16,
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: dayungTextColor(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: dayungAccentSurface(context, accent),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  number,
                  style: const TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: dayungSubtextColor(context),
            ),
          ),
          const SizedBox(height: 20),
          if (compact) ...[
            Text(
              'DETAILS SHOWN',
              style: TextStyle(
                color: dayungSubtextColor(context),
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < columns.length; index++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == columns.length - 1 ? 0 : 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: dayungSoftSurface(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: dayungTextColor(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        columns[index],
                        style: TextStyle(
                          color: dayungTextColor(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            Text(
              'LOG COLUMNS',
              style: TextStyle(
                color: dayungSubtextColor(context),
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 64,
                dataRowMinHeight: 56,
                dataRowMaxHeight: 80,
                columnSpacing: 24,
                horizontalMargin: 18,
                dividerThickness: 1,
                headingRowColor: WidgetStatePropertyAll(
                  dayungSoftSurface(context),
                ),
                headingTextStyle: TextStyle(
                  color: dayungTextColor(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFamily: 'Montserrat',
                ),
                border: TableBorder(
                  horizontalInside: BorderSide(color: dayungBorder(context)),
                ),
                columns: [
                  for (final column in columns)
                    DataColumn(
                      label: Text(
                        column,
                        style: TextStyle(
                          color: dayungTextColor(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
                rows: const [],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: dayungSoftSurface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: dayungBorder(context)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 30,
                  color: dayungSubtextColor(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'No records yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: dayungTextColor(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'New activity will appear here when available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: dayungSubtextColor(context),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({
    required this.loading,
    required this.error,
    required this.entries,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> entries;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF075985);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recent activity',
                  style: TextStyle(
                    color: dayungTextColor(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 21,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (loading)
          const _ActivityStatusCard(
            icon: Icons.hourglass_top_rounded,
            message: 'Loading recent activity...',
          )
        else if (error != null)
          _ActivityStatusCard(
            icon: Icons.error_outline_rounded,
            message: 'Could not load recent activity: $error',
            actionLabel: 'Try again',
            onAction: onRetry,
          )
        else if (entries.isEmpty)
          const _ActivityStatusCard(
            icon: Icons.history_rounded,
            message: 'No recent activity yet.',
          )
        else
          for (final entry in entries) ...[
            _ActivityEntryCard(entry: entry),
            const SizedBox(height: 12),
          ],
      ],
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

class _ActivityStatusCard extends StatelessWidget {
  const _ActivityStatusCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: dayungSectionCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: dayungSubtextColor(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: dayungSubtextColor(context),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
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
