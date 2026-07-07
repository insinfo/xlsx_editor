/// Modelo de dados do workbook: planilhas, células (grade esparsa), merges.
library;

import '../util/cell_ref.dart';
import 'styles.dart';

/// Valor efetivo de uma célula.
sealed class CellValue {
  const CellValue();
}

class NumberValue extends CellValue {
  final double value;
  const NumberValue(this.value);
}

class TextValue extends CellValue {
  final String value;
  const TextValue(this.value);
}

class BoolValue extends CellValue {
  final bool value;
  const BoolValue(this.value);
}

class ErrorValue extends CellValue {
  final String code; // '#DIV/0!', '#REF!', ...
  const ErrorValue(this.code);
}

class Cell {
  CellValue? value;

  /// Fórmula canônica en-US, sem '=' inicial; null se não é fórmula.
  String? formula;
  bool isArrayFormula;

  /// Índice em StyleTable.cellXfs.
  int styleIndex;

  /// Cache do texto formatado (invalidada em qualquer mudança).
  String? formattedCache;
  String? formattedColorCache;

  Cell({this.value, this.formula, this.isArrayFormula = false, this.styleIndex = 0});

  bool get isEmpty => value == null && formula == null;

  /// Valor cru para o motor de fórmulas/format: double|String|bool|null.
  Object? get raw => switch (value) {
        NumberValue(:final value) => value,
        TextValue(:final value) => value,
        BoolValue(:final value) => value,
        ErrorValue(:final code) => code,
        null => null,
      };

  void invalidateFormat() {
    formattedCache = null;
    formattedColorCache = null;
  }
}

/// Propriedades de uma linha.
class RowProps {
  double? height; // pontos; null = default da planilha
  bool hidden;
  int? styleIndex; // customFormat

  RowProps({this.height, this.hidden = false, this.styleIndex});
}

/// Propriedades de uma faixa de colunas (elemento <col>).
class ColProps {
  double? width; // largura OOXML em "chars"; null = default
  bool hidden;
  int? styleIndex;

  ColProps({this.width, this.hidden = false, this.styleIndex});
}

class Worksheet {
  String name;

  /// Grade esparsa: chave = CellRef.packed.
  final Map<int, Cell> cells = {};

  final Map<int, RowProps> rowProps = {};
  final Map<int, ColProps> colProps = {};
  final List<CellRange> merges = [];

  /// Índice rápido: célula coberta (packed) -> merge que a cobre.
  final Map<int, CellRange> _mergeByCell = {};

  double defaultRowHeightPt = 15;
  double defaultColWidthChars = 8.43;
  bool showGridLines = true;
  double zoomScale = 1.0;

  /// Extensão usada (para dimension e para o tamanho de scroll).
  int maxRow = 0;
  int maxCol = 0;

  Worksheet(this.name);

  Cell? cellAt(int row, int col) => cells[CellRef(row, col).packed];

  Cell ensureCell(int row, int col) {
    final key = CellRef(row, col).packed;
    final existing = cells[key];
    if (existing != null) return existing;
    final cell = Cell();
    cells[key] = cell;
    if (row > maxRow) maxRow = row;
    if (col > maxCol) maxCol = col;
    return cell;
  }

  /// Merge que cobre (row,col), se houver.
  CellRange? mergeAt(int row, int col) => _mergeByCell[CellRef(row, col).packed];

  void addMerge(CellRange range) {
    merges.add(range);
    for (var r = range.r1; r <= range.r2; r++) {
      for (var c = range.c1; c <= range.c2; c++) {
        _mergeByCell[CellRef(r, c).packed] = range;
      }
    }
    if (range.r2 > maxRow) maxRow = range.r2;
    if (range.c2 > maxCol) maxCol = range.c2;
  }

  void removeMerge(CellRange range) {
    merges.removeWhere((m) => m == range);
    for (var r = range.r1; r <= range.r2; r++) {
      for (var c = range.c1; c <= range.c2; c++) {
        _mergeByCell.remove(CellRef(r, c).packed);
      }
    }
  }

  /// Estilo efetivo de uma célula (célula > linha > coluna > default).
  int effectiveStyleIndex(int row, int col) {
    final cell = cellAt(row, col);
    if (cell != null && cell.styleIndex != 0) return cell.styleIndex;
    final rp = rowProps[row];
    if (rp?.styleIndex != null) return rp!.styleIndex!;
    final cp = colProps[col];
    if (cp?.styleIndex != null) return cp!.styleIndex!;
    return cell?.styleIndex ?? 0;
  }
}

/// Imagem ancorada (xdr:twoCellAnchor) de uma planilha.
class SheetImage {
  final int fromRow, fromCol, toRow, toCol;
  final double fromRowOff, fromColOff, toRowOff, toColOff; // EMU
  final String mediaPath; // ex.: xl/media/image1.jpeg
  const SheetImage({
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
    this.fromRowOff = 0,
    this.fromColOff = 0,
    this.toRowOff = 0,
    this.toColOff = 0,
    required this.mediaPath,
  });
}

class Workbook {
  final List<Worksheet> sheets = [];
  final Map<String, List<SheetImage>> imagesBySheet = {};
  StyleTable styles = StyleTable();
  Theme theme = Theme.fallback();
  final List<String> sharedStrings = [];
  int activeSheet = 0;

  Worksheet? sheetByName(String name) {
    for (final s in sheets) {
      if (s.name == name) return s;
    }
    return null;
  }

  int sheetIndexByName(String name) {
    for (var i = 0; i < sheets.length; i++) {
      if (sheets[i].name.toUpperCase() == name.toUpperCase()) return i;
    }
    return -1;
  }
}
