import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceTrackerPage extends StatefulWidget {
  final int dayungUnitId;
  const ServiceTrackerPage({super.key, required this.dayungUnitId});

  @override
  State<ServiceTrackerPage> createState() => _ServiceTrackerPageState();
}

class _ServiceTrackerPageState extends State<ServiceTrackerPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _notices = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    final sb = Supabase.instance.client;
    try {
      // Fetch death notices
      final notices = await sb
          .from('death_notices')
          .select('id, name, date_of_death')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('date_of_death', ascending: false);

      // For each notice, fetch checklist
      List<Map<String, dynamic>> data = [];
      for (final n in notices) {
        final checklist = await sb
            .from('service_checklists')
            .select('service_name, is_done')
            .eq('death_notice_id', n['id']);
        data.add({'notice': n, 'checklist': checklist});
      }
      setState(() {
        _notices = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading service tracker: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Service Tracker')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notices.length,
              itemBuilder: (context, i) {
                final n = _notices[i]['notice'];
                final checklist = _notices[i]['checklist'] as List;
                return Card(
                  margin: const EdgeInsets.only(bottom: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.black26),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n['name'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          n['date_of_death'] ?? '',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Service Checklist:',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...checklist.map((c) {
                          final done = c['is_done'] == true;
                          return Row(
                            children: [
                              Icon(
                                done ? Icons.check : Icons.close,
                                color: done ? Colors.black : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                c['service_name'],
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  decoration: done
                                      ? TextDecoration.none
                                      : TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          );
                        }),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: () {
                              // TODO: Open map for this notice
                            },
                            child: const Text('Map'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
