import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryLight = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const kAccentDark = Color(0xFF059669);
const Color kBg = Color(0xFFF8FAFC);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kDanger = Color(0xFFEF4444);
const double kEdge = 16;

final serviceChecklistProvider =
    StateNotifierProvider.family<
      ServiceChecklistNotifier,
      List<Map<String, dynamic>>,
      int
    >((ref, deathNoticeId) => ServiceChecklistNotifier(deathNoticeId));

class ServiceChecklistNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  final int deathNoticeId;
  ServiceChecklistNotifier(this.deathNoticeId) : super([]) {
    loadChecklist();
  }

  Future<void> loadChecklist() async {
    final sb = Supabase.instance.client;
    final checklist = await sb
        .from('service_checklists')
        .select('id, service_name, is_done, updated_at')
        .eq('death_notice_id', deathNoticeId)
        .order('updated_at', ascending: false);
    state = List<Map<String, dynamic>>.from(checklist);
  }

  Future<void> toggleDone(int checklistId, bool isDone) async {
    final sb = Supabase.instance.client;
    await sb
        .from('service_checklists')
        .update({'is_done': isDone})
        .eq('id', checklistId);
    await loadChecklist();
  }

  Future<void> addService(String serviceName) async {
    final sb = Supabase.instance.client;
    await sb.from('service_checklists').insert({
      'death_notice_id': deathNoticeId,
      'service_name': serviceName,
      'is_done': false,
    });
    await loadChecklist();
  }

  Future<void> editService(int checklistId, String newName) async {
    final sb = Supabase.instance.client;
    await sb
        .from('service_checklists')
        .update({'service_name': newName})
        .eq('id', checklistId);
    await loadChecklist();
  }
}

class ServiceTrackerPage extends StatefulWidget {
  final int dayungUnitId;
  const ServiceTrackerPage({super.key, required this.dayungUnitId});

  @override
  State<ServiceTrackerPage> createState() => _ServiceTrackerPageState();
}

class _ServiceTrackerPageState extends State<ServiceTrackerPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _notices = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    final sb = Supabase.instance.client;
    try {
      // Fetch death notices
      final notices = await sb
          .from('death_notices')
          .select('id, name, date_of_death')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('date_of_death', ascending: false);

      // For each notice, fetch checklist
      List<Map<String, dynamic>> data = [];
      for (final n in notices) {
        final checklist = await sb
            .from('service_checklists')
            .select('service_name, is_done')
            .eq('death_notice_id', n['id']);
        data.add({'notice': n, 'checklist': checklist});
      }
      setState(() {
        _notices = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading service tracker: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          final horizontalPadding = isWide ? constraints.maxWidth * 0.15 : 20.0;
          final headerFontSize = isWide ? 28.0 : 20.0;

          return Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  isWide ? 60 : 32,
                  horizontalPadding,
                  isWide ? 48 : 32,
                ),
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Icon(
                      Icons.track_changes_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Service Tracker',
                        style: TextStyle(
                          fontSize: headerFontSize,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                            color: kCardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: kBorderColor.withOpacity(0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 15,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: kPrimary,
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Loading service tracker...',
                                style: TextStyle(
                                  color: kSubText,
                                  fontSize: 12,
                                  fontFamily: 'OpenSans',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _notices.isEmpty
                    ? Center(
                        child: Container(
                          margin: const EdgeInsets.all(20),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: kCardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: kBorderColor.withOpacity(0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 15,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.track_changes_rounded,
                                size: 48,
                                color: kSubText,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No service records found',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: kText,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'No death notices have been recorded yet',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: kSubText,
                                  fontFamily: 'OpenSans',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: ListView.separated(
                          itemCount: _notices.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final n = _notices[i]['notice'];
                            return GestureDetector(
                              onTap: () => _showVigilLocationModal(context, n),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: kCardBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: kBorderColor.withOpacity(0.3),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 6,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.person_rounded,
                                          color: kPrimary,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                n['name'] ?? '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: kText,
                                                  fontFamily: 'Montserrat',
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                n['date_of_death'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: kSubText,
                                                  fontFamily: 'OpenSans',
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right,
                                          color: kSubText,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final checklist = ref.watch(
                                          serviceChecklistProvider(n['id']),
                                        );
                                        final doneCount = checklist
                                            .where((c) => c['is_done'] == true)
                                            .length;
                                        final total = checklist.length;
                                        final progress = total == 0
                                            ? 0.0
                                            : doneCount / total;

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Service Checklist:',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: kText,
                                                fontFamily: 'Montserrat',
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            LinearProgressIndicator(
                                              value: progress,
                                              backgroundColor: kBorderColor
                                                  .withOpacity(0.2),
                                              color: kSuccess,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '$doneCount of $total services completed',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: kSubText,
                                                fontFamily: 'OpenSans',
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ...checklist.map((c) {
                                              final done = c['is_done'] == true;
                                              final updatedAt = c['updated_at'];
                                              String formattedDate = '';
                                              if (updatedAt != null) {
                                                try {
                                                  final date = DateTime.parse(
                                                    updatedAt,
                                                  );
                                                  formattedDate =
                                                      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                                                } catch (_) {}
                                              }
                                              return ListTile(
                                                leading: Checkbox(
                                                  value: done,
                                                  onChanged: (val) {
                                                    ref
                                                        .read(
                                                          serviceChecklistProvider(
                                                            n['id'],
                                                          ).notifier,
                                                        )
                                                        .toggleDone(
                                                          c['id'],
                                                          val ?? false,
                                                        );
                                                  },
                                                  activeColor: kSuccess,
                                                ),
                                                title: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        c['service_name'] ?? '',
                                                        style: TextStyle(
                                                          color: done
                                                              ? kSuccess
                                                              : kDanger,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontFamily:
                                                              'OpenSans',
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.edit,
                                                        size: 18,
                                                        color: kPrimary,
                                                      ),
                                                      tooltip: 'Edit Service',
                                                      onPressed: () async {
                                                        final controller =
                                                            TextEditingController(
                                                              text:
                                                                  c['service_name'],
                                                            );
                                                        final result = await showDialog<String>(
                                                          context: context,
                                                          builder: (context) => AlertDialog(
                                                            title: const Text(
                                                              'Edit Service',
                                                            ),
                                                            content: TextField(
                                                              controller:
                                                                  controller,
                                                              autofocus: true,
                                                              decoration:
                                                                  const InputDecoration(
                                                                    labelText:
                                                                        'Service Name',
                                                                  ),
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                      context,
                                                                    ),
                                                                child:
                                                                    const Text(
                                                                      'Cancel',
                                                                    ),
                                                              ),
                                                              ElevatedButton(
                                                                onPressed: () {
                                                                  if (controller
                                                                      .text
                                                                      .trim()
                                                                      .isNotEmpty) {
                                                                    Navigator.pop(
                                                                      context,
                                                                      controller
                                                                          .text
                                                                          .trim(),
                                                                    );
                                                                  }
                                                                },
                                                                child:
                                                                    const Text(
                                                                      'Save',
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                        if (result != null &&
                                                            result.isNotEmpty) {
                                                          await ref
                                                              .read(
                                                                serviceChecklistProvider(
                                                                  n['id'],
                                                                ).notifier,
                                                              )
                                                              .editService(
                                                                c['id'],
                                                                result,
                                                              );
                                                        }
                                                      },
                                                    ),
                                                    if (formattedDate
                                                        .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              left: 8.0,
                                                            ),
                                                        child: Text(
                                                          formattedDate,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color: kSubText,
                                                                fontFamily:
                                                                    'OpenSans',
                                                              ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              );
                                            }),
                                            // Add Service Button
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: TextButton.icon(
                                                icon: const Icon(
                                                  Icons.add,
                                                  size: 18,
                                                  color: kPrimary,
                                                ),
                                                label: const Text(
                                                  'Add Service',
                                                  style: TextStyle(
                                                    color: kPrimary,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily: 'Montserrat',
                                                  ),
                                                ),
                                                onPressed: () async {
                                                  final controller =
                                                      TextEditingController();
                                                  final result = await showDialog<String>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      title: const Text(
                                                        'Add Service',
                                                      ),
                                                      content: TextField(
                                                        controller: controller,
                                                        autofocus: true,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  'Service Name',
                                                            ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                              ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () {
                                                            if (controller.text
                                                                .trim()
                                                                .isNotEmpty) {
                                                              Navigator.pop(
                                                                context,
                                                                controller.text
                                                                    .trim(),
                                                              );
                                                            }
                                                          },
                                                          child: const Text(
                                                            'Add',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (result != null &&
                                                      result.isNotEmpty) {
                                                    await ref
                                                        .read(
                                                          serviceChecklistProvider(
                                                            n['id'],
                                                          ).notifier,
                                                        )
                                                        .addService(result);
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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

void _showVigilLocationModal(
  BuildContext context,
  Map<String, dynamic> notice,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
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
                  Icons.track_changes_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Death Information',
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
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // In loving memory section
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          color: kText,
                          size: 24,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kBorderColor.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          color: kText,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'In loving memory of:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: kText,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // User information card
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      '${notice['name'] ?? 'Unknown'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kText,
                        fontFamily: 'Montserrat',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Date
                  Center(
                    child: Text(
                      '--- ${_formatDate(notice['date_of_death'])}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: kText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Location of Vigil
                  Row(
                    children: [
                      const Text(
                        'Location of Vigil:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: kText,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: kPrimary,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Open in Maps',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kPrimary,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Location name
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: const Text(
                      'Centro San Juan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kText,
                        fontFamily: 'Montserrat',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Map placeholder
                  Container(
                    height: 120,
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.map_rounded,
                          size: 32,
                          color: kSubText,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Map View',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: kSubText,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Centro San Juan Location',
                          style: TextStyle(
                            fontSize: 10,
                            color: kSubText,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Footer message
                  const Center(
                    child: Text(
                      'With deepest respect and remembrance.',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: kSubText,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatDate(dynamic dateString) {
  if (dateString == null) return 'Unknown Date';
  try {
    final date = DateTime.parse(dateString.toString());
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  } catch (e) {
    return dateString.toString();
  }
}
