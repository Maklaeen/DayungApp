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
  String? _unitLoadError;

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
    if (mounted) {
      setState(() {
        _loadingUnits = true;
        _unitLoadError = null;
      });
    }
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw StateError('Please sign in again.');

      final response = await _supabase
          .from('dayung_units')
          .select('id, name')
          .eq('president_id', userId)
          .order('name');
      if (!mounted) return;
      setState(() {
        _units = List<Map<String, dynamic>>.from(response);
        _unitId = null;
        if (_units.length == 1) {
          _unitId = int.tryParse('${_units.first['id']}');
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _unitLoadError = error.toString());
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

  Widget _buildAudienceField(ColorScheme colorScheme) {
    if (_loadingUnits) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    if (_unitLoadError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Could not load Dayung units.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: _loadUnits, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_units.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No Dayung unit is assigned to your account.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }

    if (_units.length == 1) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Dayung unit',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _units.first['name']?.toString() ?? 'Dayung Unit',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<int>(
      initialValue: _unitId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Dayung unit',
        border: OutlineInputBorder(),
      ),
      items: _units
          .map(
            (unit) => DropdownMenuItem<int>(
              value: int.tryParse('${unit['id']}'),
              child: Text(
                unit['name']?.toString() ?? 'Unit',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _sending ? null : (value) => setState(() => _unitId = value),
      validator: (value) => value == null ? 'Select a unit.' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: dayungSurface(context),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 20, 14),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Back',
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Announcement for SMS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 700;
                  return ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 24 : 16,
                      vertical: 20,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: dayungSectionCardDecoration(context),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.sms_outlined,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Send an SMS',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'To approved members and officers with saved mobile numbers.',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  _buildAudienceField(colorScheme),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _titleController,
                                    enabled: !_sending,
                                    maxLength: 120,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: const InputDecoration(
                                      labelText: 'Announcement title',
                                      hintText: 'e.g. Monthly meeting',
                                      prefixIcon: Icon(Icons.title_rounded),
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) =>
                                        (value ?? '').trim().length < 3
                                        ? 'Enter a title with at least 3 characters.'
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _bodyController,
                                    enabled: !_sending,
                                    minLines: 4,
                                    maxLines: 7,
                                    maxLength: 800,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: const InputDecoration(
                                      labelText: 'Message',
                                      hintText:
                                          'Write a short message for recipients',
                                      alignLabelWithHint: true,
                                      prefixIcon: Icon(Icons.notes_rounded),
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) =>
                                        (value ?? '').trim().length < 3
                                        ? 'Enter a message with at least 3 characters.'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  LayoutBuilder(
                                    builder: (context, actionConstraints) {
                                      final stackButtons =
                                          actionConstraints.maxWidth < 560;
                                      final sendButton = FilledButton.icon(
                                        onPressed:
                                            _sending ||
                                                _loadingUnits ||
                                                _units.isEmpty ||
                                                _unitId == null
                                            ? null
                                            : _sendSms,
                                        icon: _sending
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.send_rounded),
                                        label: Text(
                                          _sending
                                              ? 'Sending SMS...'
                                              : 'Send SMS',
                                        ),
                                      );
                                      final inAppButton = OutlinedButton.icon(
                                        onPressed: _sending
                                            ? null
                                            : () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const PostAnnouncementPage(),
                                                ),
                                              ),
                                        icon: const Icon(
                                          Icons.campaign_outlined,
                                        ),
                                        label: const Text(
                                          'Post in-app instead',
                                        ),
                                      );

                                      if (stackButtons) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            sendButton,
                                            const SizedBox(height: 8),
                                            inAppButton,
                                          ],
                                        );
                                      }

                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          inAppButton,
                                          const SizedBox(width: 12),
                                          sendButton,
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
