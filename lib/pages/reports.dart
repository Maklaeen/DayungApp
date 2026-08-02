import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/Secretary/secretary_ui.dart';
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

  Future<Map<String, dynamic>> fetchPaymentFlowSummary({int? unitId}) async {
    var query = sb
        .from('payments')
        .select('amount, iscollectedbytreasurer, is_claimed, is_claimed_date');
    if (unitId != null) query.eq('dayung_unit_id', unitId);

    final rows = List<Map<String, dynamic>>.from(await query);
    return summarizePaymentFlowRows(rows);
  }

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

  /// Funds released per month (stub, ready for your table)
  Future<List<Map<String, dynamic>>> fetchFundsReleasedPerMonth({
    int? unitId,
  }) async {
    // blank
    return [];
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

String formatPhilippineDateTime(Object? value) {
  if (value == null) return '—';

  final rawValue = value.toString().trim();
  if (rawValue.isEmpty || rawValue == '—') return '—';

  DateTime? parsed;
  try {
    parsed = DateTime.parse(rawValue);
  } catch (_) {
    return rawValue;
  }

  final isUtcInput = rawValue.endsWith('Z') || rawValue.endsWith('z');
  final philippineTime = isUtcInput
      ? parsed.toUtc().add(const Duration(hours: 8))
      : parsed.add(const Duration(hours: 8));

  return DateFormat('MMM d, yyyy • h:mm a').format(philippineTime);
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

Map<String, dynamic> summarizePaymentFlowRows(List<Map<String, dynamic>> rows) {
  double inTotal = 0;
  double outTotal = 0;
  String? latestClaimDate;

  for (final row in rows) {
    final amount = double.tryParse(row['amount']?.toString() ?? '') ?? 0.0;
    if (_isTruthyFlag(row['iscollectedbytreasurer'])) {
      inTotal += amount;
    }

    if (_isTruthyFlag(row['is_claimed'])) {
      outTotal += amount;
      final dateValue = row['is_claimed_date']?.toString();
      if (dateValue != null && dateValue.isNotEmpty) {
        final parsedDate = DateTime.tryParse(dateValue);
        if (parsedDate != null) {
          final normalizedDate = parsedDate
              .toLocal()
              .toIso8601String()
              .split('T')
              .first;
          if (latestClaimDate == null ||
              normalizedDate.compareTo(latestClaimDate) > 0) {
            latestClaimDate = normalizedDate;
          }
        }
      }
    }
  }

  return {'in': inTotal, 'out': outTotal, 'date': latestClaimDate ?? '—'};
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
  Map<String, dynamic> paymentFlowSummary = const {
    'in': 0.0,
    'out': 0.0,
    'date': '—',
  };
  bool loading = true;
  pw.ThemeData? _pdfTheme;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => loading = true);
    moneyCollected = await service.fetchMoneyCollectedPerCollector(
      unitId: widget.unitId,
    );
    paymentFlowSummary = await service.fetchPaymentFlowSummary(
      unitId: widget.unitId,
    );
    // Pass unitId as required
    newMembers = widget.unitId != null
        ? await service.fetchNewMembersPerMonth(unitId: widget.unitId!)
        : [];
    setState(() => loading = false);
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
            final horizontalPadding = isWide
                ? constraints.maxWidth * 0.15
                : 20.0;
            final cardMaxWidth = isWide ? 600.0 : double.infinity;
            final sectionTitleFontSize = isWide ? 22.0 : 18.0;

            return Column(
              children: [
                SecretaryPageHeader(
                  title: 'Reports',
                  icon: Icons.bar_chart_rounded,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    isWide ? 48 : 32,
                    horizontalPadding,
                    isWide ? 24 : 24,
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
                            isWide ? 32 : 20,
                            horizontalPadding,
                            isWide ? 32 : 20,
                          ),
                          children: [
                            _buildExportButton(),
                            const SizedBox(height: 16),
                            Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: cardMaxWidth,
                                ),
                                child: _modernSectionCard(
                                  title: 'Payment Flow Summary',
                                  icon: Icons.swap_horiz_rounded,
                                  titleFontSize: sectionTitleFontSize,
                                  child: _PaymentFlowSummaryTable(
                                    summary: paymentFlowSummary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: cardMaxWidth,
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
                                constraints: BoxConstraints(
                                  maxWidth: cardMaxWidth,
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

class _PaymentFlowSummaryTable extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _PaymentFlowSummaryTable({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final inValue = (summary['in'] as num?)?.toDouble() ?? 0.0;
    final outValue = (summary['out'] as num?)?.toDouble() ?? 0.0;
    final dateValue = summary['date']?.toString() ?? '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.35)),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.06)),
            children: [
              _buildHeaderCell('IN'),
              _buildHeaderCell('OUT'),
              _buildHeaderCell('DATE/TIME'),
            ],
          ),
          TableRow(
            children: [
              _buildValueCell('₱${inValue.toStringAsFixed(2)}'),
              _buildValueCell('₱${outValue.toStringAsFixed(2)}'),
              _buildValueCell(formatPhilippineDateTime(dateValue)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: kPrimary,
        ),
      ),
    );
  }

  Widget _buildValueCell(String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
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
