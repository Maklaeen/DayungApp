import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SuperAdminBroadcastPage extends StatefulWidget {
  const SuperAdminBroadcastPage({super.key});

  @override
  State<SuperAdminBroadcastPage> createState() =>
      _SuperAdminBroadcastPageState();
}

class _SuperAdminBroadcastPageState extends State<SuperAdminBroadcastPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _sending = false;
  bool _smsAllowed = false;
  bool _twilioConfigured = false;
  bool _sendSms = false;
  String _audience = 'all_active';
  int? _selectedUnitId;
  List<Map<String, dynamic>> _units = [];

  static const _audienceOptions = [
    ('all_active', 'All active users'),
    ('members', 'Approved members'),
    ('officers', 'Officers only'),
    ('superadmins', 'SuperAdmins only'),
    ('inactive', 'Inactive accounts'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await superAdminGetJson('/superadmin/settings');
      final units = await Supabase.instance.client
          .from('dayung_units')
          .select('id, name')
          .order('name', ascending: true);

      if (!mounted) return;
      setState(() {
        _smsAllowed = settings['settings']?['allow_sms_broadcast'] == true;
        _twilioConfigured = settings['twilio_configured'] == true;
        _units = List<Map<String, dynamic>>.from(units);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool get _showUnitFilter =>
      _audience == 'all_active' ||
      _audience == 'members' ||
      _audience == 'officers' ||
      _audience == 'inactive';

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);

    try {
      final result = await superAdminPostJson('/superadmin/send-broadcast', {
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'audience': _audience,
        if (_selectedUnitId != null && _showUnitFilter)
          'dayung_unit_id': _selectedUnitId,
        'send_sms': _sendSms,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Broadcast sent to ${result['delivered']} recipients. SMS sent: ${result['sms_sent']}.',
          ),
        ),
      );
      _titleController.clear();
      _bodyController.clear();
      setState(() {
        _sendSms = false;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  String _unitName(int? id) {
    if (id == null) return 'All units';
    final match = _units
        .where((unit) => unit['id'] == id)
        .cast<Map<String, dynamic>>()
        .toList();
    if (match.isEmpty) return 'Selected unit';
    return match.first['name']?.toString() ?? 'Selected unit';
  }

  @override
  Widget build(BuildContext context) {
    return SuperAdminAccessGuard(
      title: 'Broadcast Announcement',
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
                      _BroadcastHero(
                        smsAllowed: _smsAllowed,
                        twilioConfigured: _twilioConfigured,
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: kSuperAdminCard,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: kSuperAdminBorder),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x10000000),
                              blurRadius: 22,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Choose Audience',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: kSuperAdminText,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Send one clear message to the right group without leaving the dashboard.',
                                style: TextStyle(
                                  color: kSuperAdminMuted,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: _audienceOptions.map((option) {
                                  final selected = _audience == option.$1;
                                  return ChoiceChip(
                                    label: Text(option.$2),
                                    selected: selected,
                                    onSelected: (_) {
                                      setState(() {
                                        _audience = option.$1;
                                        if (!_showUnitFilter) {
                                          _selectedUnitId = null;
                                        }
                                      });
                                    },
                                    selectedColor: kSuperAdminPrimary
                                        .withValues(alpha: 0.14),
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
                              if (_showUnitFilter) ...[
                                const SizedBox(height: 18),
                                DropdownButtonFormField<int?>(
                                  initialValue: _selectedUnitId,
                                  decoration: _decoration(
                                    'Limit to one dayung unit',
                                  ),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('All units'),
                                    ),
                                    ..._units.map(
                                      (unit) => DropdownMenuItem<int?>(
                                        value: unit['id'] as int?,
                                        child: Text(
                                          unit['name']?.toString() ??
                                              'Unnamed unit',
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => _selectedUnitId = value),
                                ),
                              ],
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _titleController,
                                decoration: _decoration('Announcement title'),
                                validator: (value) {
                                  if ((value ?? '').trim().length < 3) {
                                    return 'Please enter a clear title.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _bodyController,
                                minLines: 5,
                                maxLines: 8,
                                decoration: _decoration('Announcement message'),
                                validator: (value) {
                                  if ((value ?? '').trim().length < 6) {
                                    return 'Please enter the full message.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                value: _sendSms,
                                onChanged: (!_smsAllowed || !_twilioConfigured)
                                    ? null
                                    : (value) =>
                                          setState(() => _sendSms = value),
                                activeThumbColor: kSuperAdminPrimary,
                                title: const Text(
                                  'Also send as SMS',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: kSuperAdminText,
                                  ),
                                ),
                                subtitle: Text(
                                  !_smsAllowed
                                      ? 'Enable SMS broadcast in System Settings first.'
                                      : !_twilioConfigured
                                      ? 'Twilio is not configured on the server yet.'
                                      : 'Recipients with saved mobile numbers will also receive a text message.',
                                  style: const TextStyle(
                                    color: kSuperAdminMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              _PreviewCard(
                                audienceLabel: _audienceOptions
                                    .firstWhere((item) => item.$1 == _audience)
                                    .$2,
                                unitLabel: _unitName(_selectedUnitId),
                                sendSms: _sendSms,
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _sending ? null : _send,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kSuperAdminPrimary,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  icon: _sending
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.campaign_rounded),
                                  label: Text(
                                    _sending
                                        ? 'Sending broadcast...'
                                        : 'Send broadcast now',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
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
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: kSuperAdminMuted),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kSuperAdminBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kSuperAdminBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kSuperAdminPrimary, width: 1.8),
      ),
    );
  }
}

class _BroadcastHero extends StatelessWidget {
  final bool smsAllowed;
  final bool twilioConfigured;

  const _BroadcastHero({
    required this.smsAllowed,
    required this.twilioConfigured,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kSuperAdminPrimary, Color(0xFF2B5AA8), kSuperAdminAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Broadcast Center',
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
          const SizedBox(height: 14),
          const Text(
            'Send a clear announcement to members, officers, inactive accounts, or the whole system from one place.',
            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroChip(
                label: smsAllowed ? 'SMS allowed' : 'SMS disabled',
                icon: Icons.sms_outlined,
              ),
              _HeroChip(
                label: twilioConfigured ? 'Twilio ready' : 'Twilio missing',
                icon: Icons.settings_ethernet_rounded,
              ),
              const _HeroChip(
                label: 'In-app notifications always sent',
                icon: Icons.notifications_active_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _HeroChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String audienceLabel;
  final String unitLabel;
  final bool sendSms;

  const _PreviewCard({
    required this.audienceLabel,
    required this.unitLabel,
    required this.sendSms,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Preview',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: kSuperAdminText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Audience: $audienceLabel',
            style: const TextStyle(color: kSuperAdminMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Unit filter: $unitLabel',
            style: const TextStyle(color: kSuperAdminMuted),
          ),
          const SizedBox(height: 4),
          Text(
            sendSms
                ? 'Delivery: in-app notification plus SMS where available'
                : 'Delivery: in-app notification only',
            style: const TextStyle(color: kSuperAdminMuted),
          ),
        ],
      ),
    );
  }
}
