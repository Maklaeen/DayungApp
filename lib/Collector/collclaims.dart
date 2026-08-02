import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/pages/submit_claim.dart';
import 'package:capstone_app/utils/theme_surface.dart';
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
                            ..._myClaims.map(_claimCard),
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
  Widget _claimCard(Map<String, dynamic> c) {
    final status = (c['status'] ?? '').toString();
    final title = (c['title'] ?? 'Untitled').toString();
    final desc = (c['description'] ?? '').toString().trim();
    final date = _formatDate(c['date_submitted']);
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          const BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          // TODO: open claim detail (collector)
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_statusIcon(status), color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: kText,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          date,
                          style: const TextStyle(
                            fontFamily: 'OpenSans',
                            fontSize: 13,
                            color: kSubText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _displayStatus(status),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 15,
                    color: kSubText,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.arrow_outward_rounded, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    'View details',
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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

  IconData _statusIcon(String status) {
    final low = status.toLowerCase();
    if (low == 'approved' || low == 'claimed') return Icons.check_circle;
    if (low == 'rejected') return Icons.cancel;
    if (low == 'pending') return Icons.pending;
    return Icons.info;
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
