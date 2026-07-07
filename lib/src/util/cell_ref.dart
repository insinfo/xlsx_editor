/// Utilitários de referência de célula (notação A1) e intervalos.
library;

/// Converte índice de coluna 0-based para letras ("A", "B", ..., "AA").
String colName(int col) {
  var c = col;
  final sb = StringBuffer();
  while (c >= 0) {
    sb.write(String.fromCharCode(0x41 + (c % 26)));
    c = (c ~/ 26) - 1;
  }
  return sb.toString().split('').reversed.join();
}

/// Converte letras de coluna ("A", "AA") para índice 0-based.
int colIndex(String name) {
  var result = 0;
  for (var i = 0; i < name.length; i++) {
    final ch = name.codeUnitAt(i);
    if (ch < 0x41 || ch > 0x5A) break;
    result = result * 26 + (ch - 0x40);
  }
  return result - 1;
}

/// Referência imutável de célula (row/col 0-based) empacotada em um int.
extension type const CellRef._(int packed) {
  const CellRef(int row, int col) : this._((row << 15) | col);

  const CellRef.fromPacked(int packed) : this._(packed);

  int get row => packed >> 15;
  int get col => packed & 0x7FFF;

  /// Interpreta "B7" (ignora cifrões de ancoragem).
  static CellRef? tryParse(String text) {
    var i = 0;
    final s = text.trim();
    if (i < s.length && s.codeUnitAt(i) == 0x24) i++; // $
    var colStart = i;
    while (i < s.length && _isAlpha(s.codeUnitAt(i))) {
      i++;
    }
    if (i == colStart) return null;
    final col = colIndex(s.substring(colStart, i).toUpperCase());
    if (i < s.length && s.codeUnitAt(i) == 0x24) i++; // $
    final rowStart = i;
    while (i < s.length && _isDigit(s.codeUnitAt(i))) {
      i++;
    }
    if (i == rowStart || i != s.length) return null;
    final row = int.parse(s.substring(rowStart)) - 1;
    if (row < 0 || col < 0) return null;
    return CellRef(row, col);
  }

  String get a1 => '${colName(col)}${row + 1}';

  CellRef offset(int dRow, int dCol) => CellRef(row + dRow, col + dCol);
}

bool _isAlpha(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Intervalo retangular inclusivo de células.
class CellRange {
  final int r1, c1, r2, c2;

  const CellRange(this.r1, this.c1, this.r2, this.c2);

  factory CellRange.normalized(int r1, int c1, int r2, int c2) => CellRange(
        r1 < r2 ? r1 : r2,
        c1 < c2 ? c1 : c2,
        r1 > r2 ? r1 : r2,
        c1 > c2 ? c1 : c2,
      );

  factory CellRange.single(CellRef ref) =>
      CellRange(ref.row, ref.col, ref.row, ref.col);

  /// Interpreta "A1:B7" ou "A1".
  static CellRange? tryParse(String text) {
    final parts = text.split(':');
    final a = CellRef.tryParse(parts[0]);
    if (a == null) return null;
    if (parts.length == 1) return CellRange.single(a);
    final b = CellRef.tryParse(parts[1]);
    if (b == null) return null;
    return CellRange.normalized(a.row, a.col, b.row, b.col);
  }

  bool contains(int row, int col) =>
      row >= r1 && row <= r2 && col >= c1 && col <= c2;

  bool intersects(CellRange other) =>
      r1 <= other.r2 && r2 >= other.r1 && c1 <= other.c2 && c2 >= other.c1;

  int get rowCount => r2 - r1 + 1;
  int get colCount => c2 - c1 + 1;
  bool get isSingle => r1 == r2 && c1 == c2;
  CellRef get anchor => CellRef(r1, c1);

  String get a1 => isSingle
      ? CellRef(r1, c1).a1
      : '${CellRef(r1, c1).a1}:${CellRef(r2, c2).a1}';

  @override
  bool operator ==(Object other) =>
      other is CellRange &&
      r1 == other.r1 &&
      c1 == other.c1 &&
      r2 == other.r2 &&
      c2 == other.c2;

  @override
  int get hashCode => Object.hash(r1, c1, r2, c2);

  @override
  String toString() => a1;
}
