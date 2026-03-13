import 'dart:convert';

import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SuperAdminSettingsPage extends StatefulWidget {
  const SuperAdminSettingsPage({super.key});

  @override
  State<SuperAdminSettingsPage> createState() => _SuperAdminSettingsPageState();
}

class _SuperAdminSettingsPageState extends State<SuperAdminSettingsPage> {
  final _messageController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _maintenanceMode = false;
  bool _allowSmsBroadcast = false;
  bool _forceOnCreate = true;
  bool _forceOnReset = true;
  bool _twilioConfigured = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await superAdminGetJson('/superadmin/settings');
      final settings = Map<String, dynamic>.from(
        result['settings'] ?? const {},
      );

      if (!mounted) return;
      setState(() {
        _maintenanceMode = settings['maintenance_mode'] == true;
        _allowSmsBroadcast = settings['allow_sms_broadcast'] == true;
        _forceOnCreate = settings['force_password_change_on_create'] != false;
        _forceOnReset = settings['force_password_change_on_reset'] != false;
        _twilioConfigured = result['twilio_configured'] == true;
        _messageController.text =
            settings['maintenance_message']?.toString() ?? '';
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final result = await superAdminPostJson('/superadmin/settings', {
        'maintenance_mode': _maintenanceMode,
        'maintenance_message': _messageController.text.trim(),
        'allow_sms_broadcast': _allowSmsBroadcast,
        'force_password_change_on_create': _forceOnCreate,
        'force_password_change_on_reset': _forceOnReset,
      });

      if (!mounted) return;
      setState(() {
        _twilioConfigured = result['twilio_configured'] == true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('System settings saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showSnapshot() async {
    try {
      final snapshot = await superAdminGetJson('/superadmin/system-snapshot');
      if (!mounted) return;

      final formatted = const JsonEncoder.withIndent('  ').convert(snapshot);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('System Snapshot'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(
                formatted,
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: formatted));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Snapshot copied to clipboard.'),
                  ),
                );
              },
              child: const Text('Copy JSON'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final onboardingPanel = _Panel(
      title: 'Onboarding Rules',
      subtitle:
          'Choose whether temporary passwords should always be replaced on first sign-in.',
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _forceOnCreate,
            onChanged: (value) => setState(() => _forceOnCreate = value),
            activeThumbColor: kSuperAdminPrimary,
            title: const Text(
              'Force password change for newly created accounts',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: kSuperAdminText,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _forceOnReset,
            onChanged: (value) => setState(() => _forceOnReset = value),
            activeThumbColor: kSuperAdminPrimary,
            title: const Text(
              'Force password change after password reset',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: kSuperAdminText,
              ),
            ),
          ),
        ],
      ),
    );

    final broadcastPanel = _Panel(
      title: 'Broadcast Delivery',
      subtitle:
          'Turn on SMS only when the server is connected to Twilio and you are ready to pay for messages.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (_twilioConfigured ? kSuperAdminAccent : kSuperAdminWarn)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _twilioConfigured
                  ? 'Twilio server integration is ready.'
                  : 'Twilio is not configured on the server.',
              style: TextStyle(
                color: _twilioConfigured ? kSuperAdminAccent : kSuperAdminWarn,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _allowSmsBroadcast,
            onChanged: (value) => setState(() => _allowSmsBroadcast = value),
            activeThumbColor: kSuperAdminPrimary,
            title: const Text(
              'Allow SMS broadcast',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: kSuperAdminText,
              ),
            ),
            subtitle: const Text(
              'When disabled, SuperAdmin broadcasts will only create in-app notifications.',
              style: TextStyle(color: kSuperAdminMuted),
            ),
          ),
        ],
      ),
    );

    final snapshotButton = OutlinedButton.icon(
      onPressed: _showSnapshot,
      icon: const Icon(Icons.inventory_2_outlined),
      label: const Text('Open system snapshot'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: kSuperAdminBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );

    final saveButton = ElevatedButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.save_outlined),
      label: Text(_saving ? 'Saving...' : 'Save settings'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: kSuperAdminPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );

    return SuperAdminAccessGuard(
      title: 'System Settings',
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
                      const _SettingsHero(),
                      const SizedBox(height: 18),
                      _Panel(
                        title: 'Access Control',
                        subtitle:
                            'Maintenance mode blocks new non-SuperAdmin sign-ins. Existing signed-in sessions are not forced out.',
                        child: Column(
                          children: [
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _maintenanceMode,
                              onChanged: (value) =>
                                  setState(() => _maintenanceMode = value),
                              activeThumbColor: kSuperAdminPrimary,
                              title: const Text(
                                'Maintenance mode',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: kSuperAdminText,
                                ),
                              ),
                              subtitle: const Text(
                                'Use this before planned updates or backend maintenance windows.',
                                style: TextStyle(color: kSuperAdminMuted),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _messageController,
                              minLines: 3,
                              maxLines: 5,
                              decoration: _decoration(
                                'Maintenance message shown to users',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 860) {
                            return Column(
                              children: [
                                onboardingPanel,
                                const SizedBox(height: 12),
                                broadcastPanel,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: onboardingPanel),
                              const SizedBox(width: 12),
                              Expanded(child: broadcastPanel),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      _Panel(
                        title: 'Operations',
                        subtitle:
                            'Use this area to capture the current server-backed state in a shareable JSON snapshot.',
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 720) {
                              return Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    child: snapshotButton,
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: saveButton,
                                  ),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: snapshotButton),
                                const SizedBox(width: 12),
                                Expanded(child: saveButton),
                              ],
                            );
                          },
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

class _SettingsHero extends StatelessWidget {
  const _SettingsHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17326B), Color(0xFF2756A4), Color(0xFFE69F00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeroIcon(icon: Icons.tune_rounded),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'System Settings',
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
          SizedBox(height: 12),
          // Text(
          //   'Control maintenance messaging, broadcast delivery, and temporary-password behavior from one safe admin surface.',
          //   style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          // ),
        ],
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  final IconData icon;

  const _HeroIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSuperAdminCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: kSuperAdminText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: kSuperAdminMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}
