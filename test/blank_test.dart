import 'package:test/test.dart';
import 'package:xlsx_editor/src/model/workbook.dart';
import 'package:xlsx_editor/src/xlsx/xlsx_blank.dart';
import 'package:xlsx_editor/src/xlsx/xlsx_reader.dart';
import 'package:xlsx_editor/src/xlsx/xlsx_writer.dart';

void main() {
  test('blank xlsx abre, edita e faz round-trip', () {
    final doc = blankXlsxDocument(sheetName: 'Teste');
    expect(doc.workbook.sheets, hasLength(1));
    expect(doc.workbook.sheets.first.name, 'Teste');

    // Edita uma célula e salva.
    final sheet = doc.workbook.sheets.first;
    sheet.ensureCell(0, 0).value = const NumberValue(42);
    sheet.ensureCell(1, 0).value = const TextValue('olá');
    doc.workbook.sharedStrings.add('olá');
    final bytes = writeXlsx(doc);

    // Relê o resultado.
    final reread = readXlsx(bytes);
    final s = reread.workbook.sheets.first;
    expect((s.cellAt(0, 0)!.value as NumberValue).value, 42);
  });
}
