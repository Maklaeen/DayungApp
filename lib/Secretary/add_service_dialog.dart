import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Service'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Type of Service'),
                onChanged: (v) => _serviceName = v,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              ListTile(
                title: Text(_timeService == null
                    ? 'Choose Time & Date'
                    : _timeService.toString()),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
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
                        _timeService = DateTime(
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
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Notes'),
                onChanged: (v) => _notes = v,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _obligated,
                    onChanged: (v) {
                      setState(() {
                        _obligated = v ?? true;
                        if (_obligated) _required = 1;
                      });
                    },
                  ),
                  const Text('Obligated (All must join)'),
                  if (!_obligated)
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Person Needed',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _required = int.tryParse(v) ?? 1,
                        enabled: !_obligated,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_formKey.currentState?.validate() != true || _timeService == null) return;
            final sb = Supabase.instance.client;
            await sb.from('service_checklist').insert({
              'service_name': _serviceName,
              'time_service': _timeService!.toIso8601String(),
              'notes': _notes,
              'required': _required,
              'userdeceased': widget.deathNotice['user_id'],
              'dayung_unit_id': widget.deathNotice['dayung_unit_id'],
              'death_notice_id': widget.deathNotice['id'],
              'is_removed': false,
            });
            widget.onServiceAdded();
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}