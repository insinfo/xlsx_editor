import 'package:test/test.dart';
import 'package:xlsx_editor/src/formula/ast.dart';
import 'package:xlsx_editor/src/formula/engine.dart';
import 'package:xlsx_editor/src/formula/localization.dart';
import 'package:xlsx_editor/src/formula/parser.dart';
import 'package:xlsx_editor/src/util/cell_ref.dart';

/// Workbook falso sobre um Map (integração de teste).
class FakeWorkbook implements WorkbookAccess {
  final List<String> sheets;
  final Map<(int, int, int), Object?> cells = {};

  FakeWorkbook(this.sheets);

  @override
  int get sheetCount => sheets.length;

  @override
  int sheetIndexByName(String name) => sheets.indexOf(name);

  @override
  Object? valueAt(int sheet, int row, int col) => cells[(sheet, row, col)];

  void set(String a1, Object? v, {int sheet = 0}) {
    final ref = CellRef.tryParse(a1)!;
    cells[(sheet, ref.row, ref.col)] = v;
  }

  /// Grava de volta os valores calculados (papel do integrador).
  void apply(List<(int, int, int, Object?)> changes) {
    for (final (s, r, c, v) in changes) {
      cells[(s, r, c)] = v;
    }
  }
}

void main() {
  Object? evalOn(FakeWorkbook wb, String formula, {int sheet = 0}) =>
      FormulaEngine(wb).evaluate(formula, sheet, 0, 0);

  Object? eval(String formula) => evalOn(FakeWorkbook(['Plan1']), formula);

  group('1. aritmética e precedência', () {
    test('2+3*4^2 = 50', () => expect(eval('2+3*4^2'), 50.0));
    test('(2+3)*4 = 20', () => expect(eval('(2+3)*4'), 20.0));
    test('-3^2 = 9 (unário liga mais forte que ^)',
        () => expect(eval('-3^2'), 9.0));
    test('50% = 0.5', () => expect(eval('50%'), 0.5));
    test('"a"&"b" = ab', () => expect(eval('"a"&"b"'), 'ab'));
    test('11499000/5', () => expect(eval('11499000/5'), 2299800.0));
    test('divisão por zero',
        () => expect(eval('1/0'), const FormulaError('#DIV/0!')));
    test('concatenação formata números', () {
      expect(eval('"n="&5'), 'n=5');
      expect(eval('"v="&2.5'), 'v=2.5');
    });
    test('coerção aritmética', () {
      expect(eval('"5"+1'), 6.0);
      expect(eval('TRUE+1'), 2.0);
      expect(eval('"x"+1'), const FormulaError('#VALUE!'));
    });
  });

  group('2. fórmulas reais', () {
    late FakeWorkbook wb;

    setUp(() {
      wb = FakeWorkbook(['Plan1']);
    });

    test('IF(G7=...,"-",D7)', () {
      wb.set('G7', 'EXCESSIVAMENTE ELEVADO');
      wb.set('D7', 123.0);
      expect(evalOn(wb, 'IF(G7="EXCESSIVAMENTE ELEVADO","-",D7)'), '-');
      wb.set('G7', 'VÁLIDO');
      expect(evalOn(wb, 'IF(G7="EXCESSIVAMENTE ELEVADO","-",D7)'), 123.0);
    });

    test('IF aninhado com comparação', () {
      const f = 'IF(F8="-","-",IF(D8>F8,"EXCESSIVAMENTE ELEVADO","VÁLIDO"))';
      wb.set('F8', 100.0);
      wb.set('D8', 150.0);
      expect(evalOn(wb, f), 'EXCESSIVAMENTE ELEVADO');
      wb.set('D8', 50.0);
      expect(evalOn(wb, f), 'VÁLIDO');
      wb.set('F8', '-');
      expect(evalOn(wb, f), '-');
    });

    test('AVERAGEIF ignora não correspondentes', () {
      // K7:K20 com 3 válidos (linhas 7, 10, 13); demais não contam.
      final status = <String>[
        'VÁLIDO', 'EXCESSIVAMENTE ELEVADO', '-', //
        'VÁLIDO', 'INEXEQUÍVEL', '-', //
        'VÁLIDO', 'INEXEQUÍVEL', '-', '-', '-', '-', '-', '-',
      ];
      for (var i = 0; i < 14; i++) {
        wb.set('K${7 + i}', status[i]);
        wb.set('H${7 + i}', 1000.0);
      }
      wb.set('H7', 10.0);
      wb.set('H10', 20.0);
      wb.set('H13', 60.0);
      expect(evalOn(wb, 'AVERAGEIF(K7:K20,"VÁLIDO",H7:H20)'), 30.0);
      // Critério sem correspondência -> #DIV/0!.
      expect(evalOn(wb, 'AVERAGEIF(K7:K20,"NADA",H7:H20)'),
          const FormulaError('#DIV/0!'));
      // Sem diferenciar maiúsculas.
      expect(evalOn(wb, 'AVERAGEIF(K7:K20,"válido",H7:H20)'), 30.0);
    });

    test('IF com AVERAGE de dois intervalos ancorados', () {
      const f = r'IF(D100="-","-",AVERAGE(D$92:D99,D101:D$105))';
      for (var i = 0; i < 8; i++) {
        wb.set('D${92 + i}', (i + 1).toDouble()); // D92..D99 = 1..8
      }
      for (var i = 0; i < 5; i++) {
        wb.set('D${101 + i}', (i + 9).toDouble()); // D101..D105 = 9..13
      }
      wb.set('D100', 999.0);
      expect(evalOn(wb, f), 7.0); // média de 1..13
      wb.set('D100', '-');
      expect(evalOn(wb, f), '-');
    });

    test('MEDIAN(IF(...)) como fórmula de matriz', () {
      // 14 células misturando VÁLIDO/INEXEQUÍVEL; mediana só dos válidos.
      final valid = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0];
      var vi = 0;
      for (var i = 0; i < 14; i++) {
        final isValid = i.isEven;
        wb.set('K${115 + i}', isValid ? 'VÁLIDO' : 'INEXEQUÍVEL');
        wb.set('H${115 + i}', isValid ? valid[vi++] : 999.0);
      }
      final engine = FormulaEngine(wb);
      engine.setFormula(0, 129, 12, 'MEDIAN(IF(K115:K128="VÁLIDO",H115:H128))',
          isArray: true);
      final changes = engine.recalcAll();
      expect(changes, contains((0, 129, 12, 40.0)));
    });

    test('SUM(E262:E265)', () {
      wb.set('E262', 5.0);
      wb.set('E263', 10.0);
      wb.set('E264', 15.0);
      wb.set('E265', 20.0);
      expect(evalOn(wb, 'SUM(E262:E265)'), 50.0);
      // Texto e vazio no intervalo são ignorados.
      wb.set('E263', 'x');
      wb.set('E264', null);
      expect(evalOn(wb, 'SUM(E262:E265)'), 25.0);
    });

    test('B5*O7 e (P140+P161+P182)', () {
      wb.set('B5', 3.0);
      wb.set('O7', 4.0);
      expect(evalOn(wb, 'B5*O7'), 12.0);
      wb.set('P140', 1.5);
      wb.set('P161', 2.5);
      wb.set('P182', 3.0);
      expect(evalOn(wb, '(P140+P161+P182)'), 7.0);
    });

    test('IF(I8="-","-",I8*75%)', () {
      wb.set('I8', 200.0);
      expect(evalOn(wb, 'IF(I8="-","-",I8*75%)'), 150.0);
      wb.set('I8', '-');
      expect(evalOn(wb, 'IF(I8="-","-",I8*75%)'), '-');
    });

    test('refs qualificadas por planilha parseiam', () {
      final a = parseFormula("'MÉDIA'!P7") as RefExpr;
      expect(a.sheet, 'MÉDIA');
      expect(a.row, 6);
      expect(a.col, 15);
      final b = parseFormula('Composições!D25') as RefExpr;
      expect(b.sheet, 'Composições');
      expect(b.row, 24);
      expect(b.col, 3);
    });

    test('IF é preguiçoso (ramo não tomado não gera erro)', () {
      expect(evalOn(wb, 'IF(1>0,"ok",1/0)'), 'ok');
      expect(evalOn(wb, 'IF(1<0,1/0,"ok")'), 'ok');
      // Erros propagam por argumentos não preguiçosos.
      expect(evalOn(wb, 'SUM(1,1/0)'), const FormulaError('#DIV/0!'));
    });

    test('comparações', () {
      expect(evalOn(wb, '"VÁLIDO"="válido"'), true); // sem maiúsculas
      expect(evalOn(wb, '2<"a"'), true); // número < texto
      expect(evalOn(wb, 'TRUE>100'), true); // bool > tudo
      expect(evalOn(wb, 'Z99=0'), true); // vazio = 0
      expect(evalOn(wb, 'Z99=""'), true); // vazio = ""
      expect(evalOn(wb, '1<>2'), true);
    });

    test('demais funções', () {
      wb.set('A1', 1.0);
      wb.set('A2', 2.0);
      wb.set('A3', 3.0);
      wb.set('A4', 'x');
      wb.set('A5', 4.0);
      expect(evalOn(wb, 'MIN(A1:A5)'), 1.0);
      expect(evalOn(wb, 'MAX(A1:A5)'), 4.0);
      expect(evalOn(wb, 'COUNT(A1:A5)'), 4.0);
      expect(evalOn(wb, 'COUNTA(A1:A5)'), 5.0);
      expect(evalOn(wb, 'MEDIAN(A1:A5)'), 2.5);
      expect(evalOn(wb, 'COUNTIF(A1:A5,">2")'), 2.0);
      expect(evalOn(wb, 'SUMIF(A1:A5,">=2")'), 9.0);
      expect(evalOn(wb, 'ROUND(2.5,0)'), 3.0);
      expect(evalOn(wb, 'ROUND(-2.5,0)'), -3.0);
      expect(evalOn(wb, 'ROUND(1.234,2)'), 1.23);
      expect(evalOn(wb, 'ABS(-2)'), 2.0);
      expect(evalOn(wb, 'AND(TRUE,1)'), true);
      expect(evalOn(wb, 'OR(FALSE,0)'), false);
      expect(evalOn(wb, 'NOT(FALSE)'), true);
      expect(evalOn(wb, 'IFERROR(1/0,"x")'), 'x');
      expect(evalOn(wb, 'IFERROR(5,"x")'), 5.0);
      expect(evalOn(wb, 'FOO(1)'), const FormulaError('#NAME?'));
    });

    test('curingas em critérios', () {
      wb.set('B1', 'VÁLIDO');
      wb.set('B2', 'INVALIDO');
      wb.set('B3', 'VÁLVULA');
      expect(evalOn(wb, 'COUNTIF(B1:B3,"VÁL*")'), 2.0);
      expect(evalOn(wb, 'COUNTIF(B1:B3,"?NVALIDO")'), 1.0);
    });
  });

  group('3. recálculo por dependências', () {
    test('propagação em ordem topológica', () {
      final wb = FakeWorkbook(['Plan1']);
      wb.set('A1', 5.0);
      final engine = FormulaEngine(wb);
      engine.setFormula(0, 0, 1, 'A1*2'); // B1
      engine.setFormula(0, 0, 2, 'B1+A1'); // C1
      var res = engine.recalcAll();
      wb.apply(res);
      expect(res, equals([(0, 0, 1, 10.0), (0, 0, 2, 15.0)]));

      wb.set('A1', 7.0);
      engine.invalidateCell(0, 0, 0);
      res = engine.recalc();
      wb.apply(res);
      // B1 antes de C1 (ordem topológica), ambos com valores novos.
      expect(res, equals([(0, 0, 1, 14.0), (0, 0, 2, 21.0)]));

      // Sem alterações -> recalc vazio.
      expect(engine.recalc(), isEmpty);
    });

    test('valores recém-calculados são usados na mesma passada', () {
      final wb = FakeWorkbook(['Plan1']);
      wb.set('A1', 1.0);
      final engine = FormulaEngine(wb);
      // C1 registrado antes de B1: força ordenação topológica interna.
      engine.setFormula(0, 0, 2, 'B1*10'); // C1
      engine.setFormula(0, 0, 1, 'A1+1'); // B1
      final res = engine.recalcAll();
      final byCell = {for (final (s, r, c, v) in res) (s, r, c): v};
      expect(byCell[(0, 0, 1)], 2.0);
      expect(byCell[(0, 0, 2)], 20.0); // usa B1 fresco, não o modelo (vazio)
    });

    test('ciclo A1<->B1 termina com #CYCLE!', () {
      final wb = FakeWorkbook(['Plan1']);
      final engine = FormulaEngine(wb);
      engine.setFormula(0, 0, 0, 'B1'); // A1
      engine.setFormula(0, 0, 1, 'A1'); // B1
      final res = engine.recalcAll();
      final byCell = {for (final (s, r, c, v) in res) (s, r, c): v};
      expect(byCell[(0, 0, 0)], const FormulaError('#CYCLE!'));
      expect(byCell[(0, 0, 1)], const FormulaError('#CYCLE!'));
    });

    test('remoção de fórmula invalida dependentes', () {
      final wb = FakeWorkbook(['Plan1']);
      wb.set('A1', 5.0);
      final engine = FormulaEngine(wb);
      engine.setFormula(0, 0, 1, 'A1*2'); // B1
      engine.setFormula(0, 0, 2, 'B1+1'); // C1
      wb.apply(engine.recalcAll());
      expect(engine.hasFormula(0, 0, 1), isTrue);
      expect(engine.formulaTextAt(0, 0, 1), 'A1*2');
      engine.removeFormula(0, 0, 1);
      wb.set('B1', 100.0); // valor manual no lugar da fórmula
      expect(engine.hasFormula(0, 0, 1), isFalse);
      final res = engine.recalc();
      expect(res, equals([(0, 0, 2, 101.0)]));
    });
  });

  group('4. translateFormula (fórmulas compartilhadas)', () {
    test('desloca refs relativas', () {
      expect(translateFormula('IF(D8="-","-",(E8*25%)+E8)', 2, 0),
          'IF(D10="-","-",(E10*25%)+E10)');
    });
    test('âncoras \$ ficam fixas', () {
      expect(
          translateFormula(r'AVERAGE(D$92:D99)', 3, 1), r'AVERAGE(E$92:E102)');
      expect(translateFormula(r'$A$1+A1', 5, 5), r'$A$1+F6');
    });
    test('nomes de função e planilha não são deslocados', () {
      expect(
          translateFormula('SUM(A1:A2)+Plan2!B1', 1, 0), 'SUM(A2:A3)+Plan2!B2');
      expect(translateFormula('"A1"&A1', 1, 1), '"A1"&B2');
    });
    test('fora dos limites vira #REF!', () {
      expect(translateFormula('A1+B2', -1, 0), '#REF!+B1');
    });
  });

  group('5. localização pt-BR', () {
    test('ida e volta com AVERAGEIF', () {
      const en = 'AVERAGEIF(K7:K20,"VÁLIDO",H7:H20)';
      const pt = 'MÉDIASE(K7:K20;"VÁLIDO";H7:H20)';
      expect(formulaToPtBr(en), pt);
      expect(formulaFromPtBr(pt), en);
    });
    test('decimais e ; em literais preservados', () {
      const en = 'IF(A1>1.5,"x;y",2.5)';
      const pt = 'SE(A1>1,5;"x;y";2,5)';
      expect(formulaToPtBr(en), pt);
      expect(formulaFromPtBr(pt), en);
    });
    test('nomes com ponto e acentos', () {
      expect(formulaToPtBr('COUNTIF(A1:A9,">1")'), 'CONT.SE(A1:A9;">1")');
      expect(formulaFromPtBr('CONT.SE(A1:A9;">1")'), 'COUNTIF(A1:A9,">1")');
      expect(formulaToPtBr('COUNT(A1:A2)'), 'CONT.NÚM(A1:A2)');
      expect(formulaFromPtBr('CONT.NÚM(A1:A2)'), 'COUNT(A1:A2)');
      expect(formulaToPtBr('NOT(TRUE)'), 'NÃO(VERDADEIRO)');
      expect(formulaFromPtBr('NÃO(VERDADEIRO)'), 'NOT(TRUE)');
    });
    test('planilha MÉDIA não é confundida com função', () {
      expect(formulaToPtBr("'MÉDIA'!P7+AVERAGE(A1:A2)"),
          "'MÉDIA'!P7+MÉDIA(A1:A2)");
      expect(formulaFromPtBr("'MÉDIA'!P7+MÉDIA(A1:A2)"),
          "'MÉDIA'!P7+AVERAGE(A1:A2)");
    });
  });

  group('6. referências entre planilhas', () {
    test("'MÉDIA'!A1 + Composições!B2", () {
      final wb = FakeWorkbook(['MÉDIA', 'Composições']);
      wb.set('A1', 10.0, sheet: 0);
      wb.set('B2', 32.0, sheet: 1);
      final engine = FormulaEngine(wb);
      expect(engine.evaluate("'MÉDIA'!A1 + Composições!B2", 0, 0, 0), 42.0);
      // Planilha inexistente -> #REF!.
      expect(engine.evaluate('Nada!A1', 0, 0, 0), const FormulaError('#REF!'));
    });

    test('dependência entre planilhas propaga', () {
      final wb = FakeWorkbook(['MÉDIA', 'Composições']);
      wb.set('A1', 10.0, sheet: 1);
      final engine = FormulaEngine(wb);
      engine.setFormula(0, 0, 0, 'Composições!A1*2'); // MÉDIA!A1
      wb.apply(engine.recalcAll());
      expect(wb.valueAt(0, 0, 0), 20.0);
      wb.set('A1', 15.0, sheet: 1);
      engine.invalidateCell(1, 0, 0);
      final res = engine.recalc();
      expect(res, equals([(0, 0, 0, 30.0)]));
    });
  });

  group('AST e exprToFormula', () {
    test('texto canônico preservado', () {
      const samples = [
        'IF(G7="EXCESSIVAMENTE ELEVADO","-",D7)',
        r'AVERAGE(D$92:D99,D101:D$105)',
        'MEDIAN(IF(K115:K128="VÁLIDO",H115:H128))',
        '(2+3)*4',
        '-3^2',
        'B5*O7',
        'IF(I8="-","-",I8*75%)',
        "'Minha Plan'!A1",
      ];
      for (final s in samples) {
        expect(exprToFormula(parseFormula(s)), s);
      }
    });

    test('erro de sintaxe lança FormulaParseException', () {
      expect(() => parseFormula('1+'), throwsA(isA<FormulaParseException>()));
      expect(
          () => parseFormula('IF(1,2'), throwsA(isA<FormulaParseException>()));
      expect(
          () => parseFormula('"aberto'), throwsA(isA<FormulaParseException>()));
    });
  });
}
