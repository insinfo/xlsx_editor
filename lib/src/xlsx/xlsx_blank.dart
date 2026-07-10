/// Pacote .xlsx mínimo gerado em memória, para abrir o editor sem arquivo.
///
/// O writer é um reescritor round-trip (exige as partes originais no ZIP),
/// então o workbook vazio é montado como um pacote OPC completo e lido pelo
/// [readXlsx] — garantindo consistência com o reader/writer.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../zip/zip_archive.dart';
import 'xlsx_reader.dart';

const String _contentTypes = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>
''';

const String _rootRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
''';

const String _workbookRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>
''';

const String _styles = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><color theme="1"/><name val="Calibri"/></font></fonts>
  <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
''';

const String _sharedStrings = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="0" uniqueCount="0"/>
''';

const String _sheet = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <dimension ref="A1"/>
  <sheetViews><sheetView workbookViewId="0"/></sheetViews>
  <sheetFormatPr defaultRowHeight="15"/>
  <sheetData/>
</worksheet>
''';

/// Bytes de um .xlsx vazio com uma única planilha [sheetName].
Uint8List blankXlsxBytes({String sheetName = 'Planilha1'}) {
  final workbook = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="${_escapeXml(sheetName)}" sheetId="1" r:id="rId1"/></sheets>
  <calcPr calcId="0" fullCalcOnLoad="1"/>
</workbook>
''';
  final archive = ZipArchive();
  archive.setFile('[Content_Types].xml', utf8.encode(_contentTypes));
  archive.setFile('_rels/.rels', utf8.encode(_rootRels));
  archive.setFile('xl/workbook.xml', utf8.encode(workbook));
  archive.setFile('xl/_rels/workbook.xml.rels', utf8.encode(_workbookRels));
  archive.setFile('xl/styles.xml', utf8.encode(_styles));
  archive.setFile('xl/sharedStrings.xml', utf8.encode(_sharedStrings));
  archive.setFile('xl/worksheets/sheet1.xml', utf8.encode(_sheet));
  return archive.encode();
}

/// Documento vazio pronto para o editor.
XlsxDocument blankXlsxDocument({String sheetName = 'Planilha1'}) =>
    readXlsx(blankXlsxBytes(sheetName: sheetName));

String _escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
