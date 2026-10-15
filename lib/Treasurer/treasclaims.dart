import 'package:capstone_app/pages/submit_claim.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
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

class TreasurerClaimsPage extends StatefulWidget {
  final int dayungUnitId;
  const TreasurerClaimsPage({super.key, required this.dayungUnitId});

  @override
  State<TreasurerClaimsPage> createState() => _TreasurerClaimsPageState();
}

class _TreasurerClaimsPageState extends State<TreasurerClaimsPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;

  // My claims
  List<Map<String, dynamic>> _myClaims = [];
  int _myPending = 0;
  int _myApproved = 0;
  int _myRejected = 0;
  int _myClaimed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = sb.auth.currentUser?.id;

      List<Map<String, dynamic>> myRows = [];
      int myPending = 0;
      int myApproved = 0;
      int myRejected = 0;
      int myClaimed = 0;
      if (uid != null) {
        final myRes = await sb
            .from('claims')
            .select(
              'id, title, description, status, date_submitted, user_id, beneficiary_id, dayung_unit_id',
            )
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('user_id', uid as Object)
            .order('date_submitted', ascending: false);
        myRows = List<Map<String, dynamic>>.from(myRes);
        for (final claim in myRows) {
          switch ((claim['status'] ?? '').toString().toLowerCase()) {
            case 'pending':
              myPending++;
              break;
            case 'approved':
              myApproved++;
              break;
            case 'rejected':
              myRejected++;
              break;
            case 'claimed':
              myClaimed++;
              break;
          }
        }
      }

      setState(() {
        _myClaims = myRows;
        _myPending = myPending;
        _myApproved = myApproved;
        _myRejected = myRejected;
        _myClaimed = myClaimed;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _myClaims = [];
        _myPending = 0;
        _myApproved = 0;
        _myRejected = 0;
        _myClaimed = 0;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      appBar: AppBar(
        backgroundColor: dayungPageBackground(context),
        elevation: 0,
        title: const Text(
          'Claims',
          style: TextStyle(color: kText, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: FloatingActionButton.extended(
          heroTag: 'submitClaimFab',
          icon: const Icon(Icons.add),
          label: const Text('Submit Claim'),
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          onPressed: () {
            showModalBottomSheet(
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
                child: SubmitClaimForm(
                  dayungUnitId: widget.dayungUnitId,
                  requireMembership: false, // officers can submit
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: _loading
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  const Text(
                    'My Claims',
                    style: TextStyle(
                      color: kPrimaryDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                  const Text(
                    'Only your own claims are shown here.',
                    style: TextStyle(
                      color: kSubtleText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip('Pending', _myPending, kWarn),
                      _chip('Approved', _myApproved, kAccent),
                      _chip('Rejected', _myRejected, kDanger),
                      _chip('Claimed', _myClaimed, kAccent),
                      _chip('Total', _myClaims.length, kPrimary),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_myClaims.isEmpty)
                    _emptyState('You have not submitted any claims yet')
                  else
                    _claimsTable(),
                ],
              ),
            ),
    );
  }

  // UI helpers
  Widget _chip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _claimsTable() {
    return RecordDataTable(
      minWidth: 720,
      columns: const [
        DataColumn(label: Text('Claim')),
        DataColumn(label: Text('Description')),
        DataColumn(label: Text('Submitted')),
        DataColumn(label: Text('Status')),
      ],
      rows: _myClaims.map((claim) {
        final status = (claim['status'] ?? '').toString();
        final color = _statusColor(status);
        final description = (claim['description'] ?? '').toString().trim();
        final submitted = (claim['date_submitted'] ?? '').toString();
        return DataRow(
          cells: [
            DataCell(
              Text(
                (claim['title'] ?? 'Claim').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataCell(
              Text(
                description.isEmpty ? '—' : description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataCell(Text(submitted.isEmpty ? '—' : submitted.split('T').first)),
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
