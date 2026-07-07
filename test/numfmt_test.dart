// Testes do motor de formatação ECMA-376 (renderização pt-BR).
import 'package:test/test.dart';
import 'package:xlsx_editor/src/numfmt/number_format.dart';

String fmt(String code, Object? value) =>
    NumberFormat.compile(code).format(value).text;

void main() {
  group('General', () {
    test('número com decimais', () {
      expect(fmt('General', 303096.17), '303096,17');
    });
    test('inteiro sem decimais e sem agrupamento', () {
      expect(fmt('General', 12), '12');
      expect(fmt('General', 252000), '252000');
    });
    test('double inteiro sem casas', () {
      expect(fmt('General', 12.0), '12');
    });
    test('negativo com -', () {
      expect(fmt('General', -5.5), '-5,5');
    });
    test('ruído binário limitado a ~11 dígitos significativos', () {
      expect(fmt('General', 0.1 + 0.2), '0,3');
    });
    test('string passa direto', () {
      expect(fmt('General', 'abc'), 'abc');
    });
    test('booleanos', () {
      expect(fmt('General', true), 'VERDADEIRO');
      expect(fmt('General', false), 'FALSO');
    });
    test('null -> vazio', () {
      expect(fmt('General', null), '');
    });
  });

  group('moeda R\$ (código real do arquivo alvo)', () {
    const code = r'"R$"\ #,##0.00;[Red]\-"R$"\ #,##0.00';
    test('positivo', () {
      final r = NumberFormat.compile(code).format(1800);
      expect(r.text, r'R$ 1.800,00');
      expect(r.colorArgbHex, isNull);
    });
    test('negativo: sinal do formato + cor [Red]', () {
      final r = NumberFormat.compile(code).format(-1800);
      expect(r.text, r'-R$ 1.800,00');
      expect(r.colorArgbHex, 'FF0000');
    });
    test('decimais', () {
      expect(fmt(code, 1720.19), r'R$ 1.720,19');
    });
  });

  group('contábil (builtin 43)', () {
    const code = r'_-* #,##0.00_-;\-* #,##0.00_-;_-* "-"??_-;_-@_-';
    test('positivo com espaços de _-', () {
      expect(fmt(code, 1234.5), ' 1.234,50 ');
    });
    test('zero contém o traço', () {
      expect(fmt(code, 0), contains('-'));
    });
    test('negativo com sinal do formato', () {
      final t = fmt(code, -10);
      expect(t, contains('-'));
      expect(t, contains('10,00'));
    });
    test('texto usa a 4a seção', () {
      expect(fmt(code, 'oi'), ' oi ');
    });
  });

  group('tag de moeda/locale [\$R\$-416]', () {
    const code = r'[$R$-416]\ #,##0.00;[Red]\-[$R$-416]\ #,##0.00';
    test('emite o literal R\$', () {
      expect(fmt(code, 46918.5), r'R$ 46.918,50');
    });
    test('negativo com cor', () {
      final r = NumberFormat.compile(code).format(-1.5);
      expect(r.text, r'-R$ 1,50');
      expect(r.colorArgbHex, 'FF0000');
    });
  });

  group('moeda simples', () {
    test('R\$ com milhar', () {
      expect(fmt(r'"R$"\ #,##0.00', 252000), r'R$ 252.000,00');
    });
  });

  group('percentual', () {
    test('0.00%', () {
      expect(fmt('0.00%', 0.25), '25,00%');
    });
    test('0%', () {
      expect(fmt('0%', 0.1), '10%');
    });
  });

  group('placeholders e agrupamento', () {
    test('#,##0 com milhões', () {
      expect(fmt('#,##0', 1234567), '1.234.567');
    });
    test('zero à esquerda com 0', () {
      expect(fmt('000', 7), '007');
    });
    test('# não mostra zero inteiro', () {
      expect(fmt('#', 0), '');
    });
    test('0.## mantém separador decimal (comportamento Excel)', () {
      expect(fmt('0.##', 1), '1,');
      expect(fmt('0.##', 1.5), '1,5');
      expect(fmt('0.##', 1.25), '1,25');
    });
    test('? preenche com espaço', () {
      expect(fmt('??0', 7), '  7');
    });
    test('vírgulas finais escalam por 1000', () {
      expect(fmt('#,##0,,', 12345678), '12');
      expect(fmt('0.0,', 12345), '12,3');
    });
  });

  group('arredondamento (metade para longe do zero, decimal exato)', () {
    test('1.005 -> 1,01', () {
      expect(fmt('0.00', 1.005), '1,01');
    });
    test('inteiro ganha casas', () {
      expect(fmt('0.00', 2), '2,00');
    });
    test('negativo com 1 seção ganha -', () {
      expect(fmt('0.00', -1.5), '-1,50');
    });
    test('negativo meio para longe do zero', () {
      expect(fmt('0', -0.5), '-1');
    });
  });

  group('científico', () {
    test('E+00', () {
      expect(fmt('0.00E+00', 12345), '1,23E+04');
      expect(fmt('0.00E+00', 0.0012), '1,20E-03');
      expect(fmt('0.00E+00', 0), '0,00E+00');
    });
    test('engenharia ##0.0E+0', () {
      expect(fmt('##0.0E+0', 12345), '12,3E+3');
    });
    test('carry renormaliza', () {
      expect(fmt('0.0E+00', 9.99e5), '1,0E+06');
    });
  });

  group('datas (sistema 1900 com bug)', () {
    test('serial 45000 = 15/03/2023', () {
      expect(fmt('dd/mm/yyyy', 45000), '15/03/2023');
    });
    test('bug 29/02/1900', () {
      expect(fmt('dd/mm/yyyy', 59), '28/02/1900');
      expect(fmt('dd/mm/yyyy', 60), '29/02/1900');
      expect(fmt('dd/mm/yyyy', 61), '01/03/1900');
      expect(fmt('dd/mm/yyyy', 1), '01/01/1900');
    });
    test('nomes pt-BR de mês e dia da semana', () {
      expect(fmt('d "de" mmmm "de" yyyy', 45000), '15 de março de 2023');
      expect(fmt('ddd', 45000), 'qua'); // 15/03/2023 = quarta-feira
      expect(fmt('dddd', 45000), 'quarta-feira');
      expect(fmt('mmm-yy', 45000), 'mar-23');
    });
    test('mm é mês quando não adjacente a h/s', () {
      expect(fmt('mm/yyyy', 45000), '03/2023');
    });
    test('isDateTime', () {
      expect(NumberFormat.compile('dd/mm/yyyy').isDateTime, isTrue);
      expect(NumberFormat.compile('#,##0.00').isDateTime, isFalse);
      expect(NumberFormat.compile('"h"0').isDateTime, isFalse);
      expect(NumberFormat.compile('[h]:mm').isDateTime, isTrue);
    });
  });

  group('horas', () {
    test('hh:mm:ss', () {
      expect(fmt('hh:mm:ss', 0.75), '18:00:00');
    });
    test('mm vira minuto adjacente a h ou ss', () {
      const serial = (12 * 3600 + 34 * 60 + 56) / 86400;
      expect(fmt('hh:mm', serial), '12:34');
      expect(fmt('mm:ss', serial), '34:56');
    });
    test('AM/PM', () {
      expect(fmt('h:mm AM/PM', 0.75), '6:00 PM');
      expect(fmt('h:mm AM/PM', 0.25), '6:00 AM');
    });
    test('decorrido [h]:mm:ss', () {
      expect(fmt('[h]:mm:ss', 1.5), '36:00:00');
    });
    test('data e hora juntas', () {
      expect(fmt('dd/mm/yyyy hh:mm', 45000.5), '15/03/2023 12:00');
    });
  });

  group('seções e condições', () {
    test('2 seções: negativo usa a 2a com valor absoluto', () {
      expect(fmt('0.0;(0.0)', -2.5), '(2,5)');
      expect(fmt('0.0;(0.0)', 2.5), '2,5');
    });
    test('3 seções: zero usa a 3a', () {
      expect(fmt('0;-0;"zero"', 0), 'zero');
    });
    test('condições [>=100]', () {
      expect(fmt('[>=100]"G"0;"P"0', 150), 'G150');
      expect(fmt('[>=100]"G"0;"P"0', 50), 'P50');
    });
    test('cores', () {
      expect(NumberFormat.compile('[Blue]0').format(1).colorArgbHex, '0000FF');
      expect(
        NumberFormat.compile('[Green]0;[Red]-0').format(-1).colorArgbHex,
        'FF0000',
      );
    });
    test('[Color n] é aceito e ignorado', () {
      final r = NumberFormat.compile('[Color 5]0.00').format(1);
      expect(r.text, '1,00');
      expect(r.colorArgbHex, isNull);
    });
    test('seção de texto', () {
      expect(fmt('0;-0;0;"txt: "@', 'x'), 'txt: x');
    });
    test('_x vira espaço', () {
      expect(fmt('0_)', 5), '5 ');
    });
  });

  group('builtins', () {
    test('ids principais', () {
      expect(NumberFormat.builtin(0).format(1.5).text, '1,5');
      expect(NumberFormat.builtin(2).format(1.5).text, '1,50');
      expect(NumberFormat.builtin(4).format(1234.5).text, '1.234,50');
      expect(NumberFormat.builtin(9).format(0.5).text, '50%');
      expect(NumberFormat.builtin(10).format(0.125).text, '12,50%');
      expect(NumberFormat.builtin(14).format(45000).text, '15/03/2023');
      expect(NumberFormat.builtin(22).format(45000.5).text, '15/03/2023 12:00');
      expect(NumberFormat.builtin(49).format('abc').text, 'abc');
      expect(NumberFormat.builtin(49).format(5).text, '5');
    });
    test('8 = moeda R\$ com [Red] no negativo', () {
      final f = NumberFormat.builtin(8);
      expect(f.format(1234.5).text, r'R$ 1.234,50');
      final neg = f.format(-1234.5);
      expect(neg.text, r'-R$ 1.234,50');
      expect(neg.colorArgbHex, 'FF0000');
    });
    test('44 = contábil R\$', () {
      final t = NumberFormat.builtin(44).format(1234.5).text;
      expect(t, contains(r'R$'));
      expect(t, contains('1.234,50'));
    });
    test('12/13 (frações) caem em General', () {
      expect(NumberFormat.builtin(12).format(1.5).text, '1,5');
    });
    test('id desconhecido -> General', () {
      expect(NumberFormat.builtin(23).format(7).text, '7');
      expect(NumberFormat.builtin(999).code, 'General');
    });
  });

  group('infra', () {
    test('compile é cacheado', () {
      expect(
        identical(NumberFormat.compile('0.00'), NumberFormat.compile('0.00')),
        isTrue,
      );
    });
    test('code preserva o original', () {
      expect(NumberFormat.compile('#,##0').code, '#,##0');
    });
    test('formato vazio/oculto', () {
      expect(fmt(';;;', 123), '');
      expect(fmt(';;;', 'x'), '');
    });
    test('string sem seção de texto passa direto', () {
      expect(fmt('0.00', 'abc'), 'abc');
    });
  });
}
