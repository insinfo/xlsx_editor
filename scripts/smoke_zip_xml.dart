// Smoke test do núcleo ZIP + XML com a planilha-alvo (roda na VM).
import 'dart:io';

import 'package:xlsx_editor/src/xml/dom.dart';
import 'package:xlsx_editor/src/zip/zip_archive.dart';

void main() {
  final bytes = File(
          'resources/PGCTIC1_-_PE_-_Planilha_de_Economicidade_-_Gestão_Pública.xlsx')
      .readAsBytesSync();
  final archive = ZipArchive.decodeBytes(bytes);
  print('entradas: ${archive.entries.length}');
  final sheet1 = archive.readBytes('xl/worksheets/sheet1.xml')!;
  print('sheet1: ${sheet1.length} bytes');
  final sw = Stopwatch()..start();
  final doc = XmlDocument.parseBytes(sheet1);
  sw.stop();
  final rows = doc.rootElement.firstChild('sheetData')!.childrenNamed('row');
  print('root=${doc.rootElement.qname} rows=${rows.length} '
      'parse=${sw.elapsedMilliseconds}ms');
  final merges = doc.rootElement.firstChild('mergeCells');
  print('merges=${merges?.getAttribute('count')}');
}
