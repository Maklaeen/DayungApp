import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentReleaseHistoryPage extends StatefulWidget {
  final int dayungUnitId;

  const PaymentReleaseHistoryPage({super.key, required this.dayungUnitId});

  @override
  State<PaymentReleaseHistoryPage> createState() =>
      _PaymentReleaseHistoryPageState();
}

class _PaymentReleaseHistoryPageState extends State<PaymentReleaseHistoryPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  double _totalReleased = 0;
  List<Map<String, dynamic>> _releases = [];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final paymentRows = List<Map<String, dynamic>>.from(
        await sb
            .from('payments')
            .select('id, amount, claim_id, userdeceased, deceased_name')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('status', 'paid')
            .eq('is_claimed', true),
      );

      final deceasedUserIds = paymentRows
          .map((row) => '${row['userdeceased'] ?? ''}'.trim())
          .where((id) => id.isNotEmpty && id != 'null')
          .toSet()
          .toList();

      final claimsByUserId = <String, Map<String, dynamic>>{};
      if (deceasedUserIds.isNotEmpty) {
        final claimRows = await sb
            .from('claims')
            .select('id, claimedmoney_date, user_id, dayung_unit_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .inFilter('user_id', deceasedUserIds);
        for (final claim in List<Map<String, dynamic>>.from(claimRows)) {
          final userId = '${claim['user_id'] ?? ''}'.trim();
          final existing = claimsByUserId[userId];
          final existingDate = DateTime.tryParse(
            '${existing?['claimedmoney_date'] ?? ''}',
          );
          final claimDate = DateTime.tryParse(
            '${claim['claimedmoney_date'] ?? ''}',
          );
          if (existing == null ||
              (claimDate != null &&
                  (existingDate == null || claimDate.isAfter(existingDate)))) {
            claimsByUserId[userId] = claim;
          }
        }
      }

      double total = 0;
      final releasesByUser = <String, Map<String, dynamic>>{};
      for (final payment in paymentRows) {
        final amount = _asDouble(payment['amount']);
        final userDeceased = '${payment['userdeceased'] ?? ''}'.trim();
        final claim = claimsByUserId[userDeceased];
        final key = userDeceased.isEmpty ? 'Unknown user' : userDeceased;
        total += amount;
        final release = releasesByUser.putIfAbsent(
          key,
          () => {
            'amount': 0.0,
            'date': claim?['claimedmoney_date'],
            'deceased_name': payment['deceased_name'] ?? 'Member',
          },
        );
        release['amount'] = (release['amount'] as double) + amount;

        final currentDate = DateTime.tryParse('${release['date'] ?? ''}');
        final paymentDate = DateTime.tryParse(
          '${claim?['claimedmoney_date'] ?? ''}',
        );
        if (currentDate == null ||
            (paymentDate != null && paymentDate.isAfter(currentDate))) {
          release['date'] = claim?['claimedmoney_date'];
        }
      }

      final releases = releasesByUser.entries
          .map(
            (entry) => {
              'userdeceased': entry.key,
              'deceased_name': entry.value['deceased_name'],
              'amount': entry.value['amount'],
              'date': entry.value['date'],
            },
          )
          .toList();

      releases.sort((a, b) {
        final aDate = DateTime.tryParse('${a['date'] ?? ''}');
        final bDate = DateTime.tryParse('${b['date'] ?? ''}');
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _totalReleased = total;
        _releases = releases;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Unable to load payment release history: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load payment release history.';
        _releases = [];
        _totalReleased = 0;
        _loading = false;
      });
    }
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (date == null) return 'Release date unavailable';
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  String _formatCurrency(double value) => '₱${value.toStringAsFixed(2)}';

  List<Map<String, dynamic>> get _visibleReleases {
    final query = _searchQuery.trim().toLowerCase();
    final visible = _releases.where((release) {
      if (query.isEmpty) return true;
      final name = '${release['deceased_name'] ?? ''}'.toLowerCase();
      final date = _formatDate(release['date']).toLowerCase();
      return name.contains(query) || date.contains(query);
    }).toList();

    visible.sort((a, b) {
      final aDate = DateTime.tryParse('${a['date'] ?? ''}');
      final bDate = DateTime.tryParse('${b['date'] ?? ''}');
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final comparison = bDate.compareTo(aDate);
      return _newestFirst ? comparison : -comparison;
    });
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      appBar: AppBar(
        title: const Text('Payment Release History'),
        backgroundColor: dayungPageBackground(context),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Released',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _loading ? '—' : _formatCurrency(_totalReleased),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_releases.length} userdeceased${_releases.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search name, date, or time',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<bool>(
              initialValue: _newestFirst,
              decoration: InputDecoration(
                labelText: 'Sort releases',
                prefixIcon: const Icon(Icons.sort_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: const [
                DropdownMenuItem(value: true, child: Text('New to old')),
                DropdownMenuItem(value: false, child: Text('Old to new')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _newestFirst = value);
              },
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (_visibleReleases.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No matching releases found.')),
              )
            else
              ..._visibleReleases.map(
                (release) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: dayungBorder(context)),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE6FFFA),
                      child: Icon(
                        Icons.check_rounded,
                        color: Color(0xFF0D9488),
                      ),
                    ),
                    title: Text(
                      '${release['deceased_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(_formatDate(release['date'])),
                    trailing: Text(
                      _formatCurrency(release['amount'] as double),
                      style: const TextStyle(
                        color: Color(0xFF0D9488),
                        fontWeight: FontWeight.w800,
                      ),
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
