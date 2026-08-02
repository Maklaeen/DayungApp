import 'dart:convert';
import 'package:capstone_app/Auth/logout.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/pages/membership_agreement_page.dart';
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

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _fetchUnreadNotifCount();
  }

  @override
  void didUpdateWidget(GlobalSidebarWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dashboard.runtimeType != widget.dashboard.runtimeType) {
      setState(() => _currentPage = 'dashboard');
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

  void _navigate(String pageKey) {
    setState(() => _currentPage = pageKey);
  }

  Widget _buildCurrentContent(bool isDesktop) {
    switch (_currentPage) {
      case 'profile':
        return ProfilePage(
          onBack: () => _navigate('dashboard'),
          showBackButton: !isDesktop,
        );
      case 'beneficiaries':
        return BeneficiaryPage(
          onBack: () => _navigate('dashboard'),
          showBackButton: !isDesktop,
        );
      case 'notifications':
        return NotificationPage(
          onBack: () => _navigate('dashboard'),
          showBackButton: !isDesktop,
        );
      case 'settings':
        return ProfSettingsPage(
          onBack: () => _navigate('dashboard'),
          showBackButton: !isDesktop,
        );
      case 'membershipAgreement':
        return MembershipAgreementPage(
          onBack: () => _navigate('dashboard'),
          showBackButton: !isDesktop,
        );
      case 'dashboard':
      default:
        return widget.dashboard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1024;

    return PopScope<Object?>(
      canPop: _currentPage == 'dashboard',
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _currentPage != 'dashboard') {
          _navigate('dashboard');
        }
      },
      child: Builder(
        builder: (context) {
          if (!isDesktop) {
            return Scaffold(
              backgroundColor: dayungPageBackground(context),
              drawer: _buildMobileDrawer(context),
              body: _buildCurrentContent(false),
            );
          }

          return Scaffold(
            backgroundColor: dayungPageBackground(context),
            body: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: DashboardSidebar(
                    fullName: _fullName,
                    roleName: _roleName,
                    selectedDayungUnit: _selectedDayungUnit,
                    unreadNotifCount: _unreadNotifCount,
                    currentPage: _currentPage,
                    onDashboardTap: () => _navigate('dashboard'),
                    onProfileTap: () => _navigate('profile'),
                    onBeneficiariesTap: () => _navigate('beneficiaries'),
                    onNotificationsTap: () {
                      _navigate('notifications');
                      _fetchUnreadNotifCount();
                    },
                    onSettingsTap: () => _navigate('settings'),
                    onMembershipAgreementTap: () =>
                        _navigate('membershipAgreement'),
                    onLogoutTap: () => showLogoutDialog(context),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: KeyedSubtree(
                      key: ValueKey<String>(_currentPage),
                      child: _buildCurrentContent(true),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: dayungPageBackground(context),
      child: Column(
        children: [
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
                        _SidebarButton(
                          icon: Icons.dashboard_rounded,
                          label: 'Dashboard',
                          color: const Color(0xFF3B82F6),
                          selected: _currentPage == 'dashboard',
                          onTap: () {
                            Navigator.pop(context);
                            _navigate('dashboard');
                          },
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.account_circle_rounded,
                          label: 'Profile',
                          color: const Color(0xFF10B981),
                          selected: _currentPage == 'profile',
                          onTap: () {
                            Navigator.pop(context);
                            _navigate('profile');
                          },
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.people_rounded,
                          label: 'Beneficiaries',
                          color: const Color(0xFF8B5CF6),
                          selected: _currentPage == 'beneficiaries',
                          onTap: () {
                            Navigator.pop(context);
                            _navigate('beneficiaries');
                          },
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.notifications_rounded,
                          label: 'Notifications',
                          color: const Color(0xFFF59E0B),
                          selected: _currentPage == 'notifications',
                          badgeCount: _unreadNotifCount,
                          onTap: () {
                            Navigator.pop(context);
                            _navigate('notifications');
                            _fetchUnreadNotifCount();
                          },
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          color: const Color(0xFF6B7280),
                          selected: _currentPage == 'settings',
                          onTap: () {
                            Navigator.pop(context);
                            _navigate('settings');
                          },
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.description_rounded,
                          label: 'Membership Agreement',
                          color: const Color(0xFF2563EB),
                          selected: _currentPage == 'membershipAgreement',
                          onTap: () {
                            Navigator.pop(context);
                            _navigate('membershipAgreement');
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(height: 1, color: dayungBorder(context)),
                        const SizedBox(height: 16),
                        _SidebarButton(
                          icon: Icons.logout_rounded,
                          label: 'Logout',
                          color: const Color(0xFFEF4444),
                          selected: false,
                          onTap: () {
                            Navigator.pop(context);
                            showLogoutDialog(context);
                          },
                        ),
                      ],
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

class DashboardSidebar extends StatelessWidget {
  final String fullName;
  final String roleName;
  final String selectedDayungUnit;
  final int unreadNotifCount;
  final String currentPage;
  final VoidCallback onDashboardTap;
  final VoidCallback onProfileTap;
  final VoidCallback onBeneficiariesTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onMembershipAgreementTap;
  final VoidCallback onLogoutTap;

  const DashboardSidebar({
    super.key,
    required this.fullName,
    required this.roleName,
    required this.selectedDayungUnit,
    required this.unreadNotifCount,
    required this.currentPage,
    required this.onDashboardTap,
    required this.onProfileTap,
    required this.onBeneficiariesTap,
    required this.onNotificationsTap,
    required this.onSettingsTap,
    required this.onMembershipAgreementTap,
    required this.onLogoutTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = fullName.isEmpty ? roleName : fullName;
    return Container(
      color: dayungPageBackground(context),
      child: Column(
        children: [
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
                        displayName,
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
                        selectedDayungUnit,
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
                        _SidebarButton(
                          icon: Icons.dashboard_rounded,
                          label: 'Dashboard',
                          color: const Color(0xFF3B82F6),
                          selected: currentPage == 'dashboard',
                          onTap: onDashboardTap,
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.account_circle_rounded,
                          label: 'Profile',
                          color: const Color(0xFF10B981),
                          selected: currentPage == 'profile',
                          onTap: onProfileTap,
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.people_rounded,
                          label: 'Beneficiaries',
                          color: const Color(0xFF8B5CF6),
                          selected: currentPage == 'beneficiaries',
                          onTap: onBeneficiariesTap,
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.notifications_rounded,
                          label: 'Notifications',
                          color: const Color(0xFFF59E0B),
                          selected: currentPage == 'notifications',
                          badgeCount: unreadNotifCount,
                          onTap: onNotificationsTap,
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          color: const Color(0xFF6B7280),
                          selected: currentPage == 'settings',
                          onTap: onSettingsTap,
                        ),
                        const SizedBox(height: 8),
                        _SidebarButton(
                          icon: Icons.description_rounded,
                          label: 'Membership Agreement',
                          color: const Color(0xFF2563EB),
                          selected: currentPage == 'membershipAgreement',
                          onTap: onMembershipAgreementTap,
                        ),
                        const SizedBox(height: 16),
                        Container(height: 1, color: dayungBorder(context)),
                        const SizedBox(height: 16),
                        _SidebarButton(
                          icon: Icons.logout_rounded,
                          label: 'Logout',
                          color: const Color(0xFFEF4444),
                          selected: false,
                          onTap: onLogoutTap,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                  'Version 1.5.0',
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
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
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
            color: selected
                ? color.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(color: color.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selected ? color : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected
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
                  color: selected ? Colors.white : color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? color : const Color(0xFF374151),
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
