import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/pages/submit_claim.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kAccent = Color(0xFF0D47A1);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
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
        padding: const EdgeInsets.only(bottom: 96),
        child: FloatingActionButton.extended(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          extendedPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Submit claim',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: 'Montserrat',
            ),
          ),
          onPressed: _openSubmitSheet,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Container(
        color: dayungPageBackground(context),
        child: _loading
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
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 180),
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
                        IconButton(
                          tooltip: 'Refresh claims',
                          onPressed: _loading ? null : _load,
                          icon: const Icon(Icons.refresh_rounded),
                          style: IconButton.styleFrom(
                            fixedSize: const Size(48, 48),
                            backgroundColor: dayungSurface(context),
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            side: BorderSide(color: dayungBorder(context)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_myClaims.isEmpty) _emptyState() else _claimsTable(),
                  ],
                ),
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

  // UI helpers
  Widget _claimsTable() {
    final colors = Theme.of(context).colorScheme;
    return RecordDataTable(
      minWidth: 760,
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
                description.isEmpty ? '—' : description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataCell(Text(_formatDate(claim['date_submitted']))),
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
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Submit your first claim to get started.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            textAlign: TextAlign.center,
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

  IconData _statusIcon(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return Icons.check_circle_rounded;
      case 'claimed':
        return Icons.task_alt_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      case 'pending':
        return Icons.schedule_rounded;
      default:
        return Icons.help_outline_rounded;
    }
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
