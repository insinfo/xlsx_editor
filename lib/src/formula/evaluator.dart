/// Avaliador de expressões de fórmula.
///
/// Valores: double | String | bool | null (vazio) | [FormulaError] |
/// [ArrayValue] (modo matricial).
library;

import 'dart:math' as math;

import 'ast.dart';

/// Erro de fórmula como valor
/// (#DIV/0!, #VALUE!, #REF!, #NAME?, #NUM!, #N/A, #CYCLE!).
class FormulaError {
  final String code;
  const FormulaError(this.code);

  @override
  bool operator ==(Object other) => other is FormulaError && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// Matriz 2D de valores (resultado de intervalos e operações em modo array).
class ArrayValue {
  final List<List<Object?>> rows;
  const ArrayValue(this.rows);

  int get rowCount => rows.length;
  int get colCount => rows.isEmpty ? 0 : rows[0].length;
  Object? at(int r, int c) => rows[r][c];
}

/// Fonte de valores de células para o avaliador.
abstract class ValueLookup {
  /// Índice da planilha pelo nome; -1 se não existir.
  int sheetIndexByName(String name);

  /// Valor efetivo da célula (double | String | bool | FormulaError | null).
  Object? cellValue(int sheet, int row, int col);
}

const _errValue = FormulaError('#VALUE!');
const _errDiv0 = FormulaError('#DIV/0!');
const _errRef = FormulaError('#REF!');
const _errName = FormulaError('#NAME?');
const _errNum = FormulaError('#NUM!');
const _errNA = FormulaError('#N/A');

/// Avalia uma AST no contexto de uma planilha.
class Evaluator {
  final ValueLookup lookup;

  /// Planilha padrão para referências sem qualificação.
  final int contextSheet;

  /// Modo de fórmula matricial (CSE): intervalos viram arrays e
  /// operadores/IF distribuem elemento a elemento.
  final bool arrayMode;

  Evaluator(this.lookup, this.contextSheet, {this.arrayMode = false});

  Object? eval(Expr e) {
    switch (e) {
      case NumberLit(:final value):
        return value;
      case StringLit(:final value):
        return value;
      case BoolLit(:final value):
        return value;
      case ErrorLit(:final code):
        return FormulaError(code);
      case RefExpr():
        return _evalRef(e);
      case RangeExpr():
        return _evalRange(e);
      case UnaryExpr():
        return _evalUnary(e);
      case BinaryExpr():
        return _evalBinary(e);
      case FuncCall():
        return _evalFunc(e);
    }
  }

  // ---------------------------------------------------------------- refs

  int _resolveSheet(String? name) =>
      name == null ? contextSheet : lookup.sheetIndexByName(name);

  /// Normaliza valores vindos do modelo (int -> double, por segurança).
  Object? _norm(Object? v) => v is num && v is! double ? v.toDouble() : v;

  Object? _evalRef(RefExpr e) {
    final s = _resolveSheet(e.sheet);
    if (s < 0) return _errRef;
    return _norm(lookup.cellValue(s, e.row, e.col));
  }

  Object? _evalRange(RangeExpr e) {
    final s = _resolveSheet(e.sheet);
    if (s < 0) return _errRef;
    final r1 = math.min(e.r1, e.r2), r2 = math.max(e.r1, e.r2);
    final c1 = math.min(e.c1, e.c2), c2 = math.max(e.c1, e.c2);
    final rows = <List<Object?>>[];
    for (var r = r1; r <= r2; r++) {
      final row = <Object?>[];
      for (var c = c1; c <= c2; c++) {
        row.add(_norm(lookup.cellValue(s, r, c)));
      }
      rows.add(row);
    }
    return ArrayValue(rows);
  }

  /// Colapsa array 1x1 em posição escalar; array maior vira #VALUE!.
  Object? _scalar(Object? v) {
    if (v is ArrayValue) {
      if (v.rowCount == 1 && v.colCount == 1) return v.at(0, 0);
      return _errValue;
    }
    return v;
  }

  // ----------------------------------------------------------- operadores

  Object? _evalUnary(UnaryExpr e) {
    final v = eval(e.operand);
    if (arrayMode && v is ArrayValue) {
      return _broadcast([v], (xs) => _applyUnary(e.op, xs[0]));
    }
    return _applyUnary(e.op, _scalar(v));
  }

  Object? _applyUnary(String op, Object? v) {
    if (v is FormulaError) return v;
    switch (op) {
      case '+':
        return v;
      case '-':
        final n = _toNumber(v);
        return n is double ? -n : n;
      case '%':
        final n = _toNumber(v);
        return n is double ? n / 100 : n;
    }
    return _errValue;
  }

  Object? _evalBinary(BinaryExpr e) {
    final a = eval(e.left);
    final b = eval(e.right);
    if (arrayMode && (a is ArrayValue || b is ArrayValue)) {
      return _broadcast([a, b], (xs) => _applyBinary(e.op, xs[0], xs[1]));
    }
    return _applyBinary(e.op, _scalar(a), _scalar(b));
  }

  Object? _applyBinary(String op, Object? a, Object? b) {
    if (a is FormulaError) return a;
    if (b is FormulaError) return b;
    switch (op) {
      case '&':
        return _toText(a) + _toText(b);
      case '=' || '<>' || '<' || '<=' || '>' || '>=':
        final cmp = _compare(a, b);
        return switch (op) {
          '=' => cmp == 0,
          '<>' => cmp != 0,
          '<' => cmp < 0,
          '<=' => cmp <= 0,
          '>' => cmp > 0,
          _ => cmp >= 0,
        };
      default:
        final x = _toNumber(a);
        if (x is! double) return x;
        final y = _toNumber(b);
        if (y is! double) return y;
        switch (op) {
          case '+':
            return x + y;
          case '-':
            return x - y;
          case '*':
            return x * y;
          case '/':
            return y == 0 ? _errDiv0 : x / y;
          case '^':
            if (x == 0 && y == 0) return _errNum;
            if (x == 0 && y < 0) return _errDiv0;
            final r = math.pow(x, y).toDouble();
            if (r.isNaN || r.isInfinite) return _errNum;
            return r;
        }
        return _errValue;
    }
  }

  /// Distribuição elemento a elemento com broadcast (escalares e
  /// linhas/colunas unitárias são replicados).
  Object? _broadcast(List<Object?> vs, Object? Function(List<Object?>) f) {
    var rows = 1, cols = 1;
    for (final v in vs) {
      if (v is ArrayValue) {
        rows = math.max(rows, v.rowCount);
        cols = math.max(cols, v.colCount);
      }
    }
    Object? pick(Object? v, int r, int c) {
      if (v is! ArrayValue) return v;
      final rr = v.rowCount == 1 ? 0 : r;
      final cc = v.colCount == 1 ? 0 : c;
      if (rr >= v.rowCount || cc >= v.colCount) return _errNA;
      return v.at(rr, cc);
    }

    final out = <List<Object?>>[];
    for (var r = 0; r < rows; r++) {
      final line = <Object?>[];
      for (var c = 0; c < cols; c++) {
        line.add(f([for (final v in vs) pick(v, r, c)]));
      }
      out.add(line);
    }
    return ArrayValue(out);
  }

  // ------------------------------------------------------------- coerções

  /// Coerção numérica: null->0, bool->1/0, texto numérico -> número,
  /// texto não numérico -> #VALUE!. Retorna double ou FormulaError.
  Object _toNumber(Object? v) {
    if (v is FormulaError) return v;
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is bool) return v ? 1.0 : 0.0;
    if (v is String) {
      final d = double.tryParse(v.trim());
      return d ?? _errValue;
    }
    return _errValue;
  }

  /// Coerção para texto (concatenação `&`).
  String _toText(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is bool) return v ? 'TRUE' : 'FALSE';
    if (v is double) return formatNumber(v);
    return '';
  }

  /// Coerção booleana. Retorna bool ou FormulaError.
  Object _toBool(Object? v) {
    if (v is FormulaError) return v;
    if (v is bool) return v;
    if (v is double) return v != 0;
    if (v == null) return false;
    if (v is String) {
      final u = v.trim().toUpperCase();
      if (u == 'TRUE') return true;
      if (u == 'FALSE') return false;
      return _errValue;
    }
    return _errValue;
  }

  /// Comparação Excel: números < textos < bools; textos sem diferenciar
  /// maiúsculas; célula vazia equivale a 0, "" ou FALSE conforme o par.
  int _compare(Object? a, Object? b) {
    var x = a ?? _emptyLike(b);
    var y = b ?? _emptyLike(a);
    int rank(Object v) => v is bool
        ? 2
        : v is String
            ? 1
            : 0;
    final rx = rank(x), ry = rank(y);
    if (rx != ry) return rx - ry;
    if (x is double && y is double) {
      if (x < y) return -1;
      if (x > y) return 1;
      return 0;
    }
    if (x is String && y is String) {
      return x.toUpperCase().compareTo(y.toUpperCase());
    }
    if (x is bool && y is bool) {
      return (x ? 1 : 0) - (y ? 1 : 0);
    }
    return 0;
  }

  Object _emptyLike(Object? other) {
    if (other is String) return '';
    if (other is bool) return false;
    return 0.0;
  }

  // -------------------------------------------------------------- funções

  Object? _evalFunc(FuncCall f) {
    switch (f.name) {
      case 'IF':
        return _fnIf(f.args);
      case 'IFERROR':
        return _fnIfError(f.args);
      case 'AND' || 'OR':
        return _fnAndOr(f.args, f.name == 'AND');
      case 'NOT':
        return _fnNot(f.args);
      case 'SUM':
        return _fnSum(f.args);
      case 'AVERAGE':
        return _fnAverage(f.args);
      case 'MIN' || 'MAX':
        return _fnMinMax(f.args, f.name == 'MIN');
      case 'COUNT':
        return _fnCount(f.args);
      case 'COUNTA':
        return _fnCountA(f.args);
      case 'MEDIAN':
        return _fnMedian(f.args);
      case 'ROUND':
        return _fnRound(f.args);
      case 'ABS':
        return _fnAbs(f.args);
      case 'AVERAGEIF' || 'SUMIF' || 'COUNTIF':
        return _fnCriteria(f.name, f.args);
      default:
        return _errName;
    }
  }

  /// IF é preguiçoso: só o ramo tomado é avaliado (exceto condição-array).
  Object? _fnIf(List<Expr> args) {
    if (args.length < 2 || args.length > 3) return _errValue;
    final cond = eval(args[0]);
    if (arrayMode && cond is ArrayValue) {
      // Condição-array: distribui elemento a elemento; else omitido = FALSE.
      final thenV = eval(args[1]);
      final elseV = args.length > 2 ? eval(args[2]) : false;
      return _broadcast([cond, thenV, elseV], (xs) {
        final b = _toBool(xs[0]);
        if (b is FormulaError) return b;
        return (b as bool) ? xs[1] : xs[2];
      });
    }
    final c = _scalar(cond);
    final b = _toBool(c);
    if (b is FormulaError) return b;
    if (b as bool) return eval(args[1]);
    return args.length > 2 ? eval(args[2]) : false;
  }

  Object? _fnIfError(List<Expr> args) {
    if (args.length != 2) return _errValue;
    final v = eval(args[0]);
    if (v is FormulaError) return eval(args[1]);
    return v;
  }

  Object? _fnAndOr(List<Expr> args, bool isAnd) {
    if (args.isEmpty) return _errValue;
    bool? acc;
    bool combine(bool b) {
      final prev = acc;
      if (prev == null) return b;
      return isAnd ? (prev && b) : (prev || b);
    }

    for (final arg in args) {
      final v = eval(arg);
      if (v is FormulaError) return v;
      if (v is ArrayValue) {
        for (final row in v.rows) {
          for (final cell in row) {
            if (cell is FormulaError) return cell;
            if (cell is bool) acc = combine(cell);
            if (cell is double) acc = combine(cell != 0);
            // textos e vazios em intervalos são ignorados
          }
        }
      } else {
        if (v == null && arg is RefExpr) continue; // referência vazia
        final b = _toBool(v);
        if (b is FormulaError) return b;
        acc = combine(b as bool);
      }
    }
    return acc ?? _errValue;
  }

  Object? _fnNot(List<Expr> args) {
    if (args.length != 1) return _errValue;
    final b = _toBool(_scalar(eval(args[0])));
    if (b is FormulaError) return b;
    return !(b as bool);
  }

  /// Coleta números para agregação: em intervalos/arrays somente doubles
  /// (texto/bool/vazio ignorados, erros propagam); escalares diretos coagidos.
  Object _collectNumbers(List<Expr> args) {
    final out = <double>[];
    for (final arg in args) {
      final v = eval(arg);
      if (v is FormulaError) return v;
      if (v is ArrayValue) {
        for (final row in v.rows) {
          for (final cell in row) {
            if (cell is FormulaError) return cell;
            if (cell is double) out.add(cell);
          }
        }
      } else if (arg is RefExpr) {
        // Referência direta segue regras de intervalo.
        if (v is double) out.add(v);
      } else {
        final n = _toNumber(v);
        if (n is! double) return n;
        out.add(n);
      }
    }
    return out;
  }

  Object? _fnSum(List<Expr> args) {
    final nums = _collectNumbers(args);
    if (nums is! List<double>) return nums;
    var sum = 0.0;
    for (final n in nums) {
      sum += n;
    }
    return sum;
  }

  Object? _fnAverage(List<Expr> args) {
    final nums = _collectNumbers(args);
    if (nums is! List<double>) return nums;
    if (nums.isEmpty) return _errDiv0;
    var sum = 0.0;
    for (final n in nums) {
      sum += n;
    }
    return sum / nums.length;
  }

  Object? _fnMinMax(List<Expr> args, bool isMin) {
    final nums = _collectNumbers(args);
    if (nums is! List<double>) return nums;
    if (nums.isEmpty) return 0.0;
    return isMin ? nums.reduce(math.min) : nums.reduce(math.max);
  }

  Object? _fnCount(List<Expr> args) {
    var n = 0;
    for (final arg in args) {
      final v = eval(arg);
      if (v is ArrayValue) {
        for (final row in v.rows) {
          for (final cell in row) {
            if (cell is double) n++;
          }
        }
      } else if (arg is RefExpr) {
        if (v is double) n++;
      } else {
        if (v is FormulaError) return v;
        if (_toNumber(v) is double) n++;
      }
    }
    return n.toDouble();
  }

  Object? _fnCountA(List<Expr> args) {
    var n = 0;
    for (final arg in args) {
      final v = eval(arg);
      if (v is ArrayValue) {
        for (final row in v.rows) {
          for (final cell in row) {
            if (cell != null) n++; // erros e textos contam
          }
        }
      } else if (v != null) {
        n++;
      }
    }
    return n.toDouble();
  }

  Object? _fnMedian(List<Expr> args) {
    final nums = _collectNumbers(args);
    if (nums is! List<double>) return nums;
    if (nums.isEmpty) return _errNum;
    nums.sort();
    final mid = nums.length ~/ 2;
    if (nums.length.isOdd) return nums[mid];
    return (nums[mid - 1] + nums[mid]) / 2;
  }

  Object? _fnRound(List<Expr> args) {
    if (args.length != 2) return _errValue;
    final x = _toNumber(_scalar(eval(args[0])));
    if (x is! double) return x;
    final n = _toNumber(_scalar(eval(args[1])));
    if (n is! double) return n;
    final digits = n.truncate();
    if (digits < -15 || digits > 15) return _errNum;
    final f = math.pow(10.0, digits).toDouble();
    // Arredondamento "half away from zero".
    final r = (x.abs() * f).roundToDouble() / f;
    return x.isNegative ? -r : r;
  }

  Object? _fnAbs(List<Expr> args) {
    if (args.length != 1) return _errValue;
    final x = _toNumber(_scalar(eval(args[0])));
    if (x is! double) return x;
    return x.abs();
  }

  // ------------------------------------------------- funções com critério

  Object? _fnCriteria(String name, List<Expr> args) {
    final maxArgs = name == 'COUNTIF' ? 2 : 3;
    if (args.length < 2 || args.length > maxArgs) return _errValue;
    final rv = eval(args[0]);
    if (rv is FormulaError) return rv;
    final critRange = rv is ArrayValue
        ? rv
        : ArrayValue([
            [rv]
          ]);
    final critV = _scalar(eval(args[1]));
    if (critV is FormulaError) return critV;
    final match = _buildCriteria(critV);
    var valRange = critRange;
    if (args.length == 3) {
      final vv = eval(args[2]);
      if (vv is FormulaError) return vv;
      valRange = vv is ArrayValue
          ? vv
          : ArrayValue([
              [vv]
            ]);
    }
    var matched = 0;
    var count = 0;
    var sum = 0.0;
    for (var r = 0; r < critRange.rowCount; r++) {
      for (var c = 0; c < critRange.colCount; c++) {
        final cell = critRange.at(r, c);
        if (cell is FormulaError) continue; // erro não casa com critério
        if (!match(cell)) continue;
        matched++;
        if (name == 'COUNTIF') continue;
        if (r >= valRange.rowCount || c >= valRange.colCount) continue;
        final v = valRange.at(r, c);
        if (v is FormulaError) return v;
        if (v is double) {
          sum += v;
          count++;
        }
      }
    }
    switch (name) {
      case 'COUNTIF':
        return matched.toDouble();
      case 'SUMIF':
        return sum;
      default: // AVERAGEIF
        return count == 0 ? _errDiv0 : sum / count;
    }
  }

  /// Constrói o predicado de critério (SUMIF/COUNTIF/AVERAGEIF):
  /// operadores ">", ">=", "<", "<=", "<>", "=" em texto; igualdade
  /// numérica/booleana; curingas `*`/`?`; critério vazio casa vazios.
  bool Function(Object?) _buildCriteria(Object? crit) {
    if (crit == null) return (v) => v == null || v == '';
    if (crit is bool) return (v) => v is bool && v == crit;
    if (crit is double) return (v) => v is double && v == crit;
    var s = crit as String;
    var op = '=';
    if (s.length >= 2 &&
        (s.startsWith('>=') || s.startsWith('<=') || s.startsWith('<>'))) {
      op = s.substring(0, 2);
      s = s.substring(2);
    } else if (s.isNotEmpty && (s[0] == '>' || s[0] == '<' || s[0] == '=')) {
      op = s[0];
      s = s.substring(1);
    }
    if (s.isEmpty) {
      // "" ou "=" casa vazios; "<>" casa não vazios.
      if (op == '<>') return (v) => v != null && v != '';
      return (v) => v == null || v == '';
    }
    final num = double.tryParse(s);
    if (num != null) {
      return (v) {
        if (v is double) {
          return switch (op) {
            '=' => v == num,
            '<>' => v != num,
            '<' => v < num,
            '<=' => v <= num,
            '>' => v > num,
            _ => v >= num,
          };
        }
        // Não-número nunca casa com critério numérico, exceto "<>".
        return op == '<>' && v != null;
      };
    }
    final upper = s.toUpperCase();
    if (upper == 'TRUE' || upper == 'FALSE') {
      final bval = upper == 'TRUE';
      if (op == '<>') return (v) => v is! bool || v != bval;
      return (v) => v is bool && v == bval;
    }
    if (op == '=' || op == '<>') {
      final matcher = _textMatcher(s);
      if (op == '=') return (v) => v is String && matcher(v);
      return (v) => !(v is String && matcher(v));
    }
    // Ordenação lexicográfica sem diferenciar maiúsculas.
    return (v) {
      if (v is! String) return false;
      final c = v.toUpperCase().compareTo(upper);
      return switch (op) {
        '<' => c < 0,
        '<=' => c <= 0,
        '>' => c > 0,
        _ => c >= 0,
      };
    };
  }

  /// Igualdade de texto sem diferenciar maiúsculas, com curingas
  /// `*` (qualquer sequência) e `?` (um caractere); `~` escapa.
  bool Function(String) _textMatcher(String pattern) {
    if (!pattern.contains('*') && !pattern.contains('?')) {
      final up = pattern.toUpperCase();
      return (v) => v.toUpperCase() == up;
    }
    final sb = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final ch = pattern[i];
      if (ch == '~' && i + 1 < pattern.length) {
        sb.write(RegExp.escape(pattern[i + 1]));
        i++;
      } else if (ch == '*') {
        sb.write('.*');
      } else if (ch == '?') {
        sb.write('.');
      } else {
        sb.write(RegExp.escape(ch));
      }
    }
    sb.write(r'$');
    final re = RegExp(sb.toString(), caseSensitive: false, unicode: true);
    return (v) => re.hasMatch(v);
  }
}
