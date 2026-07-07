/// Localização de fórmulas em nível de token:
/// canônico en-US (`,` separador, `.` decimal) <-> UI pt-BR
/// (`;` separador, `,` decimal, nomes de função traduzidos).
///
/// Literais de texto nunca são alterados.
library;

import 'tokenizer.dart';

/// Nomes de função en-US -> pt-BR.
const Map<String, String> functionNamesEnToPt = {
  'SUM': 'SOMA',
  'AVERAGE': 'MÉDIA',
  'MEDIAN': 'MED',
  'IF': 'SE',
  'AVERAGEIF': 'MÉDIASE',
  'SUMIF': 'SOMASE',
  'COUNTIF': 'CONT.SE',
  'MIN': 'MÍNIMO',
  'MAX': 'MÁXIMO',
  'COUNT': 'CONT.NÚM',
  'COUNTA': 'CONT.VALORES',
  'ROUND': 'ARRED',
  'ABS': 'ABS',
  'AND': 'E',
  'OR': 'OU',
  'NOT': 'NÃO',
  'IFERROR': 'SEERRO',
};

/// Nomes de função pt-BR -> en-US.
final Map<String, String> functionNamesPtToEn = {
  for (final e in functionNamesEnToPt.entries) e.value: e.key,
};

const Map<String, String> _boolEnToPt = {
  'TRUE': 'VERDADEIRO',
  'FALSE': 'FALSO',
};

const Map<String, String> _boolPtToEn = {
  'VERDADEIRO': 'TRUE',
  'FALSO': 'FALSE',
};

/// en-US canônico -> UI pt-BR (nomes traduzidos, `;` separador,
/// `,` decimal em literais numéricos).
String formulaToPtBr(String canonical) =>
    _convert(canonical, '.', ',', ',', ';', functionNamesEnToPt, _boolEnToPt);

/// UI pt-BR -> canônico en-US.
String formulaFromPtBr(String ptBr) =>
    _convert(ptBr, ',', ';', '.', ',', functionNamesPtToEn, _boolPtToEn);

String _convert(
  String src,
  String decFrom,
  String sepFrom,
  String decTo,
  String sepTo,
  Map<String, String> funcMap,
  Map<String, String> boolMap,
) {
  final tokens = tokenize(src, decimal: decFrom, argSep: sepFrom);
  final sb = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    switch (t.kind) {
      case TokenKind.number:
        sb.write(t.text.replaceAll(decFrom, decTo));
      case TokenKind.argSep:
        sb.write(sepTo);
      case TokenKind.name:
        final next = i + 1 < tokens.length ? tokens[i + 1] : null;
        final upper = t.text.toUpperCase();
        if (next != null && next.kind == TokenKind.lparen) {
          // Nome de função (seguido de parêntese).
          sb.write(funcMap[upper] ?? t.text);
        } else if (next == null || next.kind != TokenKind.bang) {
          // Literal booleano; nomes de planilha (antes de `!`) ficam.
          sb.write(boolMap[upper] ?? t.text);
        } else {
          sb.write(t.text);
        }
      default:
        sb.write(t.text);
    }
  }
  return sb.toString();
}
