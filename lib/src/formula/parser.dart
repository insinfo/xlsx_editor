/// Parser descendente recursivo de fórmulas (forma canônica en-US:
/// `,` separa argumentos, `.` é o ponto decimal).
///
/// Precedência (Excel): comparações < `&` < `+ -` < `* /` < `^` <
/// unário `- +` < `%` pós-fixo. Nota: `-3^2` é `(-3)^2` = 9.
library;

import 'package:xlsx_editor/src/util/cell_ref.dart';

import 'ast.dart';
import 'tokenizer.dart';

/// Erro de sintaxe em fórmula.
class FormulaParseException implements Exception {
  final String message;
  final int position;
  const FormulaParseException(this.message, this.position);

  @override
  String toString() => 'FormulaParseException($position): $message';
}

/// Partes de uma referência A1 com âncoras.
typedef RefParts = ({int row, int col, bool absRow, bool absCol});

/// Interpreta um token de referência A1 ("D8", "D$92", "$A$1").
/// Retorna null se o texto não for uma referência válida.
RefParts? tryParseA1(String text) {
  var i = 0;
  var absCol = false;
  var absRow = false;
  if (i < text.length && text.codeUnitAt(i) == 0x24) {
    absCol = true;
    i++;
  }
  final colStart = i;
  while (i < text.length && _isAsciiLetter(text.codeUnitAt(i))) {
    i++;
  }
  final letters = i - colStart;
  if (letters < 1 || letters > 3) return null;
  final col = colIndex(text.substring(colStart, i).toUpperCase());
  if (i < text.length && text.codeUnitAt(i) == 0x24) {
    absRow = true;
    i++;
  }
  final rowStart = i;
  while (i < text.length && _isAsciiDigit(text.codeUnitAt(i))) {
    i++;
  }
  if (i == rowStart || i != text.length) return null;
  final rowNum = int.tryParse(text.substring(rowStart));
  if (rowNum == null || rowNum < 1 || rowNum > 1048576) return null;
  if (col < 0 || col > 16383) return null;
  return (row: rowNum - 1, col: col, absRow: absRow, absCol: absCol);
}

bool _isAsciiLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
bool _isAsciiDigit(int c) => c >= 0x30 && c <= 0x39;

/// Interpreta [src] (fórmula SEM o `=` inicial) e devolve a AST.
/// Lança [FormulaParseException] em erro de sintaxe.
Expr parseFormula(String src) {
  List<Token> tokens;
  try {
    tokens = tokenize(src);
  } on FormatException catch (e) {
    throw FormulaParseException(e.message, e.offset ?? 0);
  }
  final parser = _Parser(src, tokens);
  final expr = parser.parseExpr();
  parser.expectEnd();
  return expr;
}

class _Parser {
  final String src;
  final List<Token> tokens;
  int _i = 0;

  _Parser(this.src, this.tokens);

  Token? get _peek => _i < tokens.length ? tokens[_i] : null;
  Token? get _peekNext => _i + 1 < tokens.length ? tokens[_i + 1] : null;
  Token _next() => tokens[_i++];

  Never _fail(String message, [int? pos]) =>
      throw FormulaParseException(message, pos ?? _peek?.pos ?? src.length);

  bool _isOp(Token? t, List<String> ops) =>
      t != null && t.kind == TokenKind.op && ops.contains(t.text);

  void expectEnd() {
    if (_i != tokens.length) _fail('Token inesperado `${_peek!.text}`');
  }

  Expr parseExpr() => _parseComparison();

  Expr _parseComparison() {
    var left = _parseConcat();
    while (_isOp(_peek, const ['=', '<>', '<', '<=', '>', '>='])) {
      final op = _next().text;
      left = BinaryExpr(op, left, _parseConcat());
    }
    return left;
  }

  Expr _parseConcat() {
    var left = _parseAdditive();
    while (_isOp(_peek, const ['&'])) {
      _next();
      left = BinaryExpr('&', left, _parseAdditive());
    }
    return left;
  }

  Expr _parseAdditive() {
    var left = _parseMultiplicative();
    while (_isOp(_peek, const ['+', '-'])) {
      final op = _next().text;
      left = BinaryExpr(op, left, _parseMultiplicative());
    }
    return left;
  }

  Expr _parseMultiplicative() {
    var left = _parsePower();
    while (_isOp(_peek, const ['*', '/'])) {
      final op = _next().text;
      left = BinaryExpr(op, left, _parsePower());
    }
    return left;
  }

  Expr _parsePower() {
    var left = _parseUnary();
    // `^` é associativo à esquerda no Excel (2^3^2 = 64).
    while (_isOp(_peek, const ['^'])) {
      _next();
      left = BinaryExpr('^', left, _parseUnary());
    }
    return left;
  }

  Expr _parseUnary() {
    if (_isOp(_peek, const ['-', '+'])) {
      final op = _next().text;
      return UnaryExpr(op, _parseUnary());
    }
    return _parsePostfix();
  }

  Expr _parsePostfix() {
    var e = _parsePrimary();
    while (_isOp(_peek, const ['%'])) {
      _next();
      e = UnaryExpr('%', e);
    }
    return e;
  }

  Expr _parsePrimary() {
    final t = _peek;
    if (t == null) _fail('Fim inesperado da fórmula');
    switch (t.kind) {
      case TokenKind.number:
        _next();
        final v = double.tryParse(t.text);
        if (v == null) _fail('Número inválido `${t.text}`', t.pos);
        return NumberLit(v);
      case TokenKind.string:
        _next();
        final inner = t.text.substring(1, t.text.length - 1);
        return StringLit(inner.replaceAll('""', '"'));
      case TokenKind.error:
        _next();
        return ErrorLit(t.text);
      case TokenKind.lparen:
        _next();
        final e = parseExpr();
        if (_peek == null || _peek!.kind != TokenKind.rparen) {
          _fail('Esperado `)`');
        }
        _next();
        return e;
      case TokenKind.quotedSheet:
        _next();
        final inner = t.text.substring(1, t.text.length - 1);
        final sheet = inner.replaceAll("''", "'");
        return _parseSheetRef(sheet, t.pos);
      case TokenKind.name:
        // Planilha não citada: nome seguido de `!`.
        if (_peekNext?.kind == TokenKind.bang) {
          final sheetTok = _next();
          return _parseSheetRef(sheetTok.text, sheetTok.pos);
        }
        // Chamada de função: nome seguido de `(`.
        if (_peekNext?.kind == TokenKind.lparen) {
          return _parseFuncCall();
        }
        _next();
        final upper = t.text.toUpperCase();
        if (upper == 'TRUE') return const BoolLit(true);
        if (upper == 'FALSE') return const BoolLit(false);
        final ref = tryParseA1(t.text);
        if (ref == null) {
          // Nome definido não suportado: vira #NAME? na avaliação.
          return const ErrorLit('#NAME?');
        }
        return _maybeRange(null, ref);
      default:
        _fail('Token inesperado `${t.text}`', t.pos);
    }
  }

  /// Após consumir o nome da planilha: `!` e referência/intervalo.
  Expr _parseSheetRef(String sheet, int pos) {
    if (_peek?.kind != TokenKind.bang) _fail('Esperado `!`', pos);
    _next();
    final t = _peek;
    if (t == null || t.kind != TokenKind.name) {
      _fail('Esperada referência após `!`');
    }
    final ref = tryParseA1(t.text);
    if (ref == null) _fail('Referência inválida `${t.text}`', t.pos);
    _next();
    return _maybeRange(sheet, ref);
  }

  /// Se o próximo token for `:`, completa o intervalo.
  Expr _maybeRange(String? sheet, RefParts a) {
    if (_peek?.kind == TokenKind.colon) {
      _next();
      final t = _peek;
      final b =
          t != null && t.kind == TokenKind.name ? tryParseA1(t.text) : null;
      if (b == null) _fail('Referência inválida após `:`');
      _next();
      return RangeExpr(sheet, a.row, a.col, b.row, b.col, a.absRow, a.absCol,
          b.absRow, b.absCol);
    }
    return RefExpr(sheet, a.row, a.col, a.absRow, a.absCol);
  }

  Expr _parseFuncCall() {
    final nameTok = _next();
    _next(); // `(`
    final name = nameTok.text.toUpperCase();
    final args = <Expr>[];
    if (_peek?.kind == TokenKind.rparen) {
      _next();
      return FuncCall(name, args);
    }
    while (true) {
      // Argumento omitido (ex.: IF(A1,,0)) equivale a 0.
      if (_peek?.kind == TokenKind.argSep || _peek?.kind == TokenKind.rparen) {
        args.add(const NumberLit(0));
      } else {
        args.add(parseExpr());
      }
      final t = _peek;
      if (t == null) _fail('Esperado `)` em $name(...)');
      if (t.kind == TokenKind.argSep) {
        _next();
        continue;
      }
      if (t.kind == TokenKind.rparen) {
        _next();
        return FuncCall(name, args);
      }
      _fail('Token inesperado `${t.text}` em $name(...)', t.pos);
    }
  }
}
