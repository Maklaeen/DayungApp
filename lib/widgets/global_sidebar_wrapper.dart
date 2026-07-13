import 'dart:convert';
import 'package:capstone_app/Auth/logout.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/settings/profsettings.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';

class GlobalSidebarWrapper extends StatefulWidget {
  final Widget dashboard;

  const GlobalSidebarWrapper({super.key, required this.dashboard});

  @override
  State<GlobalSidebarWrapper> createState() => _GlobalSidebarWrapperState();
}

class _GlobalSidebarWrapperState extends State<GlobalSidebarWrapper> {
  String _fullName = '';
  String _roleName = '';
  String _selectedDayungUnit = 'Dayung Unit';
  int _unreadNotifCount = 0;
  String _currentPage = 'dashboard';
  late Widget _currentContent;

  @override
  void initState() {
    super.initState();
    _currentContent = widget.dashboard;
    _loadUserInfo();
    _fetchUnreadNotifCount();
  }

  @override
  void didUpdateWidget(GlobalSidebarWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dashboard.runtimeType != widget.dashboard.runtimeType) {
      setState(() {
        _currentPage = 'dashboard';
        _currentContent = widget.dashboard;
      });
      _loadUserInfo();
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();

    String roleName = 'User';
    if (mounted) {
      try {
        final roleProvider = context.read<DayungRoleProvider>();
        if (roleProvider.isPresident) {
          roleName = 'President';
        } else if (roleProvider.isSecretary) {
          roleName = 'Secretary';
        } else if (roleProvider.isTreasurer) {
          roleName = 'Treasurer';
        } else if (roleProvider.isCollector) {
          roleName = 'Collector';
        } else {
          roleName = 'Member';
        }
      } catch (_) {}
    }

    final name =
        prefs.getString('${roleName.toLowerCase()}FullName') ?? roleName;

    String dayungLabelRaw =
        prefs.getString('selectedDayungUnit') ?? 'Dayung Unit';
    String resolvedLabel = dayungLabelRaw;
    Map<String, dynamic>? parsed;

    try {
      final jsonFull = prefs.getString('selectedDayungUnitData');
      if (jsonFull != null) parsed = jsonDecode(jsonFull);
    } catch (_) {}

    if (parsed == null &&
        dayungLabelRaw.trim().startsWith('{') &&
        dayungLabelRaw.contains('"name"')) {
      try {
        parsed = jsonDecode(dayungLabelRaw);
      } catch (_) {}
    }

    if (parsed != null && (parsed['name'] ?? '').toString().trim().isNotEmpty) {
      resolvedLabel = parsed['name'].toString();
    }

    if (mounted) {
      setState(() {
        _fullName = name;
        _roleName = roleName;
        _selectedDayungUnit = resolvedLabel;
      });
    }
  }

  Future<void> _fetchUnreadNotifCount() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .isFilter('read_at', null);
      if (mounted) setState(() => _unreadNotifCount = (rows as List).length);
    } catch (_) {
      if (mounted) setState(() => _unreadNotifCount = 0);
    }
  }

  void _navigate(String pageKey, Widget page) {
    setState(() {
      _currentPage = pageKey;
      _currentContent = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1024;

    if (!isDesktop) return widget.dashboard;

    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: Row(
        children: [
          SizedBox(width: 280, child: _buildSidebar()),
          Expanded(child: _currentContent),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Container(
        color: dayungPageBackground(context),
        child: Column(
          children: [
            // User info card
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: dayungSectionCardDecoration(context),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E40AF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      size: 24,
                      color: Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fullName.isEmpty ? _roleName : _fullName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E40AF),
                            fontFamily: 'Montserrat',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedDayungUnit,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                            fontFamily: 'OpenSans',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Nav items
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: dayungSectionCardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Navigation',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E40AF),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          _navItem(
                            icon: Icons.dashboard_rounded,
                            label: 'Dashboard',
                            pageKey: 'dashboard',
                            color: const Color(0xFF3B82F6),
                            onTap: () =>
                                _navigate('dashboard', widget.dashboard),
                          ),
                          const SizedBox(height: 8),
                          _navItem(
                            icon: Icons.account_circle_rounded,
                            label: 'Profile',
                            pageKey: 'profile',
                            color: const Color(0xFF10B981),
                            onTap: () =>
                                _navigate('profile', const ProfilePage()),
                          ),
                          const SizedBox(height: 8),
                          _navItem(
                            icon: Icons.people_rounded,
                            label: 'Beneficiaries',
                            pageKey: 'beneficiaries',
                            color: const Color(0xFF8B5CF6),
                            onTap: () => _navigate(
                              'beneficiaries',
                              const BeneficiaryPage(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _navItem(
                            icon: Icons.notifications_rounded,
                            label: 'Notifications',
                            pageKey: 'notifications',
                            color: const Color(0xFFF59E0B),
                            badgeCount: _unreadNotifCount,
                            onTap: () {
                              _navigate(
                                'notifications',
                                const NotificationPage(),
                              );
                              _fetchUnreadNotifCount();
                            },
                          ),
                          const SizedBox(height: 8),
                          _navItem(
                            icon: Icons.settings_rounded,
                            label: 'Settings',
                            pageKey: 'settings',
                            color: const Color(0xFF6B7280),
                            onTap: () =>
                                _navigate('settings', const ProfSettingsPage()),
                          ),
                          const SizedBox(height: 16),
                          Container(height: 1, color: dayungBorder(context)),
                          const SizedBox(height: 16),
                          _navItem(
                            icon: Icons.logout_rounded,
                            label: 'Logout',
                            pageKey: 'logout',
                            color: const Color(0xFFEF4444),
                            onTap: () => showLogoutDialog(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Version footer
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dayungSurface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dayungBorder(context)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: const Color(0xFF6B7280).withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      color: const Color(0xFF6B7280).withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required String pageKey,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final isActive = _currentPage == pageKey;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: color.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isActive ? color : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  color: isActive ? Colors.white : color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive ? color : const Color(0xFF374151),
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
