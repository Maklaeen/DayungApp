import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:capstone_app/Auth/login.dart';

class SelectDayungPage extends StatelessWidget {
  final List<String> dayungUnits = [
    'Matina Mortuary',
    'Buhangin Mortuary',
    'Agdao Mortuary',
  ];

  SelectDayungPage({super.key});

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => Login()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              // child: Align(
              //   alignment: Alignment.centerRight,
              //   child: TextButton.icon(
              //     onPressed: () => _logout(context),
              //     icon: const Icon(Icons.logout, color: Colors.red),
              //     label: const Text(
              //       'Logout',
              //       style: TextStyle(color: Colors.red),
              //     ),
              //   ),
              // ),
            ),

            const SizedBox(height: 16),

            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/dayunghandlogo.jpeg',
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            const Text(
              'Choose a dayung profile to continue',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'Montserrat',
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: dayungUnits.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, dayungUnits[index]),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F3FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.house, color: Colors.blue, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              dayungUnits[index],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Montserrat',
                              ),
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
    );
  }
}
