import 'dart:convert';
import 'package:capstone_app/Auth/logout.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/Secretary/dashboard.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/settings/profsettings.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SidebarLayout extends StatefulWidget {
  final Widget child;
  final String currentPage;

  const SidebarLayout({
    super.key,
    required this.child,
    required this.currentPage,
  });

  @override
  State<SidebarLayout> createState() => _SidebarLayoutState();
}

class _SidebarLayoutState extends State<SidebarLayout> {
  String _fullName = '';
  String _selectedDayungUnit = 'Dayung Unit';
  int _unreadNotifCount = 0;
  String _currentPage = 'dashboard';
  Widget _currentContent = const SecretaryDashboardPage();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.currentPage;
    _currentContent = widget.child;
    _loadUserInfo();
    _fetchUnreadNotifCount();
  }

  void _navigateToPage(String pageName, Widget pageWidget) {
    setState(() {
      _currentPage = pageName;
      _currentContent = pageWidget;
    });
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('secretaryFullName') ?? 'Secretary';
    String dayungLabelRaw = prefs.getString('selectedDayungUnit') ?? 'Dayung Unit';
    
    String resolvedLabel = dayungLabelRaw;
    String? jsonFull = prefs.getString('selectedDayungUnitData');
    Map<String, dynamic>? parsed;
    
    try {
      if (jsonFull != null) {
        parsed = jsonDecode(jsonFull);
      }
    } catch (_) {}
    
    if (parsed == null &&
        dayungLabelRaw.trim().startsWith('{') &&
        dayungLabelRaw.contains('"name"')) {
      try {
        parsed = jsonDecode(dayungLabelRaw);
      } catch (_) {}
    }
    
    if (parsed != null) {
      if ((parsed['name'] ?? '').toString().trim().isNotEmpty) {
        resolvedLabel = parsed['name'].toString();
      }
    }
    
    if (mounted) {
      setState(() {
        _fullName = name;
        _selectedDayungUnit = resolvedLabel;
      });
    }
  }

  Future<void> _fetchUnreadNotifCount() async {
    // Simplified notification count - you can expand this based on your needs
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    
    if (uid == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }
    
    try {
      // This is a simplified version - adjust based on your notification logic
      final rows = await sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .isFilter('read_at', null);
      
      if (mounted) setState(() => _unreadNotifCount = (rows as List).length);
    } catch (_) {
      if (mounted) setState(() => _unreadNotifCount = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isDesktop = width > 1024;

    if (isDesktop) {
      // Desktop layout with persistent sidebar
      return Scaffold(
        backgroundColor: dayungPageBackground(context),
        body: Row(
          children: [
            // Fixed Sidebar
            SizedBox(
              width: 280,
              child: _buildSidebar(),
            ),
            // Main Content - no navigation, just content switching
            Expanded(child: _currentContent),
          ],
        ),
      );
    } else {
      // Mobile layout - return child as-is (let individual pages handle their own drawer)
      return widget.child;
    }
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
            // Header Section
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: dayungSectionCardDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                              _fullName.isEmpty ? 'Secretary' : _fullName,
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
                ],
              ),
            ),
            // Navigation Section
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
                          _modernNavItem(
                            context,
                            icon: Icons.dashboard_rounded,
                            label: 'Dashboard',
                            color: const Color(0xFF3B82F6),
                            isActive: _currentPage == 'dashboard',
                            onTap: () {
                              _navigateToPage('dashboard', const SecretaryDashboardPage());
                            },
                          ),
                          const SizedBox(height: 8),
                          _modernNavItem(
                            context,
                            icon: Icons.account_circle_rounded,
                            label: 'Profile',
                            color: const Color(0xFF10B981),
                            isActive: _currentPage == 'profile',
                            onTap: () {
                              _navigateToPage('profile', const ProfilePage());
                            },
                          ),
                          const SizedBox(height: 8),
                          _modernNavItem(
                            context,
                            icon: Icons.people_rounded,
                            label: 'Beneficiaries',
                            color: const Color(0xFF8B5CF6),
                            isActive: _currentPage == 'beneficiaries',
                            onTap: () {
                              _navigateToPage('beneficiaries', const BeneficiaryPage());
                            },
                          ),
                          const SizedBox(height: 8),
                          _modernNavItem(
                            context,
                            icon: Icons.notifications_rounded,
                            label: 'Notifications',
                            color: const Color(0xFFF59E0B),
                            badgeCount: _unreadNotifCount,
                            isActive: _currentPage == 'notifications',
                            onTap: () {
                              _navigateToPage('notifications', const NotificationPage());
                              _fetchUnreadNotifCount();
                            },
                          ),
                          const SizedBox(height: 8),
                          _modernNavItem(
                            context,
                            icon: Icons.settings_rounded,
                            label: 'Settings',
                            color: const Color(0xFF6B7280),
                            isActive: _currentPage == 'settings',
                            onTap: () {
                              _navigateToPage('settings', const ProfSettingsPage());
                            },
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 1,
                            color: dayungBorder(context),
                          ),
                          const SizedBox(height: 16),
                          _modernNavItem(
                            context,
                            icon: Icons.logout_rounded,
                            label: 'Logout',
                            color: const Color(0xFFEF4444),
                            onTap: () async {
                              await showLogoutDialog(context);
                            },
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

  Widget _modernNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isActive = false,
    int badgeCount = 0,
  }) {
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
            color: isActive ? color.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: color.withValues(alpha: 0.2), width: 1)
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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