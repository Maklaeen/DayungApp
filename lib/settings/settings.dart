import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/settings/dayung_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_size_text/auto_size_text.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _currentDayung = '—';

  final List<String> selectedFilters = const [
    'Low fee',
    'Within Davao',
    'Open for all',
    '₱25,000',
  ];

  final Map<String, List<String>> recommended = const {
    'Buhangin Dayung': [
      'Low fee',
      'Open for all',
      'Within Davao City',
      '₱25,900',
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentDayung();
  }

  Future<void> _loadCurrentDayung() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentDayung = prefs.getString('selectedDayungUnit') ?? '—';
    });
  }

  Future<void> _changeDayung() async {
    final newUnit = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => SelectDayungPage()),
    );
    if (newUnit != null) {
      context.read<DayungUnitProvider>().setDayungUnit(newUnit);
      setState(() => _currentDayung = newUnit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    final headerStyle = TextStyle(
      fontSize: isWide ? 30 : 22,
      fontWeight: FontWeight.bold,
      fontFamily: 'Montserrat',
    );
    final sectionTitleStyle = TextStyle(
      fontSize: isWide ? 20 : 16,
      fontWeight: FontWeight.w600,
      fontFamily: 'Montserrat',
    );
    final bodyTextStyle = TextStyle(
      fontSize: isWide ? 18 : 14,
      fontFamily: 'OpenSans',
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 32),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                  AutoSizeText(
                    'Profile settings',
                    style: headerStyle,
                    maxLines: 1,
                    minFontSize: 16,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  title: AutoSizeText(
                    'Current Dayung',
                    style: sectionTitleStyle,
                    maxLines: 1,
                    minFontSize: 12,
                  ),
                  subtitle: AutoSizeText(
                    _currentDayung,
                    style: bodyTextStyle.copyWith(color: Colors.blue),
                    maxLines: 1,
                    minFontSize: 10,
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _changeDayung,
                    child: Text(
                      'Change',
                      style: TextStyle(
                        fontSize: isWide ? 16 : 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          AutoSizeText(
                            'Filters',
                            style: sectionTitleStyle,
                            maxLines: 1,
                            minFontSize: 12,
                          ),
                          TextButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            label: Text(
                              'Edit',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: isWide ? 16 : 13,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      AutoSizeText(
                        'Selected tags:',
                        style: bodyTextStyle,
                        maxLines: 1,
                        minFontSize: 10,
                      ),
                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: selectedFilters.map((tag) {
                          return Chip(
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            label: Text(
                              tag,
                              style: TextStyle(fontSize: isWide ? 16 : 13),
                            ),
                            backgroundColor: Colors.grey.shade200,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              AutoSizeText(
                'Recommended for you',
                style: sectionTitleStyle,
                maxLines: 1,
                minFontSize: 12,
              ),
              const SizedBox(height: 12),

              Expanded(
                child: ListView.builder(
                  itemCount: recommended.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, idx) {
                    final key = recommended.keys.elementAt(idx);
                    final tags = recommended[key]!;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AutoSizeText(
                              key,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 15,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Montserrat',
                              ),
                              maxLines: 1,
                              minFontSize: 12,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: tags.map((t) {
                                return Chip(
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  label: Text(
                                    t,
                                    style: TextStyle(
                                      fontSize: isWide ? 16 : 13,
                                    ),
                                  ),
                                  backgroundColor: Colors.blue.shade50,
                                );
                              }).toList(),
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
      ),
    );
  }
}
