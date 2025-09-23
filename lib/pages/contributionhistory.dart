import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:provider/provider.dart';
import 'package:capstone_app/settings/dayung_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class ContributionHistory extends StatefulWidget {
  const ContributionHistory({super.key});

  @override
  State<ContributionHistory> createState() => _ContributionHistoryState();
}

class _ContributionHistoryState extends State<ContributionHistory> {
  String? selectedDayungUnit;
  String? _profileUrl;
  Map<String, dynamic>? _selectedDayungUnitObj;

  @override
  void initState() {
    super.initState();
    _loadDayungUnit();
    _loadProfileImage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadDayungUnit();
  }

  Future<void> _loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson != null) {
      final unit = jsonDecode(unitJson);
      setState(() {
        selectedDayungUnit = unit['name'];
        _selectedDayungUnitObj = unit;
      });
    } else {
      setState(() {
        selectedDayungUnit = 'Dayung';
        _selectedDayungUnitObj = null;
      });
    }
  }

  Future<void> _loadProfileImage() async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser != null) {
      final response = await supabase
          .from('users')
          .select('profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();
      setState(() {
        _profileUrl = response?['profile_url'] as String?;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final dayungName = _selectedDayungUnitObj?['name'] ?? 'Dayung';
    final barangay = _selectedDayungUnitObj?['barangay'];
    final city = _selectedDayungUnitObj?['city'];
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
                      AutoSizeText(
                        dayungName,
                        style: TextStyle(
                          fontSize: isWide ? 36 : 28,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Montserrat',
                        ),
                        maxLines: 1,
                        minFontSize: 20,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (barangay != null)
                        Text(
                          '$barangay${city != null ? ', $city' : ''}',
                          style: TextStyle(
                            fontSize: isWide ? 16 : 13,
                            color: Colors.black54,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.notifications_none,
                              color: Colors.orange[700],
                              size: isWide ? 36 : 28,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProfilePage(),
                                ),
                              ).then((_) => _loadProfileImage());
                            },
                            child: CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.blue,
                              backgroundImage:
                                  (_profileUrl != null &&
                                      _profileUrl!.isNotEmpty)
                                  ? NetworkImage(_profileUrl!)
                                  : null,
                              child:
                                  (_profileUrl == null || _profileUrl!.isEmpty)
                                  ? const Icon(
                                      Icons.account_circle,
                                      size: 36,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(thickness: 1, height: 24, color: Colors.grey),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Contribution History',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: isWide ? 20 : 16,
                        color: Colors.black87,
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
