import 'package:excel/excel.dart';

/// Shared styling & layout helper for all Excel exports across the ERP
/// so every workbook has uniform headers, borders, zebra striping,
/// number formatting, and totals rows.
class ExcelStyleHelper {
  ExcelStyleHelper._();

  static final Border _headerBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('#071F40'),
  );

  static final Border _gridBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('#CBD5E1'),
  );

  static final Border _totalsTopBorder = Border(
    borderStyle: BorderStyle.Medium,
    borderColorHex: ExcelColor.fromHexString('#0A2E5C'),
  );

  static CellStyle _buildCellStyle({
    required bool bold,
    required int fontSize,
    required ExcelColor fontColorHex,
    required ExcelColor backgroundColorHex,
    required HorizontalAlign horizontalAlign,
    required Border topBorder,
    required Border bottomBorder,
    required Border leftBorder,
    required Border rightBorder,
    bool wrapText = false,
    bool isCurrency = false,
  }) {
    if (isCurrency) {
      return CellStyle(
        bold: bold,
        fontSize: fontSize,
        fontColorHex: fontColorHex,
        backgroundColorHex: backgroundColorHex,
        horizontalAlign: horizontalAlign,
        verticalAlign: VerticalAlign.Center,
        textWrapping: wrapText ? TextWrapping.WrapText : TextWrapping.Clip,
        numberFormat: NumFormat.standard_2,
        topBorder: topBorder,
        bottomBorder: bottomBorder,
        leftBorder: leftBorder,
        rightBorder: rightBorder,
      );
    }
    return CellStyle(
      bold: bold,
      fontSize: fontSize,
      fontColorHex: fontColorHex,
      backgroundColorHex: backgroundColorHex,
      horizontalAlign: horizontalAlign,
      verticalAlign: VerticalAlign.Center,
      textWrapping: wrapText ? TextWrapping.WrapText : TextWrapping.Clip,
      topBorder: topBorder,
      bottomBorder: bottomBorder,
      leftBorder: leftBorder,
      rightBorder: rightBorder,
    );
  }

  static CellStyle headerStyle() => _buildCellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#0A2E5C'),
        horizontalAlign: HorizontalAlign.Center,
        wrapText: true,
        topBorder: _headerBorder,
        bottomBorder: _headerBorder,
        leftBorder: _headerBorder,
        rightBorder: _headerBorder,
      );

  static CellStyle accentHeaderStyle() => _buildCellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#1FB5A8'),
        horizontalAlign: HorizontalAlign.Center,
        wrapText: true,
        topBorder: _headerBorder,
        bottomBorder: _headerBorder,
        leftBorder: _headerBorder,
        rightBorder: _headerBorder,
      );

  static CellStyle highlightRowStyle({bool isCurrency = false}) =>
      _buildCellStyle(
        bold: true,
        fontSize: 10,
        backgroundColorHex: ExcelColor.fromHexString('#E6F7F5'),
        fontColorHex: ExcelColor.fromHexString('#0A2E5C'),
        horizontalAlign:
            isCurrency ? HorizontalAlign.Center : HorizontalAlign.Right,
        isCurrency: isCurrency,
        topBorder: _gridBorder,
        bottomBorder: _gridBorder,
        leftBorder: _gridBorder,
        rightBorder: _gridBorder,
      );

  static CellStyle warningRowStyle({bool isCurrency = false}) =>
      _buildCellStyle(
        bold: true,
        fontSize: 10,
        backgroundColorHex: ExcelColor.fromHexString('#FEF3C7'),
        fontColorHex: ExcelColor.fromHexString('#92400E'),
        horizontalAlign:
            isCurrency ? HorizontalAlign.Center : HorizontalAlign.Right,
        isCurrency: isCurrency,
        topBorder: _gridBorder,
        bottomBorder: _gridBorder,
        leftBorder: _gridBorder,
        rightBorder: _gridBorder,
      );

  static CellStyle dangerRowStyle({bool isCurrency = false}) => _buildCellStyle(
        bold: true,
        fontSize: 10,
        backgroundColorHex: ExcelColor.fromHexString('#FEE2E2'),
        fontColorHex: ExcelColor.fromHexString('#991B1B'),
        horizontalAlign:
            isCurrency ? HorizontalAlign.Center : HorizontalAlign.Right,
        isCurrency: isCurrency,
        topBorder: _gridBorder,
        bottomBorder: _gridBorder,
        leftBorder: _gridBorder,
        rightBorder: _gridBorder,
      );

  static CellStyle totalsRowStyle({bool isCurrency = false}) => _buildCellStyle(
        bold: true,
        fontSize: 11,
        backgroundColorHex: ExcelColor.fromHexString('#E2E8F0'),
        fontColorHex: ExcelColor.fromHexString('#0A2E5C'),
        horizontalAlign: HorizontalAlign.Center,
        isCurrency: isCurrency,
        topBorder: _totalsTopBorder,
        bottomBorder: _totalsTopBorder,
        leftBorder: _gridBorder,
        rightBorder: _gridBorder,
      );

  static CellStyle dataCellStyle({
    required bool isOddRow,
    bool isCurrency = false,
    bool isCenter = false,
  }) =>
      _buildCellStyle(
        bold: false,
        fontSize: 10,
        backgroundColorHex: isOddRow
            ? ExcelColor.fromHexString('#F8FAFC')
            : ExcelColor.white,
        fontColorHex: ExcelColor.fromHexString('#0F172A'),
        horizontalAlign: (isCurrency || isCenter)
            ? HorizontalAlign.Center
            : HorizontalAlign.Right,
        isCurrency: isCurrency,
        topBorder: _gridBorder,
        bottomBorder: _gridBorder,
        leftBorder: _gridBorder,
        rightBorder: _gridBorder,
      );

  /// Appends a styled header row at index 0 and sets a comfortable row height.
  static void appendStyledHeader(
    Sheet sheet,
    List<String> titles, {
    CellStyle? style,
  }) {
    sheet.appendRow(titles.map((t) => TextCellValue(t)).toList());
    styleRow(sheet, 0, titles.length, style ?? headerStyle());
    sheet.setRowHeight(0, 28);
  }

  static void styleRow(
    Sheet sheet,
    int rowIndex,
    int colCount,
    CellStyle style,
  ) {
    for (var col = 0; col < colCount; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex),
      );
      cell.cellStyle = style;
    }
  }

  /// Applies clean zebra striping, grid borders, and currency formats to data rows.
  static void styleDataRows(
    Sheet sheet, {
    required int startRow,
    required int rowCount,
    required int colCount,
    Set<int> currencyCols = const {},
    Set<int> centerCols = const {},
  }) {
    for (var offset = 0; offset < rowCount; offset++) {
      final rowIdx = startRow + offset;
      final isOdd = offset.isOdd;
      sheet.setRowHeight(rowIdx, 22);
      for (var col = 0; col < colCount; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx),
        );
        cell.cellStyle = dataCellStyle(
          isOddRow: isOdd,
          isCurrency: currencyCols.contains(col),
          isCenter: centerCols.contains(col),
        );
      }
    }
  }

  /// Appends a bold totals row at the bottom of a table.
  static void appendTotalsRow(
    Sheet sheet, {
    required int rowIndex,
    required List<CellValue?> cells,
    Set<int> currencyCols = const {},
  }) {
    sheet.appendRow(cells);
    sheet.setRowHeight(rowIndex, 25);
    for (var col = 0; col < cells.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex),
      );
      cell.cellStyle = totalsRowStyle(isCurrency: currencyCols.contains(col));
    }
  }

  static void setColumnWidths(Sheet sheet, List<double> widths) {
    for (var col = 0; col < widths.length; col++) {
      sheet.setColumnWidth(col, widths[col]);
    }
  }
}
