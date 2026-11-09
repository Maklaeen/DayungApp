import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresidentActivityPage extends StatefulWidget {
  const PresidentActivityPage({super.key});

  @override
  State<PresidentActivityPage> createState() => _PresidentActivityPageState();
}

class _PresidentActivityPageState extends State<PresidentActivityPage> {
  static const int _announcementPageSize = 10;

  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _rules = [];
  int _announcementPage = 0;
  int _rulesPage = 0;
  bool _announcementsHaveMore = false;
  bool _rulesHaveMore = false;
  bool _loading = true;
  bool _announcementsLoading = true;
  bool _rulesLoading = true;
  String? _error;
  String? _announcementsError;
  String? _rulesError;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadActivity(), _loadAnnouncements(), _loadRules()]);
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

  Future<void> _loadAnnouncements({int page = 0}) async {
    setState(() {
      _announcementsLoading = true;
      _announcementsError = null;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Please sign in again to view announcements.');
      }

      final unitResponse = await _supabase
          .from('dayung_units')
          .select('id')
          .eq('president_id', userId)
          .order('id');
      final unitIds = List<Map<String, dynamic>>.from(
        unitResponse,
      ).map((unit) => int.tryParse('${unit['id']}')).whereType<int>().toList();

      if (unitIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _announcements = [];
          _announcementPage = page;
          _announcementsHaveMore = false;
        });
        return;
      }

      final start = page * _announcementPageSize;
      final response = await _supabase
          .from('announcements')
          .select('title, category, body, created_by, created_at')
          .inFilter('dayung_unit_id', unitIds)
          .order('created_at', ascending: false)
          .range(start, start + _announcementPageSize);
      final rows = List<Map<String, dynamic>>.from(response);
      final hasMore = rows.length > _announcementPageSize;
      final announcements = rows.take(_announcementPageSize).toList();
      final posterIds = announcements
          .map((announcement) => announcement['created_by'])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final posterNames = <String, String>{};
      if (posterIds.isNotEmpty) {
        final posters = await _supabase
            .from('users')
            .select('id, full_name')
            .inFilter('id', posterIds);
        for (final poster in List<Map<String, dynamic>>.from(posters)) {
          final id = poster['id']?.toString();
          final name = poster['full_name']?.toString().trim();
          if (id != null && name != null && name.isNotEmpty) {
            posterNames[id] = name;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _announcementPage = page;
        _announcementsHaveMore = hasMore;
        _announcements = announcements
            .map(
              (announcement) => {
                ...announcement,
                'posted_by':
                    posterNames[announcement['created_by']?.toString()] ??
                    'Name unavailable',
              },
            )
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _announcementsError = error.toString());
    } finally {
      if (mounted) setState(() => _announcementsLoading = false);
    }
  }

  Future<void> _loadRules({int page = 0}) async {
    setState(() {
      _rulesLoading = true;
      _rulesError = null;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Please sign in again to view unit rules.');
      }

      final unitResponse = await _supabase
          .from('dayung_units')
          .select('id')
          .eq('president_id', userId)
          .order('id');
      final unitIds = List<Map<String, dynamic>>.from(
        unitResponse,
      ).map((unit) => int.tryParse('${unit['id']}')).whereType<int>().toList();

      if (unitIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _rules = [];
          _rulesPage = page;
          _rulesHaveMore = false;
        });
        return;
      }

      final start = page * _announcementPageSize;
      final response = await _supabase
          .from('dayung_rules')
          .select('updated_by, created_at, updated_at')
          .inFilter('dayung_unit_id', unitIds)
          .order('updated_at', ascending: false)
          .range(start, start + _announcementPageSize);
      final rows = List<Map<String, dynamic>>.from(response);
      final hasMore = rows.length > _announcementPageSize;
      final rules = rows.take(_announcementPageSize).toList();
      final updaterIds = rules
          .map((rule) => rule['updated_by'])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final updaterNames = <String, String>{};
      if (updaterIds.isNotEmpty) {
        final updaters = await _supabase
            .from('users')
            .select('id, full_name')
            .inFilter('id', updaterIds);
        for (final updater in List<Map<String, dynamic>>.from(updaters)) {
          final id = updater['id']?.toString();
          final name = updater['full_name']?.toString().trim();
          if (id != null && name != null && name.isNotEmpty) {
            updaterNames[id] = name;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _rulesPage = page;
        _rulesHaveMore = hasMore;
        _rules = rules
            .map(
              (rule) => {
                ...rule,
                'updated_by_display':
                    updaterNames[rule['updated_by']?.toString()] ??
                    (rule['updated_by'] == null ? null : 'Name unavailable'),
              },
            )
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _rulesError = error.toString());
    } finally {
      if (mounted) setState(() => _rulesLoading = false);
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
              onPressed: _loading || _announcementsLoading || _rulesLoading
                  ? null
                  : _refreshAll,
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
              onRefresh: _refreshAll,
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
                              children: [
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
                                    entries: _announcements,
                                    loading: _announcementsLoading,
                                    error: _announcementsError,
                                    onRetry: _loadAnnouncements,
                                    hasPreviousPage: _announcementPage > 0,
                                    hasNextPage: _announcementsHaveMore,
                                    onPreviousPage: () => _loadAnnouncements(
                                      page: _announcementPage - 1,
                                    ),
                                    onNextPage: () => _loadAnnouncements(
                                      page: _announcementPage + 1,
                                    ),
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
                                      'Rule updated by',
                                      'Rule Created',
                                      'Last updated at',
                                    ],
                                    entries: _rules,
                                    loading: _rulesLoading,
                                    error: _rulesError,
                                    onRetry: () => _loadRules(page: _rulesPage),
                                    hasPreviousPage: _rulesPage > 0,
                                    hasNextPage: _rulesHaveMore,
                                    onPreviousPage: () =>
                                        _loadRules(page: _rulesPage - 1),
                                    onNextPage: () =>
                                        _loadRules(page: _rulesPage + 1),
                                    loadingMessage: 'Loading unit rules...',
                                    errorMessage: 'Could not load unit rules',
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
                              entries: _announcements,
                              loading: _announcementsLoading,
                              error: _announcementsError,
                              onRetry: _loadAnnouncements,
                              hasPreviousPage: _announcementPage > 0,
                              hasNextPage: _announcementsHaveMore,
                              onPreviousPage: () => _loadAnnouncements(
                                page: _announcementPage - 1,
                              ),
                              onNextPage: () => _loadAnnouncements(
                                page: _announcementPage + 1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _ActivityLogSection(
                              number: '02',
                              title: 'User preferences',
                              description:
                                  'A record of changes made to unit rules and preferences.',
                              icon: Icons.tune_rounded,
                              columns: const [
                                'Rule updated by',
                                'Rule Created',
                                'Last updated at',
                              ],
                              entries: _rules,
                              loading: _rulesLoading,
                              error: _rulesError,
                              onRetry: () => _loadRules(page: _rulesPage),
                              hasPreviousPage: _rulesPage > 0,
                              hasNextPage: _rulesHaveMore,
                              onPreviousPage: () =>
                                  _loadRules(page: _rulesPage - 1),
                              onNextPage: () =>
                                  _loadRules(page: _rulesPage + 1),
                              loadingMessage: 'Loading unit rules...',
                              errorMessage: 'Could not load unit rules',
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
    this.entries = const [],
    this.loading = false,
    this.error,
    this.onRetry,
    this.hasPreviousPage = false,
    this.hasNextPage = false,
    this.onPreviousPage,
    this.onNextPage,
    this.loadingMessage = 'Loading announcements...',
    this.errorMessage = 'Could not load announcements',
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;
  final List<String> columns;
  final List<Map<String, dynamic>> entries;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final bool hasPreviousPage;
  final bool hasNextPage;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final String loadingMessage;
  final String errorMessage;

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
          RecordDataTable(
            minWidth: columns.length * 150,
            showCheckboxColumn: false,
            headingRowColor: dayungSoftSurface(context),
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
            rows: [
              for (final entry in entries)
                DataRow(
                  cells: [
                    for (final column in columns)
                      DataCell(
                        Text(
                          _announcementCellValue(entry, column),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dayungTextColor(context),
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if (onPreviousPage != null || onNextPage != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: !loading && hasPreviousPage
                      ? onPreviousPage
                      : null,
                  child: const Text('Previous'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: !loading && hasNextPage ? onNextPage : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
          if (loading) ...[
            const SizedBox(height: 18),
            _ActivityLogStateCard(
              icon: Icons.hourglass_top_rounded,
              message: loadingMessage,
            ),
          ] else if (error != null) ...[
            const SizedBox(height: 18),
            _ActivityLogStateCard(
              icon: Icons.error_outline_rounded,
              message: '$errorMessage: $error',
              actionLabel: 'Try again',
              onAction: onRetry,
            ),
          ] else if (entries.isEmpty) ...[
            const SizedBox(height: 18),
            const _ActivityLogStateCard(
              icon: Icons.inbox_outlined,
              message:
                  'No records yet. New activity will appear here when available.',
            ),
          ],
        ],
      ),
    );
  }
}

String _announcementCellValue(Map<String, dynamic> entry, String column) {
  final value = switch (column) {
    'Title' => entry['title'],
    'Category' => entry['category'],
    'Description' => entry['body'],
    'Posted by' => entry['posted_by'],
    'Date and time' => entry['created_at'],
    'Rule updated by' => entry['updated_by_display'],
    'Rule Created' => entry['created_at'],
    'Last updated at' => entry['updated_at'],
    _ => null,
  };
  if (column == 'Date and time' ||
      column == 'Rule Created' ||
      column == 'Last updated at') {
    final createdAt = DateTime.tryParse(value?.toString() ?? '');
    return createdAt == null
        ? 'Date unavailable'
        : DateFormat('MMM d, yyyy • h:mm a').format(createdAt.toLocal());
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? '—' : text;
}

class _ActivityLogStateCard extends StatelessWidget {
  const _ActivityLogStateCard({
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: dayungSoftSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dayungBorder(context)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: dayungSubtextColor(context)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: dayungTextColor(context),
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: dayungTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
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
            icon: Icons.inbox_outlined,
            message: 'No recent activity is available.',
          )
        else
          for (final entry in entries) ...[
            _ActivityEntryCard(entry: entry),
            const SizedBox(height: 10),
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
