/// Tokenizador de fórmulas Excel (forma canônica en-US ou localizada).
///
/// [tokenize] preserva o texto cru de cada token, permitindo reconstrução
/// fiel da fórmula (usado pela localização e pela tradução de referências).
library;

/// Tipo léxico do token.
enum TokenKind {
  /// Literal numérico (ex.: `1.5`, `.5`, `1E+10`).
  number,

  /// Literal de texto entre aspas duplas (texto cru inclui as aspas).
  string,

  /// Nome: função, referência de célula, planilha, TRUE/FALSE.
  name,

  /// Nome de planilha entre aspas simples (texto cru inclui as aspas).
  quotedSheet,

  /// Literal de erro (`#REF!`, `#VALUE!`, ...).
  error,

  /// Operador: + - * / ^ & % = <> < <= > >=
  op,

  /// `(`
  lparen,

  /// `)`
  rparen,

  /// Separador de argumentos (`,` canônico, `;` pt-BR).
  argSep,

  /// `:` (intervalo).
  colon,

  /// `!` (separador planilha!célula).
  bang,
}

/// Token com texto cru e posição original em code units.
class Token {
  final TokenKind kind;
  final String text;
  final int pos;

  const Token(this.kind, this.text, this.pos);

  @override
  String toString() => '$kind(`$text`)';
}

/// Literais de erro reconhecidos.
const List<String> errorLiterals = [
  '#CYCLE!',
  '#DIV/0!',
  '#VALUE!',
  '#NAME?',
  '#NULL!',
  '#REF!',
  '#NUM!',
  '#N/A',
];

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c >= 0x80;

bool _isNameStart(int c) => _isLetter(c) || c == 0x5F; // letra ou _

bool _isNamePart(int c) =>
    _isLetter(c) || _isDigit(c) || c == 0x5F || c == 0x2E || c == 0x24;

/// Converte [src] em tokens. [decimal] e [argSep] definem a localidade
/// (canônico: `.` e `,`; pt-BR: `,` e `;`).
///
/// Lança [FormatException] em erro léxico.
List<Token> tokenize(String src, {String decimal = '.', String argSep = ','}) {
  final decimalCode = decimal.codeUnitAt(0);
  final sepCode = argSep.codeUnitAt(0);
  final tokens = <Token>[];
  var i = 0;
  while (i < src.length) {
    final c = src.codeUnitAt(i);
    // Espaços em branco são ignorados.
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
      continue;
    }
    final start = i;
    // Literal de texto ("...", com "" como escape) ou planilha ('...').
    if (c == 0x22 || c == 0x27) {
      var j = i + 1;
      var closed = false;
      while (j < src.length) {
        if (src.codeUnitAt(j) == c) {
          if (j + 1 < src.length && src.codeUnitAt(j + 1) == c) {
            j += 2; // aspas duplicadas = escape
            continue;
          }
          closed = true;
          j++;
          break;
        }
        j++;
      }
      if (!closed) {
        throw FormatException('Literal não terminado', src, start);
      }
      tokens.add(Token(
        c == 0x22 ? TokenKind.string : TokenKind.quotedSheet,
        src.substring(start, j),
        start,
      ));
      i = j;
      continue;
    }
    // Literal de erro (#REF!, #VALUE!, ...).
    if (c == 0x23) {
      final rest = src.substring(i).toUpperCase();
      String? match;
      for (final lit in errorLiterals) {
        if (rest.startsWith(lit)) {
          match = lit;
          break;
        }
      }
      if (match == null) {
        throw FormatException('Literal de erro desconhecido', src, i);
      }
      tokens.add(Token(TokenKind.error, match, i));
      i += match.length;
      continue;
    }
    // Número (dígitos, decimal opcional, expoente opcional).
    if (_isDigit(c) ||
        (c == decimalCode &&
            i + 1 < src.length &&
            _isDigit(src.codeUnitAt(i + 1)))) {
      var j = i;
      while (j < src.length && _isDigit(src.codeUnitAt(j))) {
        j++;
      }
      if (j < src.length &&
          src.codeUnitAt(j) == decimalCode &&
          j + 1 < src.length &&
          _isDigit(src.codeUnitAt(j + 1))) {
        j += 2;
        while (j < src.length && _isDigit(src.codeUnitAt(j))) {
          j++;
        }
      }
      // Expoente (1E5, 1.5E+10).
      if (j < src.length &&
          (src.codeUnitAt(j) == 0x45 || src.codeUnitAt(j) == 0x65)) {
        var k = j + 1;
        if (k < src.length &&
            (src.codeUnitAt(k) == 0x2B || src.codeUnitAt(k) == 0x2D)) {
          k++;
        }
        if (k < src.length && _isDigit(src.codeUnitAt(k))) {
          while (k < src.length && _isDigit(src.codeUnitAt(k))) {
            k++;
          }
          j = k;
        }
      }
      tokens.add(Token(TokenKind.number, src.substring(i, j), i));
      i = j;
      continue;
    }
    // Nome (função, referência, planilha); `$` inicial só em referências.
    if (_isNameStart(c) ||
        (c == 0x24 && i + 1 < src.length && _isLetter(src.codeUnitAt(i + 1)))) {
      var j = i + 1;
      while (j < src.length && _isNamePart(src.codeUnitAt(j))) {
        j++;
      }
      tokens.add(Token(TokenKind.name, src.substring(i, j), i));
      i = j;
      continue;
    }
    // Separador de argumentos.
    if (c == sepCode) {
      tokens.add(Token(TokenKind.argSep, argSep, i));
      i++;
      continue;
    }
    // Pontuação e operadores.
    switch (c) {
      case 0x28:
        tokens.add(Token(TokenKind.lparen, '(', i));
        i++;
      case 0x29:
        tokens.add(Token(TokenKind.rparen, ')', i));
        i++;
      case 0x3A:
        tokens.add(Token(TokenKind.colon, ':', i));
        i++;
      case 0x21:
        tokens.add(Token(TokenKind.bang, '!', i));
        i++;
      case 0x2B || 0x2D || 0x2A || 0x2F || 0x5E || 0x26 || 0x25 || 0x3D:
        tokens.add(Token(TokenKind.op, src[i], i));
        i++;
      case 0x3C: // < <= <>
        if (i + 1 < src.length &&
            (src.codeUnitAt(i + 1) == 0x3D || src.codeUnitAt(i + 1) == 0x3E)) {
          tokens.add(Token(TokenKind.op, src.substring(i, i + 2), i));
          i += 2;
        } else {
          tokens.add(Token(TokenKind.op, '<', i));
          i++;
        }
      case 0x3E: // > >=
        if (i + 1 < src.length && src.codeUnitAt(i + 1) == 0x3D) {
          tokens.add(Token(TokenKind.op, '>=', i));
          i += 2;
        } else {
          tokens.add(Token(TokenKind.op, '>', i));
          i++;
        }
      default:
        throw FormatException('Caractere inesperado', src, i);
    }
  }
  return tokens;
}
