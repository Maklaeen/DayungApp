import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:intl/intl.dart';

class AddServiceDialog extends StatefulWidget {
  final Map<String, dynamic> deathNotice;
  final VoidCallback onServiceAdded;

  const AddServiceDialog({
    super.key,
    required this.deathNotice,
    required this.onServiceAdded,
  });

  @override
  State<AddServiceDialog> createState() => _AddServiceDialogState();
}

class _AddServiceDialogState extends State<AddServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  String _serviceName = '';
  DateTime? _timeService;
  String _notes = '';
  int _required = 1;
  bool _obligated = true;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 52,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.playlist_add_check_circle_rounded,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Add Service',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (widget.deathNotice['deceased_full_name']?.toString().isNotEmpty ?? false)
                                    ? widget.deathNotice['deceased_full_name']!.toString()
                                    : (widget.deathNotice['name']?.toString().isNotEmpty ?? false)
                                        ? widget.deathNotice['name']!.toString()
                                        : 'Service schedule',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      inputFormatters: AppInputSecurity.singleLineFormatters(
                        maxLength: 120,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Type of Service',
                        hintText: 'Ex. Vigil, Wake Assistance, Burial Service',
                        prefixIcon: const Icon(Icons.design_services_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onChanged: (v) => _serviceName =
                          AppInputSecurity.sanitizePlainText(v, maxLength: 120),
                      validator: (v) => AppInputSecurity.validateSafeText(
                        v,
                        fieldName: 'Type of Service',
                        minLength: 2,
                        maxLength: 120,
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _saving
                          ? null
                          : () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _timeService ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (date == null || !context.mounted) return;
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _timeService == null
                                    ? TimeOfDay.now()
                                    : TimeOfDay.fromDateTime(_timeService!),
                              );
                              if (time == null || !context.mounted) return;
                              setState(() {
                                _timeService = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  time.hour,
                                  time.minute,
                                );
                              });
                            },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFD1D5DB)),
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFFF8FAFC),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.schedule_rounded,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Schedule',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _timeService == null
                                        ? 'Choose date and time'
                                        : DateFormat(
                                            'MMM d, yyyy • h:mm a',
                                          ).format(_timeService!),
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: _timeService == null
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFF111827),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      inputFormatters: AppInputSecurity.multiLineFormatters(
                        maxLength: 300,
                      ),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Notes',
                        hintText:
                            'Add setup details, reminders, or service notes',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 48),
                          child: Icon(Icons.note_alt_rounded),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onChanged: (v) =>
                          _notes = AppInputSecurity.sanitizePlainText(
                            v,
                            allowNewLines: true,
                            maxLength: 300,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Participation',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            value: _obligated,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Obligated for all members'),
                            subtitle: const Text(
                              'Leave this on when everyone is expected to join.',
                            ),
                            onChanged: _saving
                                ? null
                                : (v) {
                                    setState(() {
                                      _obligated = v ?? true;
                                      if (_obligated) {
                                        _required = 1;
                                      }
                                    });
                                  },
                          ),
                          if (!_obligated) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Persons Needed',
                                prefixIcon: const Icon(Icons.groups_2_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: AppInputSecurity.phoneFormatters(
                                maxLength: 3,
                              ),
                              onChanged: (v) =>
                                  _required = int.tryParse(v) ?? 1,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    final navigator = Navigator.of(context);
                                    if (_formKey.currentState?.validate() !=
                                            true ||
                                        _timeService == null) {
                                      if (_timeService == null) {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Please select a schedule.',
                                            ),
                                          ),
                                        );
                                      }
                                      return;
                                    }

                                    setState(() => _saving = true);
                                    try {
                                      final sb = Supabase.instance.client;
                                      await sb.from('service_checklist').insert({
                                        'service_name':
                                            AppInputSecurity.sanitizePlainText(
                                              _serviceName,
                                              maxLength: 120,
                                            ),
                                        'time_service': _timeService!
                                            .toIso8601String(),
                                        'notes':
                                            AppInputSecurity.sanitizePlainText(
                                              _notes,
                                              allowNewLines: true,
                                              maxLength: 300,
                                            ),
                                        'required': _obligated
                                            ? 'All'
                                            : _required,
                                        'userdeceased':
                                            widget.deathNotice['user_id'],
                                        'dayung_unit_id': widget
                                            .deathNotice['dayung_unit_id'],
                                     
                                        'is_removed': false,
                                      });
                                      widget.onServiceAdded();
                                      if (!mounted) return;
                                      navigator.pop();
                                    } on PostgrestException catch (e) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('Error: ${e.message}'),
                                        ),
                                      );
                                    } catch (e) {
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() => _saving = false);
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: const Color(0xFF1E40AF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save Service'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
