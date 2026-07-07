import 'dart:io';

import 'package:test/test.dart';
import 'package:xlsx_editor/src/model/workbook.dart';
import 'package:xlsx_editor/src/util/cell_ref.dart';
import 'package:xlsx_editor/src/xlsx/xlsx_reader.dart';
import 'package:xlsx_editor/src/xlsx/xlsx_writer.dart';

void main() {
  final bytes = File(
          'resources/PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx')
      .readAsBytesSync();

  group('Leitura da planilha-alvo', () {
    late XlsxDocument doc;

    setUpAll(() {
      doc = readXlsx(bytes);
    });

    test('abas na ordem correta', () {
      expect(doc.workbook.sheets.map((s) => s.name).toList(),
          ['MÉDIA', 'Composições']);
    });

    test('shared strings e estilos', () {
      expect(doc.workbook.sharedStrings.length, 113);
      expect(doc.workbook.styles.cellXfs.length, 155);
      expect(doc.workbook.styles.fonts.length, 28);
      expect(doc.workbook.styles.borders.length, 15);
    });

    test('merges', () {
      expect(doc.workbook.sheets[0].merges.length, 116);
      expect(doc.workbook.sheets[1].merges.length, 29);
    });

    test('células e fórmulas', () {
      final media = doc.workbook.sheets[0];
      // A1: título mesclado.
      final a1 = media.cellAt(0, 0);
      expect((a1!.value as TextValue).value,
          contains('PLANILHA DE ECONOMICIDADE'));

      // M262: =SUM(E262:E265) com valor em cache.
      final m262 = media.cellAt(261, 12);
      expect(m262, isNotNull);

      // Composições D40: 252000 (serviço de implantação).
      final comp = doc.workbook.sheets[1];
      final d40 = comp.cellAt(39, 3);
      expect((d40!.value as NumberValue).value, 252000);
    });

    test('fórmulas compartilhadas expandidas por deslocamento', () {
      final media = doc.workbook.sheets[0];
      // si=0: master H7 = IF(G7="...","-",D7); H8 deve ser IF(G8=...,D8).
      final h7 = media.cellAt(6, 7);
      final h8 = media.cellAt(7, 7);
      expect(h7!.formula, contains('G7'));
      expect(h8!.formula, contains('G8'));
      expect(h8.formula, contains('D8'));
    });

    test('imagens ancoradas (logo)', () {
      expect(doc.workbook.imagesBySheet['Composições'], isNotEmpty);
    });

    test('larguras de coluna e alturas de linha', () {
      final media = doc.workbook.sheets[0];
      expect(media.colProps[0]?.width, closeTo(13.42578125, 0.001));
      expect(media.defaultRowHeightPt, closeTo(12.75, 0.001));
    });
  });

  group('Round-trip', () {
    test('salvar e reler mantém valores', () {
      final doc = readXlsx(bytes);
      final out = writeXlsx(doc);
      final doc2 = readXlsx(out);

      expect(doc2.workbook.sheets.length, 2);
      final media1 = doc.workbook.sheets[0];
      final media2 = doc2.workbook.sheets[0];
      expect(media2.merges.length, media1.merges.length);

      // Amostra células: mesmos valores e estilos.
      var compared = 0;
      for (final entry in media1.cells.entries) {
        final ref = CellRef.fromPacked(entry.key);
        final c1 = entry.value;
        final c2 = media2.cellAt(ref.row, ref.col);
        if (c1.value == null) continue;
        expect(c2, isNotNull, reason: 'célula ${ref.a1} sumiu');
        expect(c2!.styleIndex, c1.styleIndex, reason: 'estilo ${ref.a1}');
        switch (c1.value) {
          case NumberValue(:final value):
            expect((c2.value as NumberValue).value, value,
                reason: 'valor ${ref.a1}');
          case TextValue(:final value):
            expect((c2.value as TextValue).value, value,
                reason: 'texto ${ref.a1}');
          default:
            break;
        }
        compared++;
      }
      expect(compared, greaterThan(1000));

      // calcChain removida e content types ajustado.
      expect(doc2.archive.findEntry('xl/calcChain.xml'), isNull);
    });
  });
}
