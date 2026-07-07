/// Layout de eixos: converte índices de linha/coluna em pixels via prefix
/// sums, com busca binária para hit-test e cálculo do intervalo visível.
library;

import '../model/workbook.dart';
import '../util/cell_ref.dart';

/// Conversões de unidade OOXML -> px (96 dpi).
double colWidthCharsToPx(double chars) => (chars * 7).roundToDouble() + 5;
double rowHeightPtToPx(double pt) => (pt * 96 / 72).roundToDouble();

class AxisLayout {
  final List<double> _prefix; // _prefix[i] = soma de tamanhos [0, i)
  final double defaultSize;
  final int count;

  AxisLayout._(this._prefix, this.defaultSize, this.count);

  factory AxisLayout(
      int count, double defaultSize, double? Function(int) sizeOf) {
    final prefix = List<double>.filled(count + 1, 0);
    var acc = 0.0;
    for (var i = 0; i < count; i++) {
      prefix[i] = acc;
      acc += sizeOf(i) ?? defaultSize;
    }
    prefix[count] = acc;
    return AxisLayout._(prefix, defaultSize, count);
  }

  double get total => _prefix[count];

  double posOf(int index) {
    if (index <= 0) return 0;
    if (index >= count) return total + (index - count) * defaultSize;
    return _prefix[index];
  }

  double sizeOf(int index) {
    if (index < 0) return 0;
    if (index >= count) return defaultSize;
    return _prefix[index + 1] - _prefix[index];
  }

  /// Índice cuja faixa contém o pixel [px] (>=0). Busca binária O(log n).
  int indexAt(double px) {
    if (px <= 0) return 0;
    if (px >= total) return count + ((px - total) ~/ defaultSize);
    var lo = 0, hi = count - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_prefix[mid] <= px) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// Layout completo de uma planilha (recriado quando tamanhos mudam).
class SheetLayout {
  final Worksheet sheet;
  late AxisLayout rows;
  late AxisLayout cols;

  /// Linhas/colunas navegáveis (região de scroll), além do usado.
  late int rowCount;
  late int colCount;

  SheetLayout(this.sheet) {
    rebuild();
  }

  void rebuild() {
    rowCount = sheet.maxRow + 60;
    colCount = (sheet.maxCol + 15).clamp(26, 16384);
    final defRowPx = rowHeightPtToPx(sheet.defaultRowHeightPt);
    final defColPx = colWidthCharsToPx(sheet.defaultColWidthChars);
    rows = AxisLayout(rowCount, defRowPx, (r) {
      final p = sheet.rowProps[r];
      if (p == null) return null;
      if (p.hidden) return 0;
      final h = p.height;
      return h != null ? rowHeightPtToPx(h) : null;
    });
    cols = AxisLayout(colCount, defColPx, (c) {
      final p = sheet.colProps[c];
      if (p == null) return null;
      if (p.hidden) return 0;
      final w = p.width;
      return w != null ? colWidthCharsToPx(w) : null;
    });
  }

  double get totalWidth => cols.total;
  double get totalHeight => rows.total;

  /// Retângulo px de uma célula, expandido se for âncora de merge.
  ({double x, double y, double w, double h}) cellRect(int row, int col) {
    final merge = sheet.mergeAt(row, col);
    if (merge != null) {
      final x = cols.posOf(merge.c1);
      final y = rows.posOf(merge.r1);
      return (
        x: x,
        y: y,
        w: cols.posOf(merge.c2 + 1) - x,
        h: rows.posOf(merge.r2 + 1) - y,
      );
    }
    return (
      x: cols.posOf(col),
      y: rows.posOf(row),
      w: cols.sizeOf(col),
      h: rows.sizeOf(row),
    );
  }

  /// Célula sob o ponto px (coordenadas de conteúdo, sem headers).
  CellRef cellAtPoint(double x, double y) =>
      CellRef(rows.indexAt(y), cols.indexAt(x));
}
