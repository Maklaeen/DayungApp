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
        title: Text(
          'Claims',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh claims',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
              fixedSize: const Size(52, 52),
              backgroundColor: dayungSurface(context),
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: dayungBorder(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 88),
        child: FloatingActionButton.extended(
          heroTag: 'submitClaimFab',
          icon: const Icon(Icons.add_rounded),
          label: const Text('Submit claim'),
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
              layout: DayungSkeletonLayout.list,
              itemCount: 3,
            )
          : RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 180),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'My claims',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_myClaims.length} total',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(
                        'Pending',
                        _myPending,
                        kWarn,
                        Icons.schedule_rounded,
                      ),
                      _chip(
                        'Approved',
                        _myApproved,
                        kAccent,
                        Icons.check_circle_rounded,
                      ),
                      _chip(
                        'Rejected',
                        _myRejected,
                        kDanger,
                        Icons.cancel_rounded,
                      ),
                      _chip(
                        'Claimed',
                        _myClaimed,
                        kAccent,
                        Icons.task_alt_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_myClaims.isEmpty) _emptyState() else _claimsTable(),
                ],
              ),
            ),
    );
  }

  // UI helpers
  Widget _chip(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _claimsTable() {
    final colors = Theme.of(context).colorScheme;
    return RecordDataTable(
      minWidth: 720,
      columnSpacing: 18,
      horizontalMargin: 16,
      headingRowHeight: 50,
      dataRowMinHeight: 56,
      dataRowMaxHeight: 76,
      showCheckboxColumn: false,
      headingTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: 'Montserrat',
      ),
      dataTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        fontFamily: 'OpenSans',
      ),
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
            DataCell(
              Text(submitted.isEmpty ? '—' : submitted.split('T').first),
            ),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(status), size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(
                      _displayStatus(status),
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _emptyState() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: dayungSectionCardDecoration(context, radius: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.inbox_outlined,
              color: colors.onSurfaceVariant,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No claims yet',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
            ),
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
