import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DayungSuggestionsPage extends StatefulWidget {
  const DayungSuggestionsPage({super.key});

  @override
  State<DayungSuggestionsPage> createState() => _DayungSuggestionsPageState();
}

class _DayungSuggestionsPageState extends State<DayungSuggestionsPage> {
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _allDayungs = [];
  bool _loading = false;
  String _query = '';
  List<String> _selectedTags = [];

  // Example tag options (customize as needed)
  final List<String> _feeRanges = ['Free', '₱1 - ₱100', '₱101 - ₱500', '₱501+'];
  final List<String> _paymentMethods = [
    'GCash',
    'Bank Transfer',
    'Cash',
    'Any',
  ];
  final List<String> _locations = ['Cebu', 'Davao', 'Manila', 'Anywhere'];
  final List<String> _fundSupports = ['₱0 - ₱500', '₱501 - ₱1000', '₱1001+'];

  @override
  void initState() {
    super.initState();
    _fetchSuggestions();
  }

  Future<void> _fetchSuggestions() async {
    setState(() => _loading = true);

    try {
      final query = _query.isEmpty
          ? 'Find the best Dayung unit for me'
          : _query;

      // 1. Get embedding for user query
      final embedRes = await _sb.functions.invoke(
        'embed',
        body: {'input': query},
      );
      final embedding = (embedRes.data['embedding'] as List)
          .map((e) => (e as num).toDouble())
          .toList();

      // 2. Call the dayung_search RPC with embedding and tags
      final rpcRes = await _sb.rpc(
        'dayung_search',
        params: {
          'query_embedding': embedding,
          'in_tags': _selectedTags.isEmpty ? null : _selectedTags,
          'in_limit': 20,
        },
      );

      setState(() {
        _allDayungs = List<Map<String, dynamic>>.from(rpcRes);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching suggestions: $e')));
    }
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
    _fetchSuggestions();
  }

  Widget _buildTagChips(List<String> tags, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8,
          children: tags.map((tag) {
            final selected = _selectedTags.contains(tag);
            return ChoiceChip(
              label: Text(tag),
              selected: selected,
              onSelected: (_) => _toggleTag(tag),
              selectedColor: Colors.blue.shade100,
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a Dayung')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchSuggestions,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Search box
                  TextField(
                    decoration: InputDecoration(
                      hintText:
                          'Describe your ideal Dayung or search by name/location',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      setState(() => _query = v);
                      _fetchSuggestions();
                    },
                  ),
                  const SizedBox(height: 16),

                  // Tag filters
                  _buildTagChips(_feeRanges, 'Fee Range'),
                  _buildTagChips(_paymentMethods, 'Payment Method'),
                  _buildTagChips(_locations, 'Location'),
                  _buildTagChips(_fundSupports, 'Fund Support'),

                  const SizedBox(height: 12),

                  if (_allDayungs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'No dayung units found.\nTry changing your search or filters.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ..._allDayungs.map((d) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(d['name'] ?? 'Unnamed Unit'),
                        subtitle: Text(
                          [
                                if (d['barangay'] != null) d['barangay'],
                                if (d['city'] != null) d['city'],
                                if (d['province'] != null) d['province'],
                              ]
                              .where(
                                (e) => e != null && e.toString().isNotEmpty,
                              )
                              .join(', '),
                        ),
                        trailing: d['tags'] != null
                            ? Wrap(
                                spacing: 4,
                                children: (d['tags'] as List)
                                    .map(
                                      (tag) => Chip(
                                        label: Text(tag.toString()),
                                        backgroundColor: Colors.grey.shade200,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    )
                                    .toList(),
                              )
                            : null,
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(d['name'] ?? 'Dayung Unit'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (d['description'] != null)
                                    Text(d['description']),
                                  const SizedBox(height: 8),
                                  if (d['rules'] != null)
                                    Text('Rules: ${d['rules']}'),
                                  if (d['tags'] != null)
                                    Wrap(
                                      spacing: 4,
                                      children: (d['tags'] as List)
                                          .map(
                                            (tag) => Chip(
                                              label: Text(tag.toString()),
                                              backgroundColor:
                                                  Colors.blue.shade50,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
