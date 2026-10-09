import 'dart:convert';

import 'package:capstone_app/President/post_announcement.dart';
import 'package:capstone_app/SuperAdmin/superadmin_support.dart'
    show kSuperAdminBackendBaseUrl;
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SmsAnnouncementPage extends StatefulWidget {
  const SmsAnnouncementPage({super.key});

  @override
  State<SmsAnnouncementPage> createState() => _SmsAnnouncementPageState();
}

class _SmsAnnouncementPageState extends State<SmsAnnouncementPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _units = [];
  int? _unitId;
  bool _loadingUnits = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Please sign in again.');

      final response = await _supabase
          .from('dayung_units')
          .select('id, name')
          .eq('president_id', userId)
          .order('name');
      if (!mounted) return;
      setState(() {
        _units = List<Map<String, dynamic>>.from(response);
        if (_units.length == 1) {
          _unitId = int.tryParse('${_units.first['id']}');
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load your units: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingUnits = false);
    }
  }

  Future<void> _sendSms() async {
    if (!_formKey.currentState!.validate()) return;
    final backendUrl = kSuperAdminBackendBaseUrl.trim().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    if (backendUrl.isEmpty) {
      _showMessage(
        'SMS server is not configured. Build the app with SUPERADMIN_BACKEND_URL.',
      );
      return;
    }

    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      _showMessage('Your session expired. Please sign in again.');
      return;
    }

    setState(() => _sending = true);
    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/send-announcement-sms'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'dayung_unit_id': _unitId,
              'title': _titleController.text.trim(),
              'body': _bodyController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 90));
      final result = jsonDecode(response.body);
      final resultMap = result is Map ? result : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          resultMap['error']?.toString() ?? 'SMS delivery failed.',
        );
      }

      if (!mounted) return;
      _titleController.clear();
      _bodyController.clear();
      _showMessage('SMS sent to ${resultMap['sent'] ?? 0} recipients.');
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: dayungSurface(context),
      appBar: AppBar(title: const Text('Announcement for SMS')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: dayungSectionCardDecoration(context),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.sms_outlined,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Send an SMS announcement',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The message will go to approved members and unit officers who have a saved mobile number.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_loadingUnits)
                    const LinearProgressIndicator()
                  else if (_units.isEmpty)
                    Text(
                      'No unit is assigned to your account as President.',
                      style: TextStyle(color: colorScheme.error),
                    )
                  else if (_units.length > 1)
                    DropdownButtonFormField<int>(
                      initialValue: _unitId,
                      decoration: const InputDecoration(
                        labelText: 'Dayung unit',
                      ),
                      items: _units
                          .map(
                            (unit) => DropdownMenuItem<int>(
                              value: int.tryParse('${unit['id']}'),
                              child: Text(unit['name']?.toString() ?? 'Unit'),
                            ),
                          )
                          .toList(),
                      onChanged: _sending
                          ? null
                          : (value) => setState(() => _unitId = value),
                      validator: (value) =>
                          value == null ? 'Select a unit.' : null,
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Announcement title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Enter a title with at least 3 characters.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bodyController,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 800,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Enter a message with at least 3 characters.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sending || _loadingUnits || _units.isEmpty
                          ? null
                          : _sendSms,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(_sending ? 'Sending SMS...' : 'Send SMS'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _sending
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PostAnnouncementPage(),
                              ),
                            ),
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('Post an in-app announcement instead'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
