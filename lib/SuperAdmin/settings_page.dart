import 'package:flutter/material.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);

class SuperAdminSettingsPage extends StatelessWidget {
  const SuperAdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: themeBg,
      appBar: AppBar(
        title: const Text('System Settings'),
        backgroundColor: kPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kPrimary,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: kCardBg,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            child: SwitchListTile(
              title: const Text(
                'Maintenance Mode',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Temporarily disable user access for maintenance.',
                style: TextStyle(fontSize: 13, color: kSubText),
              ),
              value: false,
              onChanged: (val) {
                // TODO: Implement maintenance mode toggle
              },
              activeColor: kPrimary,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: kCardBg,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            child: ListTile(
              leading: const Icon(Icons.backup, color: kPrimary),
              title: const Text(
                'Backup Database',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Download a backup of all system data.',
                style: TextStyle(fontSize: 13, color: kSubText),
              ),
              onTap: () {
                // TODO: Implement backup logic
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: kSubText,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: kCardBg,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: kPrimary),
              title: const Text(
                'About System',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'View system version and developer info.',
                style: TextStyle(fontSize: 13, color: kSubText),
              ),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Dayung Admin System',
                  applicationVersion: 'v1.0.0',
                  applicationLegalese: 'Developed by Your Team',
                );
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: kSubText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
