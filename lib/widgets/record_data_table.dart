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
    this.headingRowHeight,
    this.dividerThickness = 1,
    this.border,
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
  final double? headingRowHeight;
  final double dividerThickness;
  final TableBorder? border;
  final bool cardStyle;
  final Color? headingRowColor;
  final TextStyle? headingTextStyle;
  final TextStyle? dataTextStyle;
  final bool showCheckboxColumn;
  final bool fillAvailableWidth;
  final bool modernStyle;

  @override
  Widget build(BuildContext context) {
    assert(
      rows.every((row) => row.cells.length == columns.length),
      'Each row must contain one cell for every column.',
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final effectiveHeadingTextStyle =
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
              ));
    final effectiveDataTextStyle =
        dataTextStyle ??
        (modernStyle
            ? TextStyle(
                color: colors.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'OpenSans',
              )
            : theme.textTheme.bodyMedium?.copyWith(color: colors.onSurface));
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
      headingRowHeight: headingRowHeight,
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
      headingTextStyle: effectiveHeadingTextStyle,
      dataTextStyle: effectiveDataTextStyle,
      dividerThickness: dividerThickness,
      border:
          border ??
          TableBorder(
            horizontalInside: BorderSide(
              color: modernStyle
                  ? colors.outlineVariant.withValues(alpha: 0.8)
                  : colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
      columns: columns,
      rows: styledRows,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 840) {
          return _buildMobileCards(
            context,
            styledRows,
            effectiveDataTextStyle ??
                Theme.of(context).textTheme.bodyMedium ??
                const TextStyle(),
            colors,
            effectiveHeadingTextStyle,
          );
        }

        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final tableMinWidth = fillAvailableWidth || modernStyle
            ? minWidth > availableWidth
                  ? minWidth
                  : availableWidth
            : minWidth;
        final scrollableTable = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: tableMinWidth > 0
              ? ConstrainedBox(
                  constraints: BoxConstraints(minWidth: tableMinWidth),
                  child: table,
                )
              : table,
        );

        if (!cardStyle && !modernStyle) return scrollableTable;

        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.8),
            ),
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
      },
    );
  }

  Widget _buildMobileCards(
    BuildContext context,
    List<DataRow> rows,
    TextStyle dataStyle,
    ColorScheme colors,
    TextStyle? headingStyle,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final labelStyle =
        headingStyle ??
        Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        );
    final selectableRows =
        showCheckboxColumn && rows.any((row) => row.onSelectChanged != null);

    return Column(
      children: [
        for (final row in rows)
          _buildMobileCard(row, labelStyle, dataStyle, colors, selectableRows),
      ],
    );
  }

  Widget _buildMobileCard(
    DataRow row,
    TextStyle? labelStyle,
    TextStyle dataStyle,
    ColorScheme colors,
    bool selectableRows,
  ) {
    final rowColor = row.color?.resolve(
      row.selected ? {WidgetState.selected} : const <WidgetState>{},
    );

    return Container(
      key: row.key,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:
            rowColor ??
            (row.selected
                ? colors.primary.withValues(alpha: 0.08)
                : colors.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: row.selected
              ? colors.primary.withValues(alpha: 0.35)
              : colors.outlineVariant.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: row.onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selectableRows && row.onSelectChanged != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Checkbox(
                    value: row.selected,
                    onChanged: row.onSelectChanged,
                  ),
                ),
              for (var index = 0; index < columns.length; index++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: index == columns.length - 1 ? 0 : 14,
                  ),
                  child: _buildMobileCell(
                    columns[index],
                    row.cells[index],
                    labelStyle,
                    dataStyle,
                    colors,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCell(
    DataColumn column,
    DataCell cell,
    TextStyle? labelStyle,
    TextStyle dataStyle,
    ColorScheme colors,
  ) {
    final alignment = column.numeric
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final value = DefaultTextStyle(
      style: dataStyle,
      child: Opacity(
        opacity: cell.placeholder ? 0.6 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: cell.child),
            if (cell.showEditIcon) ...[
              const SizedBox(width: 8),
              Icon(Icons.edit, size: 18, color: colors.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
    final cellContent = Align(alignment: alignment, child: value);
    final interactiveCell =
        cell.onTap != null ||
        cell.onLongPress != null ||
        cell.onDoubleTap != null ||
        cell.onTapDown != null ||
        cell.onTapCancel != null;

    return Column(
      crossAxisAlignment: column.numeric
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        DefaultTextStyle(
          style: labelStyle ?? const TextStyle(fontWeight: FontWeight.w700),
          child: column.label,
        ),
        const SizedBox(height: 5),
        if (interactiveCell)
          InkWell(
            onTap: cell.onTap,
            onLongPress: cell.onLongPress,
            onDoubleTap: cell.onDoubleTap,
            onTapDown: cell.onTapDown,
            onTapCancel: cell.onTapCancel,
            child: cellContent,
          )
        else
          cellContent,
      ],
    );
  }
}
