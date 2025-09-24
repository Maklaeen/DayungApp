import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';

class SelectDayungPage extends StatefulWidget {
  const SelectDayungPage({super.key});

  @override
  State<SelectDayungPage> createState() => _SelectDayungPageState();
}

class _SelectDayungPageState extends State<SelectDayungPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _dayung;

  @override
  void initState() {
    super.initState();
    _fetchJoinedDayung();
  }

  Future<void> _fetchJoinedDayung() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final user = _sb.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _dayung = null;
        _error = 'Please log in.';
      });
      return;
    }

    try {
      // 1) Get the user’s assigned dayung_unit_id
      final me = await _sb
          .from('users')
          .select('dayung_unit_id')
          .eq('id', user.id)
          .maybeSingle();

      final int? dayungId = me != null ? me['dayung_unit_id'] as int? : null;

      if (dayungId == null) {
        setState(() {
          _loading = false;
          _dayung = null;
        });
        return;
      }

      // 2) Load the dayung details
      final d = await _sb
          .from('dayung_units')
          .select('id, name, barangay, city, province, latitude, longitude')
          .eq('id', dayungId)
          .maybeSingle();

      setState(() {
        _dayung = d != null ? Map<String, dynamic>.from(d) : null;
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message.isEmpty
            ? 'Failed to load dayung (RLS/policy?)'
            : e.message;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Unexpected error loading your dayung.';
      });
    }
  }

  String _address(Map<String, dynamic> d) {
    final parts = <String>[
      if ((d['barangay'] ?? '').toString().isNotEmpty) d['barangay'],
      if ((d['city'] ?? '').toString().isNotEmpty) d['city'],
      if ((d['province'] ?? '').toString().isNotEmpty) d['province'],
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Your Dayung')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _fetchJoinedDayung)
            : RefreshIndicator(
                onRefresh: _fetchJoinedDayung,
                child: _dayung == null
                    ? _EmptyState(
                        onFind: () async {
                          final selected = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DayungSuggestionsPage(),
                            ),
                          );
                          // After returning, refresh assignment (approval may happen later)
                          await _fetchJoinedDayung();
                          if (selected != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Application submitted. Awaiting approval.',
                                ),
                              ),
                            );
                          }
                        },
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        child: Icon(Icons.home),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _dayung!['name'] ?? 'Dayung',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _address(_dayung!),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.check_circle),
                                        label: const Text('Use this Dayung'),
                                        onPressed: () {
                                          Navigator.pop(context, _dayung);
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                      TextButton.icon(
                                        icon: const Icon(Icons.find_in_page),
                                        label: const Text('Find another'),
                                        onPressed: () async {
                                          final selected = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const DayungSuggestionsPage(),
                                            ),
                                          );
                                          // User may apply to another; refresh assignment
                                          await _fetchJoinedDayung();
                                          if (selected != null) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Application submitted. Awaiting approval.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onFind});
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 40),
        Icon(
          Icons.search,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'You have not joined any Dayung yet.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Find your Dayung and submit an application. Once approved, it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.explore),
              label: const Text('Find a Dayung'),
              onPressed: onFind,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
