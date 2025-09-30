import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF111827);
const Color kSubtleText = Color(0xFF6B7280);
const Color kCard = Colors.white;

class ManageFundPage extends StatefulWidget {
  final int dayungUnitId;
  const ManageFundPage({super.key, required this.dayungUnitId});

  @override
  State<ManageFundPage> createState() => _ManageFundPageState();
}

class _ManageFundPageState extends State<ManageFundPage> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  // Aggregated rows per death notice
  List<Map<String, dynamic>> _funds = [];

  // UI state
  String _search = '';
  String _statusFilter = 'all'; // all | collecting | completed
  String _sort = 'date_desc'; // date_desc | date_asc | progress_desc

  double _totalPaid = 0.0;
  double _totalGoal = 0.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await sb
          .from('payments')
          .select(
            'death_notice_id, amount, status, paid_at, notice:death_notices(id,name,date_of_death)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId);

      final rows = List<Map<String, dynamic>>.from(res);

      final byNotice = <int, Map<String, dynamic>>{};
      for (final r in rows) {
        final dnId = r['death_notice_id'] as int?;
        if (dnId == null) continue;

        final notice = (r['notice'] as Map?)?.cast<String, dynamic>();
        final name = (notice?['name'] ?? 'Death Notice').toString();
        final dateStr = (notice?['date_of_death'] ?? '').toString();

        final amt = (r['amount'] is num)
            ? (r['amount'] as num).toDouble()
            : double.tryParse('${r['amount']}') ?? 0.0;
        final status = (r['status'] ?? '').toString().toLowerCase();

        final bucket = byNotice.putIfAbsent(dnId, () {
          return {
            'id': dnId,
            'name': name,
            'paid': 0.0,
            'goal': 0.0,
            'deadline': dateStr,
            'status': '', // computed later
            'progress': 0.0, // computed later
          };
        });

        bucket['goal'] = (bucket['goal'] as double) + amt;
        if (status == 'paid') {
          bucket['paid'] = (bucket['paid'] as double) + amt;
        }

        // Keep latest label fields
        bucket['name'] = name;
        bucket['deadline'] = dateStr;
      }

      final list = byNotice.values.toList();
      double totalPaid = 0, totalGoal = 0;

      for (final f in list) {
        final paid = (f['paid'] as double);
        final goal = (f['goal'] as double);
        final p = goal <= 0 ? 0.0 : (paid / goal).clamp(0.0, 1.0);
        f['progress'] = p;
        f['status'] = (paid >= goal && goal > 0)
            ? 'Completed'
            : 'Still Collecting...';

        totalPaid += paid;
        totalGoal += goal;
      }

      // Default sort: latest date first
      list.sort((a, b) {
        final ad = DateTime.tryParse((a['deadline'] ?? '').toString());
        final bd = DateTime.tryParse((b['deadline'] ?? '').toString());
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      if (!mounted) return;
      setState(() {
        _funds = list;
        _totalPaid = totalPaid;
        _totalGoal = totalGoal;
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isEmpty ? 'Failed to load funds.' : e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load funds: $e';
        _loading = false;
      });
    }
  }

  Future<void> _onRefresh() => _load();

  List<Map<String, dynamic>> get _visibleFunds {
    List<Map<String, dynamic>> list = _funds;

    // Filter by status
    if (_statusFilter == 'collecting') {
      list = list
          .where((f) => (f['status'] ?? '').toString() != 'Completed')
          .toList();
    } else if (_statusFilter == 'completed') {
      list = list
          .where((f) => (f['status'] ?? '').toString() == 'Completed')
          .toList();
    }

    // Search by name
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((f) => (f['name'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }

    // Sort
    int cmpDate(a, b, {bool desc = true}) {
      final ad = DateTime.tryParse((a['deadline'] ?? '').toString());
      final bd = DateTime.tryParse((b['deadline'] ?? '').toString());
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return desc ? bd.compareTo(ad) : ad.compareTo(bd);
    }

    switch (_sort) {
      case 'date_asc':
        list.sort((a, b) => cmpDate(a, b, desc: false));
        break;
      case 'progress_desc':
        list.sort((a, b) {
          final pa = ((a['progress'] ?? 0.0) as double);
          final pb = ((b['progress'] ?? 0.0) as double);
          return pb.compareTo(pa);
        });
        break;
      case 'date_desc':
      default:
        list.sort((a, b) => cmpDate(a, b, desc: true));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimaryDark, size: 28),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text(
          'Manage Fund',
          style: TextStyle(
            color: kPrimaryDark,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            fontFamily: 'Montserrat',
            letterSpacing: .2,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: kPrimaryDark),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _summaryHeader(),
                  const SizedBox(height: 12),
                  _filtersBar(),
                  const SizedBox(height: 8),
                  if (_visibleFunds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: const [
                          Icon(
                            Icons.inbox_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 10),
                          Text('No matching funds. Try a different filter.'),
                        ],
                      ),
                    )
                  else
                    ...List.generate(
                      _visibleFunds.length,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _fundCard(_visibleFunds[i]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _summaryHeader() {
    final remaining = (_totalGoal - _totalPaid).clamp(0.0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overview',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kSubtleText,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _kpi('Collected', _currency(_totalPaid), color: Colors.teal),
              const SizedBox(width: 12),
              _kpi('Goal', _currency(_totalGoal), color: Colors.indigo),
              const SizedBox(width: 12),
              _kpi('Remaining', _currency(remaining), color: Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, {required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(.9),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color.darken(),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtersBar() {
    return Column(
      children: [
        // Search
        TextField(
          decoration: InputDecoration(
            hintText: 'Search...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kPrimary),
            ),
          ),
          onChanged: (v) => setState(() => _search = v.trim()),
        ),
        const SizedBox(height: 10),
        // Status chips only (removed sort menu)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statusChip('All', 'all'),
            _statusChip('Collecting', 'collecting'),
            _statusChip('Completed', 'completed'),
          ],
        ),
      ],
    );
  }

  Widget _statusChip(String label, String key) {
    final selected = _statusFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      labelStyle: TextStyle(
        color: selected ? Colors.white : kNeutralText,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: kPrimary,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? kPrimary : Colors.grey.shade300),
      onSelected: (_) => setState(() => _statusFilter = key),
    );
  }

  Widget _fundCard(Map<String, dynamic> fund) {
    final paid = (fund['paid'] as double?) ?? 0.0;
    final goal = (fund['goal'] as double?) ?? 0.0;
    final progress = (fund['progress'] as double?)?.clamp(0.0, 1.0) ?? 0.0;
    final deadline = (fund['deadline'] ?? '').toString();
    final completed = (fund['status'] ?? '').toString() == 'Completed';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: completed ? Colors.teal.withOpacity(.3) : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _jarIcon(progress: progress),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + status pill
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (fund['name'] ?? 'Death Notice').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: kNeutralText,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: completed
                              ? Colors.teal.withOpacity(.12)
                              : Colors.orange.withOpacity(.12),
                          border: Border.all(
                            color: completed ? Colors.teal : Colors.orange,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          completed ? 'Completed' : 'Collecting',
                          style: TextStyle(
                            color: completed
                                ? Colors.teal[800]
                                : Colors.orange[800],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Amounts
                  Text(
                    '₱${paid.toStringAsFixed(2)} / ₱${goal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: kNeutralText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Progress bar + percent
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(
                              completed ? Colors.teal : Colors.indigo,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Date of death
                  Row(
                    children: [
                      const Icon(Icons.event, size: 16, color: kSubtleText),
                      const SizedBox(width: 6),
                      Text(
                        'Date of Death: ${deadline.isEmpty ? '—' : deadline}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: kSubtleText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Animated, asset-free “jar” indicator
  Widget _jarIcon({double progress = 0.0}) {
    final clamped = progress.clamp(0.0, 1.0);

    return SizedBox(
      width: 56,
      height: 86,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Jar neck
          Positioned(
            top: 0,
            child: Container(
              width: 20,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          // Jar body outline
          Positioned(
            top: 10,
            left: 6,
            right: 6,
            bottom: 6,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Liquid fill with animation
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: clamped),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final height = 60 * value;
                return Container(
                  height: height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.teal.shade400, Colors.teal.shade200],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CustomPaint(
                    painter: _WavePainter(amplitude: 3, phase: 0.0),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _currency(double n) {
    return '₱${n.toStringAsFixed(2)}';
  }
}

// Subtle wave overlay inside the liquid
class _WavePainter extends CustomPainter {
  final double amplitude;
  final double phase;
  _WavePainter({this.amplitude = 3, this.phase = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..style = PaintingStyle.fill;

    final path = Path();
    final midY = size.height * 0.25;

    path.moveTo(0, midY);
    for (double x = 0; x <= size.width; x++) {
      final y = midY + amplitude * sin(0.5 * (x / size.width * 6.283 + phase));
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.amplitude != amplitude;
  }
}

extension _ColorX on Color {
  Color darken([double amount = .2]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final h = hsl.hue,
        s = hsl.saturation,
        l = (hsl.lightness - amount).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(hsl.alpha, h, s, l).toColor();
  }
}
