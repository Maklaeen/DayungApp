import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectDayungPage extends StatefulWidget {
  const SelectDayungPage({super.key});

  @override
  State<SelectDayungPage> createState() => _SelectDayungPageState();
}

class _SelectDayungPageState extends State<SelectDayungPage> {
  List<Map<String, dynamic>> _dayungUnits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDayungUnits();
  }

  Future<void> _fetchDayungUnits() async {
    final response = await Supabase.instance.client
        .from('dayung_units')
        .select('id, name, barangay, city, province')
        .order('name');
    setState(() {
      _dayungUnits = List<Map<String, dynamic>>.from(response);
      _loading = false;
    });
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _dayungUnits.length,
                      itemBuilder: (context, index) {
                        final unit = _dayungUnits[index];
                        return GestureDetector(
                          onTap: () => Navigator.pop(context, unit),
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
                                const Icon(
                                  Icons.house,
                                  color: Colors.blue,
                                  size: 32,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        unit['name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                      if (unit['barangay'] != null)
                                        Text(
                                          unit['barangay'],
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black54,
                                            fontFamily: 'OpenSans',
                                          ),
                                        ),
                                      if (unit['city'] != null)
                                        Text(
                                          unit['city'],
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.black45,
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
                      },
                    ),
            ),
            // Add this skip button
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0, top: 8.0),
              child: TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text(
                  'Skip for now',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blue,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
