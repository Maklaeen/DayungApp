import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/Secretary/secretary_ui.dart';
import 'package:capstone_app/shared/president_secretary_member_reports.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

const Color kCardBg = Color(0xFFFFFFFF);
const Color kBorderColor = Color(0xFFE5E7EB);
const Color kPrimary = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kSubText = Color(0xFF6B7280);
const List<String> _monthShortLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

enum _ReportExportOption { moneyCollected, newMembers, all }

class ReportsService {
  final sb = Supabase.instance.client;

  // gina fetch ang total money collected per collector per month
  Future<List<Map<String, dynamic>>> fetchMoneyCollectedPerCollector({
    int? unitId,
  }) async {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1).toIso8601String();
    final yearEnd = DateTime(now.year, 12, 31, 23, 59, 59).toIso8601String();

    final query = sb
        .from('payments')
        .select(
          'amount, paid_at, created_at, collected_by, collector:users!payments_collected_by_fkey(full_name)',
        )
        .eq('status', 'paid')
        .gte('created_at', yearStart)
        .lte('created_at', yearEnd);
    if (unitId != null) query.eq('dayung_unit_id', unitId);
    final rows = List<Map<String, dynamic>>.from(await query);

    // Aggregate: {collector, month, total}
    final Map<String, Map<String, dynamic>> data = {};
    for (final r in rows) {
      final collectorId = r['collected_by']?.toString() ?? 'unknown';
      final collectorName = (r['collector']?['full_name'] ?? 'Unknown')
          .toString();
      final dateValue = (r['paid_at'] ?? r['created_at'])?.toString() ?? '';
      final paidAt = DateTime.tryParse(dateValue);
      if (paidAt == null) continue;
      final month = '${paidAt.year}-${paidAt.month.toString().padLeft(2, '0')}';
      final amount = double.tryParse(r['amount'].toString()) ?? 0.0;
      final key = '$collectorId|$month';
      data.putIfAbsent(
        key,
        () => {
          'collector_id': collectorId,
          'collector_name': collectorName,
          'month': month,
          'total': 0.0,
        },
      );
      data[key]!['total'] = (data[key]!['total'] as double) + amount;
    }
    return data.values.toList();
  }

  Future<List<Map<String, dynamic>>> fetchDisbursementActivity({
    int? unitId,
  }) async {
    var claimsQuery = sb
        .from('claims')
        .select(
          'claimant_name, title, amount_released, secretary_id, '
          'date_released, status, claimedmoney',
        );
    if (unitId != null) claimsQuery = claimsQuery.eq('dayung_unit_id', unitId);

    final claims = List<Map<String, dynamic>>.from(await claimsQuery);
    final activities = claims
        .where((claim) => _isTruthyFlag(claim['claimedmoney']))
        .map(
          (claim) => {
            'beneficiary_name':
                (claim['claimant_name'] ?? '').toString().trim().isEmpty
                ? 'Unknown beneficiary'
                : claim['claimant_name'],
            'deceased_member': (claim['title'] ?? '').toString().trim().isEmpty
                ? 'Unknown member'
                : claim['title'],
            'amount': claim['amount_released'],
            'released_by':
                (claim['secretary_id'] ?? '').toString().trim().isEmpty
                ? 'Not recorded'
                : claim['secretary_id'],
            'released_at': claim['date_released'],
            'status': claim['status'],
          },
        )
        .toList();

    activities.sort((a, b) {
      final aDate = DateTime.tryParse('${a['released_at'] ?? ''}');
      final bDate = DateTime.tryParse('${b['released_at'] ?? ''}');
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return activities;
  }

  Future<List<Map<String, dynamic>>> fetchCollectionReportRows({
    int? unitId,
  }) async {
    var query = sb
        .from('payments')
        .select(
          'id, user_id, userdeceased, deceased_name, amount, status, type, '
          'created_at, paid_at, is_claimed, is_claimed_date, '
          'contributor:users!payments_user_id_fkey(full_name)',
        )
        .not('userdeceased', 'is', null);
    if (unitId != null) query = query.eq('dayung_unit_id', unitId);

    final rows = List<Map<String, dynamic>>.from(await query);
    final deceasedIds = rows
        .map((row) => (row['userdeceased'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final deceasedNamesById = <String, String>{};

    if (deceasedIds.isNotEmpty) {
      final deceasedUsers = await sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', deceasedIds);
      for (final user in deceasedUsers) {
        deceasedNamesById[(user['id'] ?? '').toString()] =
            (user['full_name'] ?? '').toString();
      }
    }

    for (final row in rows) {
      final contributor = row['contributor'];
      final deceasedId = (row['userdeceased'] ?? '').toString();
      final deceasedName = (row['deceased_name'] ?? '').toString().trim();
      row['contributor_name'] = contributor is Map
          ? (contributor['full_name'] ?? 'Unknown contributor').toString()
          : 'Unknown contributor';
      row['deceased_member_name'] = deceasedName.isNotEmpty
          ? deceasedName
          : deceasedNamesById[deceasedId]?.trim().isNotEmpty == true
          ? deceasedNamesById[deceasedId]
          : 'Unknown member';
    }

    rows.sort((a, b) {
      final aDate = DateTime.tryParse(
        '${a['paid_at'] ?? a['created_at'] ?? ''}',
      );
      final bDate = DateTime.tryParse(
        '${b['paid_at'] ?? b['created_at'] ?? ''}',
      );
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  Future<Map<String, bool>> fetchCollectionClaimStatuses({int? unitId}) async {
    var query = sb.from('claims').select('user_id, claimedmoney');
    if (unitId != null) query = query.eq('dayung_unit_id', unitId);

    final rows = List<Map<String, dynamic>>.from(await query);
    final statuses = <String, bool>{};
    for (final row in rows) {
      final memberId = (row['user_id'] ?? '').toString();
      if (memberId.isEmpty) continue;
      statuses[memberId] =
          (statuses[memberId] ?? false) || _isTruthyFlag(row['claimedmoney']);
    }
    return statuses;
  }

  Future<Map<String, int>> fetchMemberActivitySummary({
    required int unitId,
  }) async {
    final applications = await sb
        .from('applications')
        .select('user_id, status, isRemovedInDayung')
        .eq('dayung_unit_id', unitId);
    final applicationRows = List<Map<String, dynamic>>.from(applications);

    final deathNotices = await sb
        .from('death_notices')
        .select('user_id, beneficiary_id, deceased_type')
        .eq('dayung_unit_id', unitId);
    final noticeRows = List<Map<String, dynamic>>.from(deathNotices);

    final deceasedMembers = noticeRows
        .where(
          (row) =>
              (row['deceased_type'] ?? 'member').toString().toLowerCase() ==
              'member',
        )
        .map((row) => (row['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    final deceasedBeneficiaries = noticeRows
        .where(
          (row) =>
              (row['deceased_type'] ?? '').toString().toLowerCase() ==
              'beneficiary',
        )
        .map((row) => (row['beneficiary_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    return {
      'added': applicationRows
          .where((row) => (row['status'] ?? '').toString() == 'approved')
          .length,
      'removed': applicationRows
          .where((row) => row['isRemovedInDayung'] == true)
          .length,
      'deceasedMembers': deceasedMembers.length,
      'deceasedBeneficiaries': deceasedBeneficiaries.length,
    };
  }

  /// Number of new members each month
  Future<List<Map<String, dynamic>>> fetchNewMembersPerMonth({
    required int unitId,
  }) async {
    final query = sb
        .from('applications')
        .select('approved_at')
        .eq('status', 'approved')
        .eq('dayung_unit_id', unitId); // Always filter by unitId
    final rows = List<Map<String, dynamic>>.from(await query);

    final Map<String, int> monthCounts = {};
    for (final r in rows) {
      final approvedAt = DateTime.tryParse(r['approved_at']?.toString() ?? '');
      if (approvedAt == null) continue;
      final month =
          '${approvedAt.year}-${approvedAt.month.toString().padLeft(2, '0')}';
      monthCounts[month] = (monthCounts[month] ?? 0) + 1;
    }
    return monthCounts.entries
        .map((e) => {'month': e.key, 'count': e.value})
        .toList();
  }
}

String _formatMonthYear(String ym) {
  // ym is in 'YYYY-MM'
  final parts = ym.split('-');
  if (parts.length != 2) return ym;
  final year = parts[0];
  final monthNum = int.tryParse(parts[1]) ?? 1;
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final monthName = (monthNum >= 1 && monthNum <= 12)
      ? months[monthNum - 1]
      : ym;
  return '$monthName - $year';
}

bool _isTruthyFlag(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

String formatPhilippineDateTime(Object? value) {
  if (value == null) return '—';

  final rawValue = value.toString().trim();
  if (rawValue.isEmpty || rawValue == '—') return '—';

  final parsed = DateTime.tryParse(rawValue);
  if (parsed == null) return rawValue;

  final philippineTime = parsed.toUtc().add(const Duration(hours: 8));
  return DateFormat('MMM d, yyyy • h:mm a').format(philippineTime);
}

Map<String, dynamic> summarizePaymentFlowRows(List<Map<String, dynamic>> rows) {
  double collectedTotal = 0;
  double claimedTotal = 0;
  DateTime? latestClaimDate;

  for (final row in rows) {
    final amount = double.tryParse(row['amount']?.toString() ?? '') ?? 0;
    if (_isTruthyFlag(row['iscollectedbytreasurer'])) {
      collectedTotal += amount;
    }

    if (_isTruthyFlag(row['is_claimed'])) {
      claimedTotal += amount;
      final claimDate = DateTime.tryParse(
        row['is_claimed_date']?.toString() ?? '',
      );
      if (claimDate != null &&
          (latestClaimDate == null || claimDate.isAfter(latestClaimDate))) {
        latestClaimDate = claimDate;
      }
    }
  }

  final latestDate = latestClaimDate == null
      ? '—'
      : DateFormat('yyyy-MM-dd').format(latestClaimDate.toUtc());
  return {
    'in': collectedTotal,
    'out': claimedTotal,
    'date': latestDate,
    'latestActivity': latestDate,
  };
}

class ReportsPage extends StatefulWidget {
  final int? unitId;
  const ReportsPage({super.key, this.unitId});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final service = ReportsService();
  List<Map<String, dynamic>> moneyCollected = [];
  List<Map<String, dynamic>> newMembers = [];
  List<Map<String, dynamic>> disbursementActivities = [];
  List<Map<String, dynamic>> collectionReportRows = [];
  Map<String, bool> collectionClaimStatuses = {};
  Map<String, int> memberActivitySummary = const {
    'added': 0,
    'removed': 0,
    'deceasedMembers': 0,
    'deceasedBeneficiaries': 0,
  };
  String? disbursementActivityError;
  String? collectionReportError;
  String? _selectedIndividualMemberId;
  final Set<String> _selectedConsolidatedMemberIds = {};
  bool loading = true;
  pw.ThemeData? _pdfTheme;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => loading = true);
    try {
      List<Map<String, dynamic>> collectionRows = [];
      Map<String, bool> claimStatuses = {};
      String? collectionError;
      try {
        collectionRows = await service.fetchCollectionReportRows(
          unitId: widget.unitId,
        );
        claimStatuses = await service.fetchCollectionClaimStatuses(
          unitId: widget.unitId,
        );
      } catch (error) {
        debugPrint('Unable to load collection reports: $error');
        collectionError = 'Unable to load collection reports.';
      }

      final activities = await service.fetchDisbursementActivity(
        unitId: widget.unitId,
      );
      final collected = await service.fetchMoneyCollectedPerCollector(
        unitId: widget.unitId,
      );
      final members = widget.unitId != null
          ? await service.fetchNewMembersPerMonth(unitId: widget.unitId!)
          : <Map<String, dynamic>>[];
      final activitySummary = widget.unitId != null
          ? await service.fetchMemberActivitySummary(unitId: widget.unitId!)
          : memberActivitySummary;
      if (!mounted) return;
      setState(() {
        collectionReportRows = collectionRows;
        collectionClaimStatuses = claimStatuses;
        collectionReportError = collectionError;
        if (_selectedIndividualMemberId != null &&
            !collectionRows.any(
              (row) =>
                  row['userdeceased']?.toString() ==
                  _selectedIndividualMemberId,
            )) {
          _selectedIndividualMemberId = null;
        }
        _selectedConsolidatedMemberIds.removeWhere(
          (id) => !collectionRows.any(
            (row) => row['userdeceased']?.toString() == id,
          ),
        );
        disbursementActivities = activities;
        memberActivitySummary = activitySummary;
        disbursementActivityError = null;
        moneyCollected = collected;
        newMembers = members;
        loading = false;
      });
    } catch (error) {
      debugPrint('Unable to load reports: $error');
      if (!mounted) return;
      setState(() {
        disbursementActivityError = 'Unable to load Disbursement Activity.';
        loading = false;
      });
    }
  }

  List<_ReportMember> get _reportMembers {
    final membersById = <String, String>{};
    for (final row in collectionReportRows) {
      final id = (row['userdeceased'] ?? '').toString();
      if (id.isEmpty) continue;
      final name = (row['deceased_member_name'] ?? 'Unknown member').toString();
      membersById.putIfAbsent(id, () => name);
    }
    return membersById.entries
        .map((entry) => _ReportMember(id: entry.key, name: entry.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _showMemberPicker({required bool multiSelect}) async {
    final selectedIds = multiSelect
        ? _selectedConsolidatedMemberIds.toList()
        : [
            if (_selectedIndividualMemberId != null)
              _selectedIndividualMemberId!,
          ];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _SearchableMemberPicker(
        members: _reportMembers,
        selectedIds: selectedIds,
        multiSelect: multiSelect,
        title: multiSelect ? 'Select members' : 'Select deceased member',
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (multiSelect) {
        _selectedConsolidatedMemberIds
          ..clear()
          ..addAll(result);
      } else {
        _selectedIndividualMemberId = result.isEmpty ? null : result.first;
      }
    });
  }

  Widget _buildIndividualCollectionReport() {
    final selectedId = _selectedIndividualMemberId;
    final selectedMember = selectedId == null
        ? null
        : _reportMembers.where((member) => member.id == selectedId).firstOrNull;
    final rows = selectedId == null
        ? <Map<String, dynamic>>[]
        : collectionReportRows
              .where((row) => row['userdeceased']?.toString() == selectedId)
              .toList();
    final totalCollected = rows.fold<double>(0, (total, row) {
      if ((row['status'] ?? '').toString().toLowerCase() != 'paid') {
        return total;
      }
      return total + _reportAmount(row['amount']);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollectionMemberSelector(
          label: 'Deceased member',
          selectedName: selectedMember?.name,
          onTap: _reportMembers.isEmpty
              ? null
              : () => _showMemberPicker(multiSelect: false),
        ),
        const SizedBox(height: 16),
        if (collectionReportError != null)
          const _CollectionReportNotice(
            icon: Icons.cloud_off_rounded,
            message: 'Collection details could not be loaded. Try refreshing.',
          )
        else if (selectedMember == null)
          const _CollectionReportNotice(
            icon: Icons.search_rounded,
            message:
                'Choose a deceased member to view their contribution history.',
          )
        else ...[
          _CollectedTotalCard(total: totalCollected),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const _CollectionReportNotice(
              icon: Icons.receipt_long_rounded,
              message: 'No collection records are available for this member.',
            )
          else
            _IndividualCollectionRows(rows: rows),
        ],
      ],
    );
  }

  Widget _buildConsolidatedCollectionReport() {
    final selectedMembers = _reportMembers
        .where((member) => _selectedConsolidatedMemberIds.contains(member.id))
        .toList();
    final summaryRows = selectedMembers.map((member) {
      final payments = collectionReportRows
          .where((row) => row['userdeceased']?.toString() == member.id)
          .toList();
      final paidPayments = payments
          .where(
            (row) => (row['status'] ?? '').toString().toLowerCase() == 'paid',
          )
          .toList();
      DateTime? latestPaidDate;
      for (final payment in paidPayments) {
        final date = DateTime.tryParse(
          '${payment['paid_at'] ?? payment['created_at'] ?? ''}',
        );
        if (date != null &&
            (latestPaidDate == null || date.isAfter(latestPaidDate))) {
          latestPaidDate = date;
        }
      }
      final total = paidPayments.fold<double>(
        0,
        (sum, payment) => sum + _reportAmount(payment['amount']),
      );
      return <String, dynamic>{
        'deceased_member': member.name,
        'collected': total,
        'date': latestPaidDate,
        'status': paidPayments.isEmpty ? 'Pending' : 'Collected',
        'claim_status': collectionClaimStatuses[member.id] == true
            ? 'Released'
            : collectionClaimStatuses.containsKey(member.id)
            ? 'Pending'
            : 'Not filed',
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollectionMemberSelector(
          label: 'Members',
          selectedName: selectedMembers.isEmpty
              ? null
              : '${selectedMembers.length} selected',
          onTap: _reportMembers.isEmpty
              ? null
              : () => _showMemberPicker(multiSelect: true),
          multiSelect: true,
        ),
        const SizedBox(height: 16),
        if (collectionReportError != null)
          const _CollectionReportNotice(
            icon: Icons.cloud_off_rounded,
            message: 'Collection details could not be loaded. Try refreshing.',
          )
        else if (_selectedConsolidatedMemberIds.isEmpty)
          const _CollectionReportNotice(
            icon: Icons.search_rounded,
            message:
                'Choose one or more members to compare collection and claim status.',
          )
        else if (summaryRows.isEmpty)
          const _CollectionReportNotice(
            icon: Icons.receipt_long_rounded,
            message: 'No collection records are available for these members.',
          )
        else
          _ConsolidatedCollectionRows(rows: summaryRows),
      ],
    );
  }

  List<double> _moneyCollectedMonthlyTotals() {
    final now = DateTime.now();
    final monthlyTotals = List<double>.filled(12, 0);

    for (final row in moneyCollected) {
      final monthValue = (row['month'] ?? '').toString();
      final parts = monthValue.split('-');
      if (parts.length != 2) continue;

      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year != now.year || month == null || month < 1 || month > 12) {
        continue;
      }

      final totalValue = row['total'];
      final total = totalValue is num
          ? totalValue.toDouble()
          : double.tryParse(totalValue.toString()) ?? 0;
      monthlyTotals[month - 1] += total;
    }

    return monthlyTotals;
  }

  List<Map<String, dynamic>> _sortedNewMembersData() {
    final rows = List<Map<String, dynamic>>.from(newMembers);
    rows.sort((a, b) {
      final left = (a['month'] ?? '').toString();
      final right = (b['month'] ?? '').toString();
      return left.compareTo(right);
    });
    return rows;
  }

  Future<pw.ThemeData> _getPdfTheme() async {
    if (_pdfTheme != null) return _pdfTheme!;

    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/OpenSans-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/OpenSans-Bold.ttf'),
    );
    _pdfTheme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);
    return _pdfTheme!;
  }

  Future<void> _showExportOptions() async {
    final option = await showModalBottomSheet<_ReportExportOption>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SecretarySheetHeader(
                title: 'Print Reports',
                subtitle: 'Choose which graph to export as PDF.',
              ),
              ListTile(
                leading: const Icon(
                  Icons.account_balance_rounded,
                  color: kPrimary,
                ),
                title: const Text('Money Collected Per Collector (Monthly)'),
                onTap: () =>
                    Navigator.pop(context, _ReportExportOption.moneyCollected),
              ),
              ListTile(
                leading: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: kPrimary,
                ),
                title: const Text('New Members Per Month'),
                onTap: () =>
                    Navigator.pop(context, _ReportExportOption.newMembers),
              ),
              ListTile(
                leading: const Icon(Icons.print_rounded, color: kPrimary),
                title: const Text('All'),
                onTap: () => Navigator.pop(context, _ReportExportOption.all),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (option == null || !mounted) return;
    await _printReport(option);
  }

  Future<void> _printReport(_ReportExportOption option) async {
    final pdfTheme = await _getPdfTheme();
    final document = pw.Document(theme: pdfTheme);
    final moneyTotals = _moneyCollectedMonthlyTotals();
    final newMembersRows = _sortedNewMembersData();
    final now = DateTime.now();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Text(
              'Reports',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(kPrimary.toARGB32()),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Printed: ${now.toLocal()}'),
            pw.SizedBox(height: 20),
          ];

          if (option == _ReportExportOption.moneyCollected ||
              option == _ReportExportOption.all) {
            widgets.add(
              _buildPdfBarSection(
                title: 'Money Collected Per Collector (Monthly)',
                subtitle:
                    'Current year total: ₱${moneyTotals.fold(0.0, (sum, value) => sum + value).toStringAsFixed(0)}',
                values: moneyTotals,
                labels: _monthShortLabels,
                barColor: PdfColor.fromInt(kPrimary.toARGB32()),
                asCurrency: true,
              ),
            );
            widgets.add(pw.SizedBox(height: 20));
          }

          if (option == _ReportExportOption.newMembers ||
              option == _ReportExportOption.all) {
            widgets.add(
              _buildPdfBarSection(
                title: 'New Members Per Month',
                subtitle: 'Approved members by month',
                values: newMembersRows
                    .map((row) => ((row['count'] as num?) ?? 0).toDouble())
                    .toList(),
                labels: newMembersRows
                    .map(
                      (row) =>
                          _formatPdfMonthLabel((row['month'] ?? '').toString()),
                    )
                    .toList(),
                barColor: PdfColor.fromInt(kAccent.toARGB32()),
                asCurrency: false,
              ),
            );
          }

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => document.save());
  }

  pw.Widget _buildPdfBarSection({
    required String title,
    required String subtitle,
    required List<double> values,
    required List<String> labels,
    required PdfColor barColor,
    required bool asCurrency,
  }) {
    final maxValue = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a > b ? a : b);

    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
        border: pw.Border.all(color: PdfColor.fromInt(kBorderColor.toARGB32())),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(kPrimary.toARGB32()),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(subtitle),
          pw.SizedBox(height: 18),
          if (values.isEmpty)
            pw.Text('No data available.')
          else
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: List.generate(values.length, (index) {
                final value = values[index];
                final ratio = maxValue <= 0 ? 0.0 : value / maxValue;
                final label = index < labels.length ? labels[index] : '';

                return pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 3),
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          asCurrency
                              ? '₱${value.toStringAsFixed(0)}'
                              : value.toStringAsFixed(0),
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Container(
                          height: 120,
                          alignment: pw.Alignment.bottomCenter,
                          child: pw.Container(
                            width: 16,
                            height: maxValue <= 0 ? 2 : 120 * ratio,
                            decoration: pw.BoxDecoration(
                              color: barColor,
                              borderRadius: const pw.BorderRadius.vertical(
                                top: pw.Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          label,
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  String _formatPdfMonthLabel(String value) {
    final parts = value.split('-');
    if (parts.length != 2) return value;

    final month = int.tryParse(parts[1]);
    if (month == null || month < 1 || month > 12) return value;
    return _monthShortLabels[month - 1];
  }

  Widget _buildExportButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: loading ? null : _showExportOptions,
        icon: const Icon(Icons.print_rounded),
        label: const Text('Print / PDF'),
        style: FilledButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            final horizontalPadding = isWide ? 24.0 : 20.0;
            const contentMaxWidth = 1200.0;
            final sectionTitleFontSize = isWide ? 22.0 : 18.0;

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: const BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF1E40AF),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: contentMaxWidth,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isWide ? 0 : horizontalPadding,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Reports',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: loading
                      ? const DayungPageSkeleton(
                          layout: DayungSkeletonLayout.dashboard,
                          itemCount: 4,
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            isWide ? 28 : 20,
                            horizontalPadding,
                            isWide ? 32 : 20,
                          ),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: contentMaxWidth,
                                ),
                                child: _buildExportButton(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: contentMaxWidth,
                                ),
                                child: PresidentSecretaryMemberReports(
                                  addedMembers:
                                      memberActivitySummary['added'] ?? 0,
                                  removedMembers:
                                      memberActivitySummary['removed'] ?? 0,
                                  deceasedMembers:
                                      memberActivitySummary['deceasedMembers'] ??
                                      0,
                                  deceasedBeneficiaries:
                                      memberActivitySummary['deceasedBeneficiaries'] ??
                                      0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: contentMaxWidth,
                                ),
                                child: _modernSectionCard(
                                  title: 'Individual Collection Report',
                                  icon: Icons.person_search_rounded,
                                  titleFontSize: sectionTitleFontSize,
                                  child: _buildIndividualCollectionReport(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: contentMaxWidth,
                                ),
                                child: _modernSectionCard(
                                  title: 'Consolidated Collection Report',
                                  icon: Icons.assessment_rounded,
                                  titleFontSize: sectionTitleFontSize,
                                  child: _buildConsolidatedCollectionReport(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: contentMaxWidth,
                                ),
                                child: _modernSectionCard(
                                  title: 'Disbursement Activity',
                                  icon: Icons.payments_rounded,
                                  titleFontSize: sectionTitleFontSize,
                                  child: _DisbursementActivityTable(
                                    activities: disbursementActivities,
                                    error: disbursementActivityError,
                                    onRetry: _loadReports,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: contentMaxWidth,
                                ),
                                child: _modernSectionCard(
                                  title:
                                      'Money Collected Per Collector (Monthly)',
                                  icon: Icons.account_balance_rounded,
                                  titleFontSize: sectionTitleFontSize,
                                  child: _MoneyCollectedBarChart(
                                    data: moneyCollected,
                                    isWide: isWide,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: contentMaxWidth,
                                ),
                                child: _modernSectionCard(
                                  title: 'New Members Per Month',
                                  icon: Icons.person_add_alt_1_rounded,
                                  titleFontSize: sectionTitleFontSize,
                                  child: Column(
                                    children: [
                                      _NewMembersBarChart(
                                        data: newMembers,
                                        isWide: isWide,
                                      ),
                                      const SizedBox(height: 12),
                                      ...newMembers.map(
                                        (r) => Container(
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kCardBg,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: kBorderColor.withValues(
                                                alpha: 0.2,
                                              ),
                                            ),
                                          ),
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: kPrimary
                                                  .withValues(alpha: 0.12),
                                              child: Icon(
                                                Icons.person,
                                                color: kPrimary,
                                              ),
                                            ),
                                            title: Text(
                                              _formatMonthYear(r['month']),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: SizedBox(
                                              width: isWide ? 80 : 50,
                                              child: Text(
                                                '${r['count']}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _modernSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    double titleFontSize = 18,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: kBorderColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w800,
                    color: kPrimary,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ReportMember {
  final String id;
  final String name;

  const _ReportMember({required this.id, required this.name});
}

class _SearchableMemberPicker extends StatefulWidget {
  final List<_ReportMember> members;
  final List<String> selectedIds;
  final bool multiSelect;
  final String title;

  const _SearchableMemberPicker({
    required this.members,
    required this.selectedIds,
    required this.multiSelect,
    required this.title,
  });

  @override
  State<_SearchableMemberPicker> createState() =>
      _SearchableMemberPickerState();
}

class _SearchableMemberPickerState extends State<_SearchableMemberPicker> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<String> _selectedIds = widget.selectedIds.toSet();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = widget.members
        .where(
          (member) =>
              member.name.toLowerCase().contains(_search.trim().toLowerCase()),
        )
        .toList();
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: screenHeight * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  color: kPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.multiSelect
                    ? 'Search names and select all that apply.'
                    : 'Search by name to find the right member.',
                style: const TextStyle(
                  color: kSubText,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _search = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search member name',
                  filled: true,
                  fillColor: const Color(0xFFF7F9FC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: kBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: kBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: kPrimary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: filteredMembers.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No members match that search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kSubText,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredMembers.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: kBorderColor),
                        itemBuilder: (context, index) {
                          final member = filteredMembers[index];
                          final isSelected = _selectedIds.contains(member.id);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            minVerticalPadding: 10,
                            leading: CircleAvatar(
                              backgroundColor: kPrimary.withValues(alpha: 0.1),
                              child: const Icon(
                                Icons.person_rounded,
                                color: kPrimary,
                              ),
                            ),
                            title: Text(
                              member.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            trailing: widget.multiSelect
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: (_) => _toggle(member.id),
                                  )
                                : isSelected
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: kPrimary,
                                  )
                                : null,
                            onTap: () {
                              if (widget.multiSelect) {
                                _toggle(member.id);
                              } else {
                                Navigator.of(context).pop([member.id]);
                              }
                            },
                          );
                        },
                      ),
              ),
              if (widget.multiSelect) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selectedIds.toList()),
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text('Done (${_selectedIds.length} selected)'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(String memberId) {
    setState(() {
      if (!_selectedIds.add(memberId)) _selectedIds.remove(memberId);
    });
  }
}

class _CollectionMemberSelector extends StatelessWidget {
  final String label;
  final String? selectedName;
  final VoidCallback? onTap;
  final bool multiSelect;

  const _CollectionMemberSelector({
    required this.label,
    required this.selectedName,
    required this.onTap,
    this.multiSelect = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select $label',
          style: const TextStyle(
            color: Color(0xFF374151),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(
              multiSelect ? Icons.group_add_rounded : Icons.search_rounded,
            ),
            label: Text(
              selectedName ??
                  (onTap == null ? 'No members available' : 'Search members'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: onTap == null ? kSubText : kPrimary,
              side: const BorderSide(color: kBorderColor),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CollectionReportNotice extends StatelessWidget {
  final IconData icon;
  final String message;

  const _CollectionReportNotice({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: kPrimary, size: 30),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectedTotalCard extends StatelessWidget {
  final double total;

  const _CollectedTotalCard({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.savings_rounded, color: kPrimary, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Total collected',
              style: TextStyle(
                color: Color(0xFF374151),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            _formatReportCurrency(total),
            style: const TextStyle(
              color: kPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }
}

class _IndividualCollectionRows extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _IndividualCollectionRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(children: rows.map(_mobileCard).toList());
        }
        return _reportTable(
          columns: const [
            DataColumn(label: Text('Contributor')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Method')),
            DataColumn(label: Text('Amount')),
            DataColumn(label: Text('Status')),
          ],
          rows: rows
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(_reportCell(row['contributor_name'])),
                    DataCell(_reportCell(_formatReportDate(_paymentDate(row)))),
                    DataCell(_reportCell('Not recorded')),
                    DataCell(
                      _reportCell(
                        _formatReportCurrency(_reportAmount(row['amount'])),
                      ),
                    ),
                    DataCell(_CollectionStatusPill(label: _paymentStatus(row))),
                  ],
                ),
              )
              .toList(),
          minWidth: 700,
        );
      },
    );
  }

  Widget _mobileCard(Map<String, dynamic> row) {
    return _CollectionDataCard(
      title: (row['contributor_name'] ?? 'Unknown contributor').toString(),
      trailing: _formatReportCurrency(_reportAmount(row['amount'])),
      details: [
        ('Date', _formatReportDate(_paymentDate(row))),
        ('Method', 'Not recorded'),
      ],
      status: _paymentStatus(row),
    );
  }
}

class _ConsolidatedCollectionRows extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _ConsolidatedCollectionRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(children: rows.map(_mobileCard).toList());
        }
        return _reportTable(
          columns: const [
            DataColumn(label: Text('Deceased Member')),
            DataColumn(label: Text('Collected')),
            DataColumn(label: Text('Collection Date')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Claim Status')),
          ],
          rows: rows
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(_reportCell(row['deceased_member'])),
                    DataCell(
                      _reportCell(_formatReportCurrency(row['collected'])),
                    ),
                    DataCell(_reportCell(_formatReportDate(row['date']))),
                    DataCell(_CollectionStatusPill(label: '${row['status']}')),
                    DataCell(
                      _CollectionStatusPill(label: '${row['claim_status']}'),
                    ),
                  ],
                ),
              )
              .toList(),
          minWidth: 720,
        );
      },
    );
  }

  Widget _mobileCard(Map<String, dynamic> row) {
    return _CollectionDataCard(
      title: (row['deceased_member'] ?? 'Unknown member').toString(),
      trailing: _formatReportCurrency(row['collected']),
      details: [
        ('Collection date', _formatReportDate(row['date'])),
        ('Claim status', '${row['claim_status']}'),
      ],
      status: '${row['status']}',
    );
  }
}

class _CollectionDataCard extends StatelessWidget {
  final String title;
  final String trailing;
  final List<(String, String)> details;
  final String status;

  const _CollectionDataCard({
    required this.title,
    required this.trailing,
    required this.details,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: kPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: const TextStyle(
                  color: kPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 126,
                    child: Text(
                      detail.$1,
                      style: const TextStyle(
                        color: kSubText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      detail.$2,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          _CollectionStatusPill(label: status),
        ],
      ),
    );
  }
}

class _CollectionStatusPill extends StatelessWidget {
  final String label;

  const _CollectionStatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase();
    final color =
        normalized.contains('paid') ||
            normalized.contains('collect') ||
            normalized.contains('release')
        ? const Color(0xFF15803D)
        : normalized.contains('pending') || normalized.contains('not filed')
        ? const Color(0xFFB45309)
        : const Color(0xFF475569);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Widget _reportTable({
  required List<DataColumn> columns,
  required List<DataRow> rows,
  required double minWidth,
}) {
  return Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorderColor),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            kPrimary.withValues(alpha: 0.06),
          ),
          headingTextStyle: const TextStyle(
            color: kPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
          dataTextStyle: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          columnSpacing: 20,
          horizontalMargin: 16,
          columns: columns,
          rows: rows,
        ),
      ),
    ),
  );
}

Widget _reportCell(Object? value) {
  return Text(
    '${value ?? '—'}',
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );
}

Object? _paymentDate(Map<String, dynamic> row) =>
    row['paid_at'] ?? row['created_at'];

String _paymentStatus(Map<String, dynamic> row) {
  final status = (row['status'] ?? 'Unknown').toString().trim();
  if (status.isEmpty) return 'Unknown';
  return status[0].toUpperCase() + status.substring(1);
}

double _reportAmount(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0;
}

String _formatReportCurrency(Object? value) =>
    '₱${_reportAmount(value).toStringAsFixed(2)}';

String _formatReportDate(Object? value) {
  if (value is DateTime) {
    return DateFormat('MMM d, yyyy').format(value.toLocal());
  }
  final date = DateTime.tryParse('${value ?? ''}');
  return date == null ? '—' : DateFormat('MMM d, yyyy').format(date.toLocal());
}

class _DisbursementActivityTable extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final String? error;
  final VoidCallback onRetry;

  const _DisbursementActivityTable({
    required this.activities,
    required this.error,
    required this.onRetry,
  });

  Widget _buildErrorState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFAD4CE)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFB42318),
            size: 26,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Disbursement activity could not be loaded',
                  style: TextStyle(
                    color: Color(0xFF912018),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Check your connection and try again.',
                  style: TextStyle(color: Color(0xFF7A271A), fontSize: 13),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB42318),
              side: const BorderSide(color: Color(0xFFE7A49A)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return _buildErrorState(context);
    }
    if (activities.isEmpty) {
      return _message('No disbursement activity has been recorded yet.');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: activities
                .map((activity) => _buildActivityCard(activity))
                .toList(),
          );
        }

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorderColor.withValues(alpha: 0.45)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                kPrimary.withValues(alpha: 0.06),
              ),
              columnSpacing: 24,
              horizontalMargin: 18,
              columns: const [
                DataColumn(label: Text('Beneficiary Name')),
                DataColumn(label: Text('Deceased Member')),
                DataColumn(label: Text('Amount Released')),
                DataColumn(label: Text('Released By')),
                DataColumn(label: Text('Date and Time Released')),
                DataColumn(label: Text('Status')),
              ],
              rows: activities.map((activity) {
                return DataRow(
                  cells: [
                    DataCell(_tableValue(activity['beneficiary_name'])),
                    DataCell(_tableValue(activity['deceased_member'])),
                    DataCell(_tableValue(_formatCurrency(activity['amount']))),
                    DataCell(_tableValue(activity['released_by'])),
                    DataCell(
                      _tableValue(_formatReleaseDate(activity['released_at'])),
                    ),
                    DataCell(_statusBadge(activity['status'])),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${activity['beneficiary_name']}',
                  style: const TextStyle(
                    color: kPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _formatCurrency(activity['amount']),
                style: const TextStyle(
                  color: kPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _detailLine('Deceased Member', activity['deceased_member']),
          _detailLine('Released By', activity['released_by']),
          _detailLine(
            'Date and Time Released',
            _formatReleaseDate(activity['released_at']),
          ),
          const SizedBox(height: 8),
          _statusBadge(activity['status']),
        ],
      ),
    );
  }

  Widget _detailLine(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: kSubText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${value ?? '—'}',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text, {Color? color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color ?? kSubText, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _tableValue(Object? value) {
    return Text(
      '${value ?? '—'}',
      style: const TextStyle(
        color: Colors.black87,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _statusBadge(Object? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${value ?? 'Released'}',
        style: const TextStyle(
          color: Color(0xFF2E7D32),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _formatCurrency(Object? value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse('${value ?? ''}') ?? 0;
    return '₱${amount.toStringAsFixed(2)}';
  }

  String _formatReleaseDate(Object? value) {
    final date = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (date == null) return 'Date unavailable';
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }
}

// Chart for Money Collected Per Collector (Monthly)
class _MoneyCollectedBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isWide;
  const _MoneyCollectedBarChart({required this.data, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentYear = now.year;
    final monthlyTotals = List<double>.filled(12, 0);

    for (final row in data) {
      final monthValue = (row['month'] ?? '').toString();
      final parts = monthValue.split('-');
      if (parts.length != 2) continue;

      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year != currentYear || month == null || month < 1 || month > 12) {
        continue;
      }

      final totalValue = row['total'];
      final total = totalValue is num
          ? totalValue.toDouble()
          : double.tryParse(totalValue.toString()) ?? 0;
      monthlyTotals[month - 1] += total;
    }

    final maxY = monthlyTotals.reduce((a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 100.0 : maxY * 1.25;
    final totalYear = monthlyTotals.fold(0.0, (sum, value) => sum + value);
    const monthLabels = [
      'J',
      'F',
      'M',
      'A',
      'M',
      'J',
      'J',
      'A',
      'S',
      'O',
      'N',
      'D',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Total: ₱${totalYear.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                  fontFamily: 'Montserrat',
                ),
              ),
            ),
            const Spacer(),
            Text(
              '$currentYear',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kSubText,
                fontFamily: 'OpenSans',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: isWide ? 220 : 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: chartMax,
              minY: 0,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '₱${rod.toY.toStringAsFixed(0)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= monthLabels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          monthLabels[idx],
                          style: TextStyle(
                            fontSize: isWide ? 11 : 10,
                            color: kSubText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: chartMax / 4,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.shade100, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(12, (i) {
                final value = monthlyTotals[i];
                final isCurrentMonth = i == now.month - 1;
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: value,
                      color: isCurrentMonth
                          ? kPrimary
                          : kPrimary.withValues(alpha: 0.45),
                      width: isWide ? 18 : 16,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: chartMax,
                        color: Colors.grey.shade100,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(12, (i) {
              final value = monthlyTotals[i];
              final isCurrentMonth = i == now.month - 1;
              return Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrentMonth
                      ? kPrimary.withValues(alpha: 0.1)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrentMonth
                        ? kPrimary.withValues(alpha: 0.3)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      monthLabels[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isCurrentMonth ? kPrimary : kSubText,
                      ),
                    ),
                    Text(
                      value > 0 ? '₱${value.toStringAsFixed(0)}' : '—',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isCurrentMonth ? kPrimary : kSubText,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// Chart for New Members Per Month
class _NewMembersBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isWide;
  const _NewMembersBarChart({required this.data, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final months = data.map((e) => e['month'] as String).toList()..sort();
    final counts = months
        .map((m) => data.firstWhere((e) => e['month'] == m)['count'] as int)
        .toList();
    final maxY = counts.isNotEmpty
        ? (counts.reduce((a, b) => a > b ? a : b) * 1.2)
        : 10.0;

    return SizedBox(
      height: isWide ? 200 : 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          groupsSpace: isWide ? 36 : 24,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: ((maxY ~/ 5) > 0 ? (maxY ~/ 5).toDouble() : 1.0),
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      fontSize: isWide ? 14 : 10,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  return idx >= 0 && idx < months.length
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            _formatMonthYear(months[idx]),
                            style: TextStyle(
                              fontSize: isWide ? 14 : 12,
                              color: Colors.black87,
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            horizontalInterval: ((maxY ~/ 5) > 0
                ? (maxY ~/ 5).toDouble()
                : 1.0),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(months.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: counts[i].toDouble(),
                  color: Colors.blueAccent,
                  width: isWide ? 26 : 22,
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
