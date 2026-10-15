import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/pages/submit_claim.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Color palette (borrowed from memclaims.dart)
const double kCardRadius = 18;
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryDark = Color(0xFF083366);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
const kNeutralText = Color(0xFF1F2937);
const kSubtleText = Color(0xFF4B5563);

class CollectorClaimsPage extends StatefulWidget {
  final int dayungUnitId;
  const CollectorClaimsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectorClaimsPage> createState() => _CollectorClaimsPageState();
}

class _CollectorClaimsPageState extends State<CollectorClaimsPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  bool _submittingModalOpen = false;

  List<Map<String, dynamic>> _myClaims = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = sb.auth.currentUser?.id;

      final myRes = uid == null
          ? []
          : await sb
                .from('claims')
                .select(
                  'id, title, description, status, date_submitted, user_id, dayung_unit_id',
                )
                .eq('dayung_unit_id', widget.dayungUnitId)
                .eq('user_id', uid as Object)
                .order('date_submitted', ascending: false);

      final myClaims = List<Map<String, dynamic>>.from(myRes);

      setState(() {
        _myClaims = myClaims;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _myClaims = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: FloatingActionButton.extended(
          backgroundColor: kPrimaryDark,
          foregroundColor: Colors.white,
          elevation: 4,
          extendedPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: const Text(
            'Submit Claim',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: 'Montserrat',
            ),
          ),
          onPressed: _openSubmitSheet,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: dayungSurface(context),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  boxShadow: [dayungTopShadow(context)],
                ),
                child: _loading
                    ? const DayungPageSkeleton(
                        layout: DayungSkeletonLayout.dashboard,
                        itemCount: 4,
                      )
                    : RefreshIndicator(
                        color: kPrimary,
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                          children: [
                            if (_myClaims.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'My Claims',
                                  style: TextStyle(
                                    color: kText,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                              ),
                            if (_myClaims.isNotEmpty) _claimsTable(),
                            const SizedBox(height: 8),
                            if (_myClaims.isEmpty)
                              _emptyState('No claims yet for this unit'),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSubmitSheet() async {
    if (_submittingModalOpen) return;
    _submittingModalOpen = true;

    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SubmitClaimForm(dayungUnitId: widget.dayungUnitId),
      ),
    );

    _submittingModalOpen = false;
    if (result == true) await _load();
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E40AF), Color(0xFF3B82F6), Color(0xFF60A5FA)],
        ),
      ),
      child: const Text(
        'Claims',
        style: TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          fontFamily: 'Montserrat',
        ),
      ),
    );
  }

  // UI helpers
  Widget _claimsTable() {
    return RecordDataTable(
      minWidth: 960,
      columnSpacing: 20,
      columns: const [
        DataColumn(label: Text('Claim')),
        DataColumn(label: Text('Description')),
        DataColumn(label: Text('Submitted')),
        DataColumn(label: Text('Status')),
      ],
      rows: _myClaims.map((claim) {
        final status = (claim['status'] ?? '').toString();
        final color = _statusColor(status);
        return DataRow(
          cells: [
            DataCell(
              Text(
                (claim['title'] ?? 'Untitled').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataCell(
              Text(
                (claim['description'] ?? '').toString().trim().isEmpty
                    ? '—'
                    : (claim['description'] ?? '').toString().trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataCell(Text(_formatDate(claim['date_submitted']))),
            DataCell(
              Text(
                _displayStatus(status),
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _emptyState(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    final parsed = DateTime.tryParse(date.toString());
    if (parsed == null) return date.toString();
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String s) {
    final low = s.toLowerCase();
    if (low == 'approved' || low == 'claimed') return kAccent;
    if (low == 'rejected') return kDanger;
    if (low == 'pending') return kWarn;
    return kSubtleText;
  }

  String _displayStatus(String s) {
    final low = s.toLowerCase();
    if (low == 'approved') return 'Approved';
    if (low == 'claimed') return 'Claimed';
    if (low == 'rejected') return 'Rejected';
    if (low == 'pending') return 'Pending';
    return s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '—';
  }
}
