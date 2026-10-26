import 'package:flutter/material.dart';

class RecordDataTable extends StatelessWidget {
  const RecordDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.columnSpacing = 24,
    this.horizontalMargin = 16,
    this.minWidth = 0,
    this.dataRowMinHeight,
    this.dataRowMaxHeight,
    this.cardStyle = false,
    this.headingRowColor,
    this.headingTextStyle,
    this.dataTextStyle,
    this.showCheckboxColumn = true,
    this.fillAvailableWidth = false,
    this.modernStyle = true,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final double columnSpacing;
  final double horizontalMargin;
  final double minWidth;
  final double? dataRowMinHeight;
  final double? dataRowMaxHeight;
  final bool cardStyle;
  final Color? headingRowColor;
  final TextStyle? headingTextStyle;
  final TextStyle? dataTextStyle;
  final bool showCheckboxColumn;
  final bool fillAvailableWidth;
  final bool modernStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final styledRows = modernStyle
        ? rows.indexed
              .map((entry) {
                final (index, row) = entry;
                return DataRow(
                  key: row.key,
                  selected: row.selected,
                  onSelectChanged: row.onSelectChanged,
                  onLongPress: row.onLongPress,
                  color:
                      row.color ??
                      WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return colors.primary.withValues(alpha: 0.12);
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return colors.primary.withValues(alpha: 0.06);
                        }
                        return index.isEven
                            ? colors.surface
                            : (isDark
                                  ? colors.surfaceContainerLow
                                  : const Color(0xFFF5F8FC));
                      }),
                  cells: row.cells,
                );
              })
              .toList(growable: false)
        : rows;
    final table = DataTable(
      columnSpacing: columnSpacing,
      horizontalMargin: horizontalMargin,
      dataRowMinHeight: dataRowMinHeight ?? (modernStyle ? 72 : null),
      dataRowMaxHeight: dataRowMaxHeight ?? (modernStyle ? 144 : null),
      showCheckboxColumn: showCheckboxColumn,
      headingRowColor: WidgetStatePropertyAll(
        headingRowColor ??
            (modernStyle
                ? (isDark
                      ? colors.surfaceContainerHigh
                      : const Color(0xFFEAF2FC))
                : colors.surfaceContainerHighest.withValues(alpha: 0.55)),
      ),
      headingTextStyle:
          headingTextStyle ??
          (modernStyle
              ? TextStyle(
                  color: isDark ? colors.onSurface : const Color(0xFF0D47A1),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                )
              : theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                )),
      dataTextStyle:
          dataTextStyle ??
          (modernStyle
              ? TextStyle(
                  color: colors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                )
              : theme.textTheme.bodyMedium?.copyWith(color: colors.onSurface)),
      dividerThickness: 1,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: modernStyle
              ? colors.outlineVariant.withValues(alpha: 0.8)
              : colors.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      columns: columns,
      rows: styledRows,
    );

    final scrollableTable = LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final tableMinWidth = fillAvailableWidth || modernStyle
            ? minWidth > availableWidth
                  ? minWidth
                  : availableWidth
            : minWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: tableMinWidth > 0
              ? ConstrainedBox(
                  constraints: BoxConstraints(minWidth: tableMinWidth),
                  child: table,
                )
              : table,
        );
      },
    );

    if (!cardStyle && !modernStyle) return scrollableTable;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: scrollableTable,
      ),
    );
  }
}
