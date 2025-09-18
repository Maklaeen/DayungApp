import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContributionHistory extends StatefulWidget {
  const ContributionHistory({super.key});

  @override
  State<ContributionHistory> createState() => _ContributionHistoryState();
}

class _ContributionHistoryState extends State<ContributionHistory> {
  final bool _showNavBar = true;
  String? selectedDayungUnit;

  @override
  void initState() {
    super.initState();
    _loadDayungUnit();
  }

  Future<void> _loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final unit = prefs.getString('selectedDayungUnit');
    setState(() => selectedDayungUnit = unit ?? 'Dayung');
  }

  @override
  Widget build(BuildContext context) {
    final contributions = [
      {'date': 'February 17, 2025', 'amount': '₱ 200'},
      {'date': 'March 20, 2024', 'amount': '₱ 200'},
      {'date': 'June 30, 2023', 'amount': '₱ 200'},
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedDayungUnit ?? 'Dayung',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationPage(),
                                ),
                              );
                            },
                            child: Stack(
                              children: [
                                Icon(
                                  Icons.notifications_none,
                                  color: Colors.orange[700],
                                  size: 36,
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    child: const Text(
                                      '1',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProfilePage(),
                                ),
                              );
                            },
                            child: const CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.blue,
                              child: Icon(
                                Icons.account_circle,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 1),

                // Title
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Contribution History',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ),

                // Contribution List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: contributions.length,
                    itemBuilder: (context, index) {
                      final item = contributions[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['date']!,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item['amount']!,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Contribution Payment',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: IgnorePointer(
                ignoring: !_showNavBar,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _showNavBar ? 1.0 : 0.0,
                  child: Container(
                    height: 70,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _navBarItem(
                          icon: Icons.home,
                          label: 'Home',
                          selected: false,
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MemberDashboard(),
                              ),
                            );
                          },
                        ),
                        _navBarItem(
                          icon: FontAwesomeIcons.globe,
                          label: 'Contributions',
                          selected: true,
                          onTap: () {},
                        ),
                        _navBarItem(
                          icon: Icons.receipt_long,
                          label: 'Claims',
                          selected: false,
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ClaimsPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBarItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.blue[800] : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: selected ? Colors.blue[800] : Colors.black,
            size: 30,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.blue[800] : Colors.black,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
