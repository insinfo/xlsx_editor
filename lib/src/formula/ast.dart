/// AST de fórmulas Excel (forma canônica en-US).
library;

import 'package:xlsx_editor/src/util/cell_ref.dart';

/// Nó de expressão.
sealed class Expr {
  const Expr();
}

/// Literal numérico.
class NumberLit extends Expr {
  final double value;
  const NumberLit(this.value);
}

/// Literal de texto.
class StringLit extends Expr {
  final String value;
  const StringLit(this.value);
}

/// Literal booleano (TRUE/FALSE).
class BoolLit extends Expr {
  final bool value;
  const BoolLit(this.value);
}

/// Literal de erro ('#REF!', '#VALUE!', ...).
class ErrorLit extends Expr {
  final String code;
  const ErrorLit(this.code);
}

/// Referência de célula, opcionalmente qualificada por planilha.
/// row/col são 0-based; absRow/absCol indicam âncora `$`.
class RefExpr extends Expr {
  final String? sheet;
  final int row, col;
  final bool absRow, absCol;
  const RefExpr(this.sheet, this.row, this.col, this.absRow, this.absCol);
}

/// Intervalo retangular (cantos como escritos, sem normalização,
/// para preservar as âncoras `$` de cada canto).
class RangeExpr extends Expr {
  final String? sheet;
  final int r1, c1, r2, c2;
  final bool absR1, absC1, absR2, absC2;
  const RangeExpr(this.sheet, this.r1, this.c1, this.r2, this.c2, this.absR1,
      this.absC1, this.absR2, this.absC2);
}

/// Operador unário: '-' e '+' (prefixo), '%' (pós-fixo).
class UnaryExpr extends Expr {
  final String op;
  final Expr operand;
  const UnaryExpr(this.op, this.operand);
}

/// Operador binário: + - * / ^ & = <> < <= > >=
class BinaryExpr extends Expr {
  final String op;
  final Expr left, right;
  const BinaryExpr(this.op, this.left, this.right);
}

/// Chamada de função; [name] em MAIÚSCULAS en-US.
class FuncCall extends Expr {
  final String name;
  final List<Expr> args;
  const FuncCall(this.name, this.args);
}

/// Formata número no estilo "General" simplificado (inteiros sem `.0`).
String formatNumber(double v) {
  if (v.isNaN || v.isInfinite) return '#NUM!';
  if (v == v.truncateToDouble() && v.abs() < 1e15) {
    return v.truncate().toString();
  }
  return v.toString();
}

/// Gera o texto canônico en-US da expressão ('$' preservados,
/// nomes de planilha entre aspas quando necessário).
String exprToFormula(Expr e) => _write(e);

int _binPrec(String op) => switch (op) {
      '=' || '<>' || '<' || '<=' || '>' || '>=' => 1,
      '&' => 2,
      '+' || '-' => 3,
      '*' || '/' => 4,
      '^' => 5,
      _ => 1,
    };

int _prec(Expr e) => switch (e) {
      BinaryExpr(:final op) => _binPrec(op),
      UnaryExpr(:final op) => op == '%' ? 7 : 6,
      _ => 8,
    };

String _wrap(Expr e, int prec, {required bool strict}) {
  final s = _write(e);
  final ep = _prec(e);
  final need = strict ? ep <= prec : ep < prec;
  return need ? '($s)' : s;
}

String _write(Expr e) {
  switch (e) {
    case NumberLit(:final value):
      return formatNumber(value);
    case StringLit(:final value):
      return '"${value.replaceAll('"', '""')}"';
    case BoolLit(:final value):
      return value ? 'TRUE' : 'FALSE';
    case ErrorLit(:final code):
      return code;
    case RefExpr():
      return '${_sheetPrefix(e.sheet)}${_refText(e.row, e.col, e.absRow, e.absCol)}';
    case RangeExpr():
      return '${_sheetPrefix(e.sheet)}'
          '${_refText(e.r1, e.c1, e.absR1, e.absC1)}:'
          '${_refText(e.r2, e.c2, e.absR2, e.absC2)}';
    case UnaryExpr(:final op, :final operand):
      final inner = _wrap(operand, op == '%' ? 7 : 6, strict: false);
      return op == '%' ? '$inner%' : '$op$inner';
    case BinaryExpr(:final op, :final left, :final right):
      final p = _binPrec(op);
      return '${_wrap(left, p, strict: false)}$op${_wrap(right, p, strict: true)}';
    case FuncCall(:final name, :final args):
      return '$name(${args.map(_write).join(',')})';
  }
}

String _refText(int row, int col, bool absRow, bool absCol) =>
    '${absCol ? r'$' : ''}${colName(col)}${absRow ? r'$' : ''}${row + 1}';

String _sheetPrefix(String? sheet) {
  if (sheet == null) return '';
  if (_isSimpleSheetName(sheet)) return '$sheet!';
  return "'${sheet.replaceAll("'", "''")}'!";
}

/// Nome de planilha que dispensa aspas: letras/dígitos/underscore,
/// iniciando por letra e sem parecer referência A1.
bool _isSimpleSheetName(String s) {
  if (s.isEmpty) return false;
  final first = s.codeUnitAt(0);
  final firstOk = (first >= 0x41 && first <= 0x5A) ||
      (first >= 0x61 && first <= 0x7A) ||
      first >= 0x80 ||
      first == 0x5F;
  if (!firstOk) return false;
  for (var i = 1; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final ok = (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        (c >= 0x30 && c <= 0x39) ||
        c >= 0x80 ||
        c == 0x5F;
    if (!ok) return false;
  }
  // "A1", "XFD1048576" etc. precisariam de aspas.
  return CellRef.tryParse(s) == null;
}
