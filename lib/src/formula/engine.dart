/// Motor de fórmulas: registro, dependências, recálculo topológico e
/// tradução de referências relativas (fórmulas compartilhadas).
library;

import 'package:xlsx_editor/src/util/cell_ref.dart';

import 'ast.dart';
import 'evaluator.dart';
import 'parser.dart';
import 'tokenizer.dart';

export 'evaluator.dart' show ArrayValue, FormulaError;

/// Acesso do avaliador ao workbook (implementado pelo integrador).
abstract class WorkbookAccess {
  int get sheetCount;

  /// Índice da planilha pelo nome; -1 se não existe.
  int sheetIndexByName(String name);

  /// Valor efetivo da célula: double | String | bool | FormulaError | null.
  Object? valueAt(int sheet, int row, int col);
}

/// Célula com fórmula registrada.
class _FormulaCell {
  final int sheet, row, col;
  String text;
  Expr ast;
  bool isArray;
  bool dirty = true;
  bool computed = false;
  Object? value;
  List<(int, CellRange)> deps;

  _FormulaCell(this.sheet, this.row, this.col, this.text, this.ast,
      this.isArray, this.deps);
}

/// Estado de uma passada de recálculo.
class _RecalcState {
  final inProgress = <(int, int, int)>{};
  final changed = <(int, int, int, Object?)>[];
}

/// Fonte de valores: usa valores recém-calculados das fórmulas
/// (calculando sob demanda durante o recálculo) e o modelo para o resto.
class _EngineLookup implements ValueLookup {
  final FormulaEngine _engine;
  final _RecalcState? _state;

  _EngineLookup(this._engine, this._state);

  @override
  int sheetIndexByName(String name) => _engine._access.sheetIndexByName(name);

  @override
  Object? cellValue(int sheet, int row, int col) {
    final f = _engine._formulas[(sheet, row, col)];
    if (f == null) return _engine._access.valueAt(sheet, row, col);
    final state = _state;
    if (state != null && f.dirty) return _engine._computeCell(f, state);
    if (f.computed) return f.value;
    return _engine._access.valueAt(sheet, row, col);
  }
}

/// Motor de fórmulas com recálculo incremental.
class FormulaEngine {
  final WorkbookAccess _access;
  final Map<(int, int, int), _FormulaCell> _formulas = {};

  FormulaEngine(WorkbookAccess access) : _access = access;

  /// Registra/substitui fórmula (texto canônico SEM '=').
  /// [isArray] para fórmulas de matriz (CSE).
  void setFormula(int sheet, int row, int col, String formula,
      {bool isArray = false}) {
    final ast = parseFormula(formula);
    final deps = <(int, CellRange)>[];
    _collectDeps(ast, sheet, deps);
    _formulas[(sheet, row, col)] =
        _FormulaCell(sheet, row, col, formula, ast, isArray, deps);
    invalidateCell(sheet, row, col);
  }

  void removeFormula(int sheet, int row, int col) {
    if (_formulas.remove((sheet, row, col)) != null) {
      invalidateCell(sheet, row, col);
    }
  }

  bool hasFormula(int sheet, int row, int col) =>
      _formulas.containsKey((sheet, row, col));

  String? formulaTextAt(int sheet, int row, int col) =>
      _formulas[(sheet, row, col)]?.text;

  /// Marca a célula como alterada e propaga dirty aos dependentes
  /// (diretos e transitivos).
  void invalidateCell(int sheet, int row, int col) {
    final seen = <(int, int, int)>{(sheet, row, col)};
    final queue = <(int, int, int)>[(sheet, row, col)];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      _formulas[cur]?.dirty = true;
      final (s, r, c) = cur;
      for (final entry in _formulas.entries) {
        if (seen.contains(entry.key)) continue;
        final ok =
            entry.value.deps.any((d) => d.$1 == s && d.$2.contains(r, c));
        if (ok) {
          seen.add(entry.key);
          queue.add(entry.key);
        }
      }
    }
  }

  /// Recalcula tudo que está dirty em ordem topológica.
  /// Retorna as células cujo valor calculado mudou.
  List<(int sheet, int row, int col, Object? value)> recalc() {
    final state = _RecalcState();
    final dirty = _formulas.values.where((f) => f.dirty).toList();
    for (final f in dirty) {
      if (f.dirty) _computeCell(f, state);
    }
    return state.changed;
  }

  /// Recalcula TODAS as fórmulas registradas (primeira carga).
  List<(int, int, int, Object?)> recalcAll() {
    for (final f in _formulas.values) {
      f.dirty = true;
    }
    return recalc();
  }

  /// Avalia expressão avulsa no contexto de uma célula
  /// (barra de status etc). Não altera o estado do motor.
  Object? evaluate(String formula, int sheet, int row, int col) {
    final ast = parseFormula(formula);
    final ev = Evaluator(_EngineLookup(this, null), sheet);
    return _finalize(ev.eval(ast), false);
  }

  /// Calcula a célula (DFS): dependências dirty são calculadas antes;
  /// reentrada em célula em progresso caracteriza ciclo -> #CYCLE!.
  Object? _computeCell(_FormulaCell f, _RecalcState state) {
    final key = (f.sheet, f.row, f.col);
    if (state.inProgress.contains(key)) {
      return const FormulaError('#CYCLE!');
    }
    state.inProgress.add(key);
    Object? v;
    try {
      final ev =
          Evaluator(_EngineLookup(this, state), f.sheet, arrayMode: f.isArray);
      v = _finalize(ev.eval(f.ast), f.isArray);
    } finally {
      state.inProgress.remove(key);
    }
    f.dirty = false;
    final changed = !f.computed || !_valueEquals(f.value, v);
    f.value = v;
    f.computed = true;
    if (changed) state.changed.add((f.sheet, f.row, f.col, v));
    return v;
  }

  /// Normaliza o resultado final de uma célula: array vira escalar
  /// ([0][0] em modo matricial, 1x1 colapsa, senão #VALUE!); vazio vira 0.
  Object? _finalize(Object? v, bool isArray) {
    if (v is ArrayValue) {
      if (isArray || (v.rowCount == 1 && v.colCount == 1)) {
        final first = v.rowCount > 0 && v.colCount > 0 ? v.at(0, 0) : null;
        return _finalize(first, false);
      }
      return const FormulaError('#VALUE!');
    }
    if (v == null) return 0.0;
    return v;
  }

  bool _valueEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    return a == b; // FormulaError implementa ==
  }

  /// Extrai as dependências (célula/intervalo) da AST.
  void _collectDeps(Expr e, int defaultSheet, List<(int, CellRange)> out) {
    switch (e) {
      case RefExpr():
        final s =
            e.sheet == null ? defaultSheet : _access.sheetIndexByName(e.sheet!);
        if (s >= 0) out.add((s, CellRange(e.row, e.col, e.row, e.col)));
      case RangeExpr():
        final s =
            e.sheet == null ? defaultSheet : _access.sheetIndexByName(e.sheet!);
        if (s >= 0) {
          out.add((s, CellRange.normalized(e.r1, e.c1, e.r2, e.c2)));
        }
      case UnaryExpr(:final operand):
        _collectDeps(operand, defaultSheet, out);
      case BinaryExpr(:final left, :final right):
        _collectDeps(left, defaultSheet, out);
        _collectDeps(right, defaultSheet, out);
      case FuncCall(:final args):
        for (final a in args) {
          _collectDeps(a, defaultSheet, out);
        }
      default:
        break; // literais não têm dependências
    }
  }
}

/// Traduz referências RELATIVAS por (dRow,dCol); âncoras `$` ficam fixas.
/// Referências que saem dos limites viram `#REF!`. Usado pelo leitor de
/// xlsx para expandir fórmulas compartilhadas (`<f t="shared">`).
String translateFormula(String formula, int dRow, int dCol) {
  List<Token> tokens;
  try {
    tokens = tokenize(formula);
  } on FormatException catch (e) {
    throw FormulaParseException(e.message, e.offset ?? 0);
  }
  final sb = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.kind == TokenKind.name) {
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      // Nome de função ou de planilha não é referência.
      final skip = next != null &&
          (next.kind == TokenKind.lparen || next.kind == TokenKind.bang);
      if (!skip) {
        final parts = tryParseA1(t.text);
        if (parts != null) {
          final r = parts.absRow ? parts.row : parts.row + dRow;
          final c = parts.absCol ? parts.col : parts.col + dCol;
          if (r < 0 || c < 0 || r > 1048575 || c > 16383) {
            sb.write('#REF!');
          } else {
            sb.write('${parts.absCol ? r'$' : ''}${colName(c)}'
                '${parts.absRow ? r'$' : ''}${r + 1}');
          }
          continue;
        }
      }
    }
    sb.write(t.text);
  }
  return sb.toString();
}
