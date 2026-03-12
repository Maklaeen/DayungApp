import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
    >((ref, deathNoticeId) {
      return ServiceChecklistNotifier(deathNoticeId);
    });

class ServiceChecklistNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  final int deathNoticeId;
  ServiceChecklistNotifier(this.deathNoticeId) : super([]);

  Future<void> removeService(int checklistId) async {
    final sb = Supabase.instance.client;
    try {
      await sb.from('service_checklist').delete().eq('id', checklistId);
      state = state.where((item) => item['id'] != checklistId).toList();
    } catch (e) {
      debugPrint('Error removing service: $e');
    }
  }

  Future<void> fetchServices() async {
    final sb = Supabase.instance.client;
    try {
      final response = await sb
          .from('service_checklist')
          .select()
          .eq('death_notice_id', deathNoticeId);
      state = List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching services: $e');
    }
  }
}

class ServiceTrackerPage extends StatefulWidget {
  final int dayungUnitId;
  const ServiceTrackerPage({Key? key, required this.dayungUnitId})
    : super(key: key);

  @override
  _ServiceTrackerPageState createState() => _ServiceTrackerPageState();
}

class _ServiceTrackerPageState extends State<ServiceTrackerPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _notices = [];
  Map<int, List<Map<String, dynamic>>> _servicesByUser =
      {}; // user_id -> services

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final sb = Supabase.instance.client;
    try {
      final response = await sb
          .from('death_notices')
          .select()
          .eq('dayung_unit_id', widget.dayungUnitId);
      final notices = List<Map<String, dynamic>>.from(response as List);

      // Fetch services for each userdeceased (user_id)
      Map<int, List<Map<String, dynamic>>> servicesByUser = {};
      for (final notice in notices) {
        final userId = notice['user_id'];
        final services = await sb
            .from('service_checklist')
            .select()
            .eq('userdeceased', userId)
            .eq('is_removed', false);
        servicesByUser[userId] = List<Map<String, dynamic>>.from(
          services as List,
        );
      }

      setState(() {
        _notices = notices;
        _servicesByUser = servicesByUser;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching notices/services: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  void _showAddServiceDialog(Map<String, dynamic> notice) {
    final _formKey = GlobalKey<FormState>();
    String serviceName = '';
    DateTime? timeService;
    String notes = '';
    String required = 'All';
    final requiredOptions = ['All', 'Custom'];
    int? customRequired;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 10,
              title: const Text(
                'Add Service',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Type of Service
                      TextFormField(
                        inputFormatters: AppInputSecurity.singleLineFormatters(
                          maxLength: 120,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Type of Service',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.design_services),
                        ),
                        onChanged: (val) =>
                            serviceName = AppInputSecurity.sanitizePlainText(
                              val,
                              maxLength: 120,
                            ),
                        validator: (val) => AppInputSecurity.validateSafeText(
                          val,
                          fieldName: 'Type of Service',
                          minLength: 2,
                          maxLength: 120,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Time Start
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                timeService == null
                                    ? 'Select Time Start'
                                    : DateFormat(
                                        'yyyy-MM-dd HH:mm',
                                      ).format(timeService!),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (date != null) {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (time != null) {
                                  setState(() {
                                    timeService = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      time.hour,
                                      time.minute,
                                    );
                                  });
                                }
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      TextFormField(
                        inputFormatters: AppInputSecurity.multiLineFormatters(
                          maxLength: 300,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Notes',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.note),
                        ),
                        onChanged: (val) =>
                            notes = AppInputSecurity.sanitizePlainText(
                              val,
                              allowNewLines: true,
                              maxLength: 300,
                            ),
                      ),
                      const SizedBox(height: 16),

                      // Required
                      DropdownButtonFormField<String>(
                        value: required,
                        decoration: InputDecoration(
                          labelText: 'Required',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.group),
                        ),
                        items: requiredOptions
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            required = val!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      if (required == 'Custom')
                        TextFormField(
                          inputFormatters: AppInputSecurity.phoneFormatters(
                            maxLength: 3,
                          ),
                          decoration: InputDecoration(
                            labelText: 'How many persons?',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.person),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) =>
                              customRequired = int.tryParse(val),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    debugPrint('Save button pressed');
                    if (_formKey.currentState!.validate() &&
                        timeService != null) {
                      debugPrint('Form validated. Preparing to insert...');
                      try {
                        final sb = Supabase.instance.client;
                        final insertData = {
                          'service_name': AppInputSecurity.sanitizePlainText(
                            serviceName,
                            maxLength: 120,
                          ),
                          'time_service': timeService!.toIso8601String(),
                          'notes': AppInputSecurity.sanitizePlainText(
                            notes,
                            allowNewLines: true,
                            maxLength: 300,
                          ),
                          'required': required == 'All'
                              ? notice['person_needed'] ?? 'All'
                              : customRequired ?? 1,
                          'userdeceased': notice['user_id'],
                          'dayung_unit_id': notice['dayung_unit_id'],
                          'death_notice_id': notice['id'],
                          'is_removed': false,
                        };
                        debugPrint('Insert data: $insertData');
                        final response = await sb
                            .from('service_checklist')
                            .insert(insertData)
                            .select();
                        debugPrint('Insert response: $response');
                        Navigator.pop(context);
                      } on PostgrestException catch (e) {
                        debugPrint(
                          'PostgrestException: ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${e.message}')),
                        );
                      } catch (e, stack) {
                        debugPrint('Error inserting service: $e');
                        debugPrint('Stack trace: $stack');
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    } else {
                      debugPrint('Form not valid or timeService is null');
                      if (timeService == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select a start time'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
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
                      style: const TextStyle(
                        fontSize: 18,
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
            _loading
                ? const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notices.length,
                      itemBuilder: (context, index) {
                        final notice = _notices[index];
                        final userId = notice['user_id'];
                        final services = _servicesByUser[userId] ?? [];

                        // Debug: Print services for this user
                        debugPrint('UserID: $userId, Services: $services');

                        return Card(
                          color: kCardBg,
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            notice['name'] ?? 'No Name',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: kText,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.calendar_today,
                                                size: 16,
                                                color: kSubText,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Date of Death: ',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: kSubText,
                                                ),
                                              ),
                                              Flexible(
                                                child: Text(
                                                  notice['date_of_death'] ??
                                                      'N/A',
                                                  style: const TextStyle(
                                                    color: kSubText,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.account_tree,
                                                size: 16,
                                                color: kSubText,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Dayung Unit ID: ',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: kSubText,
                                                ),
                                              ),
                                              Text(
                                                '${notice['dayung_unit_id'] ?? 'N/A'}',
                                                style: const TextStyle(
                                                  color: kSubText,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.cake,
                                                size: 16,
                                                color: kSubText,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Date of Birth: ',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: kSubText,
                                                ),
                                              ),
                                              Flexible(
                                                child: Text(
                                                  notice['dob'] ?? 'N/A',
                                                  style: const TextStyle(
                                                    color: kSubText,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.accessibility_new,
                                                size: 16,
                                                color: kSubText,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Deceased Age: ',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: kSubText,
                                                ),
                                              ),
                                              Text(
                                                '${notice['deceased_age'] ?? 'N/A'} yrs',
                                                style: const TextStyle(
                                                  color: kSubText,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(
                                            Icons.add,
                                            color: kPrimary,
                                          ),
                                          label: const Text('Add Service'),
                                          onPressed: () =>
                                              _showAddServiceDialog(notice),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
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
