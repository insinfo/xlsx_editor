/// Leitor de pacotes XLSX (OPC): workbook, sheets, sharedStrings, styles,
/// theme e drawings. Mantém o ZIP original para round-trip preservador.
library;

import 'dart:typed_data';

import '../formula/engine.dart' show translateFormula;
import '../model/styles.dart';
import '../model/workbook.dart';
import '../util/cell_ref.dart';
import '../xml/dom.dart';
import '../zip/zip_archive.dart';

class XlsxDocument {
  final Workbook workbook;

  /// Arquivo original (entradas não modeladas são preservadas ao salvar).
  final ZipArchive archive;

  /// Caminho da parte de cada sheet (ex.: xl/worksheets/sheet1.xml).
  final Map<String, String> sheetPartByName;

  XlsxDocument(this.workbook, this.archive, this.sheetPartByName);

  Uint8List? mediaBytes(String path) => archive.readBytes(path);
}

class XlsxReadException implements Exception {
  final String message;
  XlsxReadException(this.message);
  @override
  String toString() => 'XlsxReadException: $message';
}

XlsxDocument readXlsx(Uint8List bytes) {
  final archive = ZipArchive.decodeBytes(bytes);
  final workbook = Workbook();

  // 1. _rels/.rels -> parte officeDocument.
  final rootRels = _parseRels(archive, '_rels/.rels');
  final workbookPath = rootRels.values.firstWhere(
    (r) => r.type.endsWith('/officeDocument'),
    orElse: () => throw XlsxReadException('officeDocument não encontrado'),
  ).target;

  final wbDir = _dirOf(workbookPath);
  final wbXml = _parseXml(archive, workbookPath);
  final wbRels = _parseRels(
      archive, '$wbDir/_rels/${_baseName(workbookPath)}.rels');

  // 2. sharedStrings.
  final sstRel = _relOfType(wbRels, '/sharedStrings');
  if (sstRel != null) {
    _readSharedStrings(
        _parseXml(archive, _resolve(wbDir, sstRel.target)), workbook);
  }

  // 3. theme + styles.
  final themeRel = _relOfType(wbRels, '/theme');
  if (themeRel != null) {
    workbook.theme =
        _readTheme(_parseXml(archive, _resolve(wbDir, themeRel.target)));
  }
  final stylesRel = _relOfType(wbRels, '/styles');
  if (stylesRel != null) {
    workbook.styles =
        _readStyles(_parseXml(archive, _resolve(wbDir, stylesRel.target)));
  }

  // 4. sheets na ordem do workbook.xml.
  final sheetParts = <String, String>{};
  final sheetsEl = wbXml.rootElement.firstChild('sheets');
  if (sheetsEl == null) throw XlsxReadException('<sheets> ausente');
  for (final sheetEl in sheetsEl.childrenNamed('sheet')) {
    final name = sheetEl.getAttribute('name') ?? 'Sheet';
    final rId = sheetEl.getAttribute('r:id');
    final rel = rId != null ? wbRels[rId] : null;
    if (rel == null) continue;
    final partPath = _resolve(wbDir, rel.target);
    sheetParts[name] = partPath;
    final ws = Worksheet(name);
    _readWorksheet(_parseXml(archive, partPath), ws, workbook);
    workbook.sheets.add(ws);

    // Drawings da sheet (imagens ancoradas).
    final sheetRelsPath =
        '${_dirOf(partPath)}/_rels/${_baseName(partPath)}.rels';
    if (archive.findEntry(sheetRelsPath) != null) {
      final sheetRels = _parseRels(archive, sheetRelsPath);
      final drawingRel = _relOfType(sheetRels, '/drawing');
      if (drawingRel != null) {
        final drawingPath = _resolve(_dirOf(partPath), drawingRel.target);
        final images = _readDrawing(archive, drawingPath);
        if (images.isNotEmpty) workbook.imagesBySheet[name] = images;
      }
    }
  }

  // Aba ativa.
  final bookViews = wbXml.rootElement.firstChild('bookViews');
  final view = bookViews?.firstChild('workbookView');
  workbook.activeSheet =
      int.tryParse(view?.getAttribute('activeTab') ?? '0') ?? 0;
  if (workbook.activeSheet >= workbook.sheets.length) workbook.activeSheet = 0;

  return XlsxDocument(workbook, archive, sheetParts);
}

// ---------------------------------------------------------------------------
// Partes auxiliares
// ---------------------------------------------------------------------------

class _Rel {
  final String id, type, target;
  _Rel(this.id, this.type, this.target);
}

Map<String, _Rel> _parseRels(ZipArchive archive, String path) {
  final entry = archive.findEntry(path);
  if (entry == null) return {};
  final doc = XmlDocument.parseBytes(entry.content);
  final rels = <String, _Rel>{};
  for (final rel in doc.rootElement.childrenNamed('Relationship')) {
    final id = rel.getAttribute('Id') ?? '';
    rels[id] = _Rel(id, rel.getAttribute('Type') ?? '',
        rel.getAttribute('Target') ?? '');
  }
  return rels;
}

_Rel? _relOfType(Map<String, _Rel> rels, String suffix) {
  for (final rel in rels.values) {
    if (rel.type.endsWith(suffix)) return rel;
  }
  return null;
}

XmlDocument _parseXml(ZipArchive archive, String path) {
  final entry = archive.findEntry(path) ??
      (throw XlsxReadException('parte ausente: $path'));
  return XmlDocument.parseBytes(entry.content);
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

String _baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

/// Resolve target relativo (ex.: 'worksheets/sheet1.xml', '../media/x.png').
String _resolve(String baseDir, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = [...baseDir.split('/'), ...target.split('/')];
  final out = <String>[];
  for (final p in parts) {
    if (p.isEmpty || p == '.') continue;
    if (p == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else {
      out.add(p);
    }
  }
  return out.join('/');
}

// ---------------------------------------------------------------------------
// sharedStrings
// ---------------------------------------------------------------------------

void _readSharedStrings(XmlDocument doc, Workbook wb) {
  for (final si in doc.rootElement.childrenNamed('si')) {
    final direct = si.firstChild('t');
    if (direct != null) {
      wb.sharedStrings.add(direct.text);
      continue;
    }
    // Rich text: concatena os runs.
    final sb = StringBuffer();
    for (final r in si.childrenNamed('r')) {
      sb.write(r.firstChild('t')?.text ?? '');
    }
    wb.sharedStrings.add(sb.toString());
  }
}

// ---------------------------------------------------------------------------
// theme
// ---------------------------------------------------------------------------

Theme _readTheme(XmlDocument doc) {
  XmlElement? clrScheme;
  for (final el in doc.rootElement.descendants) {
    if (el.localName == 'clrScheme') {
      clrScheme = el;
      break;
    }
  }
  if (clrScheme == null) return Theme.fallback();
  final colors = <String>[];
  for (final slot in clrScheme.childElements) {
    String? hex;
    for (final c in slot.childElements) {
      if (c.localName == 'srgbClr') {
        hex = c.getAttribute('val');
      } else if (c.localName == 'sysClr') {
        hex = c.getAttribute('lastClr') ?? c.getAttribute('val');
      }
    }
    colors.add('#${(hex ?? '000000').toUpperCase()}');
  }
  return colors.length >= 12 ? Theme(colors) : Theme.fallback();
}

// ---------------------------------------------------------------------------
// styles.xml
// ---------------------------------------------------------------------------

XlsxColor _readColor(XmlElement el) {
  final rgb = el.getAttribute('rgb');
  if (rgb != null) return XlsxColor.rgbHex(rgb);
  final indexed = el.getAttribute('indexed');
  if (indexed != null) return XlsxColor.indexedColor(int.parse(indexed));
  final theme = el.getAttribute('theme');
  if (theme != null) {
    final tint = double.tryParse(el.getAttribute('tint') ?? '') ?? 0;
    return XlsxColor.themeColor(int.parse(theme), tint);
  }
  return const XlsxColor.autoColor();
}

StyleTable _readStyles(XmlDocument doc) {
  final root = doc.rootElement;
  final numFmts = <int, String>{};
  final numFmtsEl = root.firstChild('numFmts');
  if (numFmtsEl != null) {
    for (final f in numFmtsEl.childrenNamed('numFmt')) {
      final id = int.tryParse(f.getAttribute('numFmtId') ?? '');
      final code = f.getAttribute('formatCode');
      if (id != null && code != null) numFmts[id] = code;
    }
  }

  final fonts = <XlsxFont>[];
  final fontsEl = root.firstChild('fonts');
  if (fontsEl != null) {
    for (final f in fontsEl.childrenNamed('font')) {
      var font = const XlsxFont();
      for (final child in f.childElements) {
        switch (child.localName) {
          case 'name':
            font = font.copyWith(name: child.getAttribute('val') ?? font.name);
          case 'sz':
            font = font.copyWith(
                size: double.tryParse(child.getAttribute('val') ?? '') ??
                    font.size);
          case 'b':
            font = font.copyWith(bold: child.getAttribute('val') != '0');
          case 'i':
            font = font.copyWith(italic: child.getAttribute('val') != '0');
          case 'u':
            font =
                font.copyWith(underline: child.getAttribute('val') != 'none');
          case 'strike':
            font = font.copyWith(strike: child.getAttribute('val') != '0');
          case 'color':
            font = font.copyWith(color: _readColor(child));
        }
      }
      fonts.add(font);
    }
  }

  final fills = <XlsxFill>[];
  final fillsEl = root.firstChild('fills');
  if (fillsEl != null) {
    for (final f in fillsEl.childrenNamed('fill')) {
      final pattern = f.firstChild('patternFill');
      if (pattern == null) {
        fills.add(const XlsxFill());
        continue;
      }
      final fg = pattern.firstChild('fgColor');
      final bg = pattern.firstChild('bgColor');
      fills.add(XlsxFill(
        patternType: pattern.getAttribute('patternType') ?? 'none',
        fgColor: fg != null ? _readColor(fg) : null,
        bgColor: bg != null ? _readColor(bg) : null,
      ));
    }
  }

  final borders = <XlsxBorder>[];
  final bordersEl = root.firstChild('borders');
  if (bordersEl != null) {
    for (final b in bordersEl.childrenNamed('border')) {
      BorderSide side(String name) {
        final el = b.firstChild(name);
        if (el == null) return const BorderSide();
        final style = el.getAttribute('style') ?? 'none';
        final colorEl = el.firstChild('color');
        return BorderSide(
            style: style,
            color: colorEl != null
                ? _readColor(colorEl)
                : const XlsxColor.autoColor());
      }

      borders.add(XlsxBorder(
        left: side('left'),
        right: side('right'),
        top: side('top'),
        bottom: side('bottom'),
      ));
    }
  }

  // cellStyleXfs (pais) e cellXfs (efetivos).
  List<CellXf> readXfList(XmlElement? listEl, List<CellXf>? parents) {
    final result = <CellXf>[];
    if (listEl == null) return result;
    for (final xf in listEl.childrenNamed('xf')) {
      int attr(String name, int def) =>
          int.tryParse(xf.getAttribute(name) ?? '') ?? def;
      final xfId = int.tryParse(xf.getAttribute('xfId') ?? '');
      final parent = (parents != null &&
              xfId != null &&
              xfId >= 0 &&
              xfId < parents.length)
          ? parents[xfId]
          : null;

      XlsxAlignment? alignment;
      final alignEl = xf.firstChild('alignment');
      if (alignEl != null) {
        alignment = XlsxAlignment(
          horizontal: alignEl.getAttribute('horizontal') ?? 'general',
          vertical: alignEl.getAttribute('vertical') ?? 'bottom',
          wrapText: alignEl.getAttribute('wrapText') == '1',
          textRotation:
              int.tryParse(alignEl.getAttribute('textRotation') ?? '') ?? 0,
          indent: int.tryParse(alignEl.getAttribute('indent') ?? '') ?? 0,
          shrinkToFit: alignEl.getAttribute('shrinkToFit') == '1',
        );
      } else {
        alignment = parent?.alignment;
      }

      result.add(CellXf(
        numFmtId: attr('numFmtId', parent?.numFmtId ?? 0),
        fontId: attr('fontId', parent?.fontId ?? 0),
        fillId: attr('fillId', parent?.fillId ?? 0),
        borderId: attr('borderId', parent?.borderId ?? 0),
        alignment: alignment,
      ));
    }
    return result;
  }

  final styleXfs = readXfList(root.firstChild('cellStyleXfs'), null);
  final cellXfs = readXfList(root.firstChild('cellXfs'), styleXfs);

  final table = StyleTable(
    fonts: fonts.isEmpty ? null : fonts,
    fills: fills.isEmpty ? null : fills,
    borders: borders.isEmpty ? null : borders,
    cellXfs: cellXfs.isEmpty ? null : cellXfs,
    numFmts: numFmts,
  );
  table.originalFontCount = table.fonts.length;
  table.originalFillCount = table.fills.length;
  table.originalBorderCount = table.borders.length;
  table.originalXfCount = table.cellXfs.length;
  return table;
}

// ---------------------------------------------------------------------------
// worksheet
// ---------------------------------------------------------------------------

void _readWorksheet(XmlDocument doc, Worksheet ws, Workbook wb) {
  final root = doc.rootElement;

  final fmtPr = root.firstChild('sheetFormatPr');
  if (fmtPr != null) {
    ws.defaultRowHeightPt =
        double.tryParse(fmtPr.getAttribute('defaultRowHeight') ?? '') ??
            ws.defaultRowHeightPt;
    ws.defaultColWidthChars =
        double.tryParse(fmtPr.getAttribute('defaultColWidth') ?? '') ??
            ws.defaultColWidthChars;
  }

  final viewEl = root.firstChild('sheetViews')?.firstChild('sheetView');
  if (viewEl != null) {
    ws.showGridLines = viewEl.getAttribute('showGridLines') != '0';
    final zoom = int.tryParse(viewEl.getAttribute('zoomScale') ?? '');
    if (zoom != null) ws.zoomScale = zoom / 100.0;
  }

  final colsEl = root.firstChild('cols');
  if (colsEl != null) {
    for (final col in colsEl.childrenNamed('col')) {
      final min = int.tryParse(col.getAttribute('min') ?? '') ?? 1;
      final max = int.tryParse(col.getAttribute('max') ?? '') ?? min;
      final width = double.tryParse(col.getAttribute('width') ?? '');
      final hidden = col.getAttribute('hidden') == '1';
      final style = int.tryParse(col.getAttribute('style') ?? '');
      final custom = col.getAttribute('customWidth') == '1';
      // Limita a expansão de faixas gigantes (ex.: max=16384).
      final boundedMax = max.clamp(min, min + 2048);
      for (var c = min; c <= boundedMax; c++) {
        ws.colProps[c - 1] = ColProps(
          width: (custom || width != null) ? width : null,
          hidden: hidden,
          styleIndex: style,
        );
      }
    }
  }

  // Fórmulas compartilhadas: si -> (texto base, célula base).
  final sharedFormulas = <int, (String, int, int)>{};

  final sheetData = root.firstChild('sheetData');
  if (sheetData != null) {
    for (final rowEl in sheetData.childrenNamed('row')) {
      final r = (int.tryParse(rowEl.getAttribute('r') ?? '') ?? 1) - 1;
      final ht = double.tryParse(rowEl.getAttribute('ht') ?? '');
      final hidden = rowEl.getAttribute('hidden') == '1';
      final customFormat = rowEl.getAttribute('customFormat') == '1';
      final rowStyle = int.tryParse(rowEl.getAttribute('s') ?? '');
      if (ht != null || hidden || (customFormat && rowStyle != null)) {
        ws.rowProps[r] = RowProps(
          height: ht,
          hidden: hidden,
          styleIndex: customFormat ? rowStyle : null,
        );
      }
      if (r > ws.maxRow) ws.maxRow = r;

      for (final cEl in rowEl.childrenNamed('c')) {
        final refText = cEl.getAttribute('r');
        final ref = refText != null ? CellRef.tryParse(refText) : null;
        if (ref == null) continue;
        final row = ref.row, col = ref.col;
        final type = cEl.getAttribute('t') ?? 'n';
        final styleIdx = int.tryParse(cEl.getAttribute('s') ?? '') ?? 0;

        final vEl = cEl.firstChild('v');
        final fEl = cEl.firstChild('f');

        CellValue? value;
        final vText = vEl?.text;
        switch (type) {
          case 's':
            final idx = int.tryParse(vText ?? '');
            if (idx != null && idx < wb.sharedStrings.length) {
              value = TextValue(wb.sharedStrings[idx]);
            }
          case 'str':
            if (vText != null) value = TextValue(vText);
          case 'inlineStr':
            final t = cEl.firstChild('is')?.firstChild('t');
            if (t != null) value = TextValue(t.text);
          case 'b':
            if (vText != null) value = BoolValue(vText == '1');
          case 'e':
            if (vText != null) value = ErrorValue(vText);
          default:
            final n = double.tryParse(vText ?? '');
            if (n != null) value = NumberValue(n);
        }

        String? formula;
        var isArray = false;
        if (fEl != null) {
          final fType = fEl.getAttribute('t');
          final fText = fEl.text;
          if (fType == 'shared') {
            final si = int.tryParse(fEl.getAttribute('si') ?? '') ?? -1;
            if (fText.isNotEmpty) {
              sharedFormulas[si] = (fText, row, col);
              formula = fText;
            } else {
              final master = sharedFormulas[si];
              if (master != null) {
                formula = translateFormula(
                    master.$1, row - master.$2, col - master.$3);
              }
            }
          } else if (fType == 'array') {
            formula = fText.isEmpty ? null : fText;
            isArray = true;
          } else if (fText.isNotEmpty) {
            formula = fText;
          }
        }

        if (value == null && formula == null && styleIdx == 0) continue;
        final cell = ws.ensureCell(row, col);
        cell
          ..value = value
          ..formula = formula
          ..isArrayFormula = isArray
          ..styleIndex = styleIdx;
      }
    }
  }

  final mergesEl = root.firstChild('mergeCells');
  if (mergesEl != null) {
    for (final m in mergesEl.childrenNamed('mergeCell')) {
      final range = CellRange.tryParse(m.getAttribute('ref') ?? '');
      if (range != null) ws.addMerge(range);
    }
  }
}

// ---------------------------------------------------------------------------
// drawings (imagens ancoradas)
// ---------------------------------------------------------------------------

List<SheetImage> _readDrawing(ZipArchive archive, String drawingPath) {
  final entry = archive.findEntry(drawingPath);
  if (entry == null) return [];
  final doc = XmlDocument.parseBytes(entry.content);
  final relsPath =
      '${_dirOf(drawingPath)}/_rels/${_baseName(drawingPath)}.rels';
  final rels = _parseRels(archive, relsPath);

  final images = <SheetImage>[];
  for (final anchor in doc.rootElement.childElements) {
    if (anchor.localName != 'twoCellAnchor' &&
        anchor.localName != 'oneCellAnchor') {
      continue;
    }
    XmlElement? fromEl, toEl, blip;
    for (final el in anchor.descendants) {
      switch (el.localName) {
        case 'from':
          fromEl = el;
        case 'to':
          toEl = el;
        case 'blip':
          blip = el;
      }
    }
    if (fromEl == null || blip == null) continue;
    final embed = blip.getAttribute('r:embed');
    final rel = embed != null ? rels[embed] : null;
    if (rel == null) continue;
    final mediaPath = _resolve(_dirOf(drawingPath), rel.target);

    (int, int, double, double) anchorPoint(XmlElement el) {
      int child(String name) {
        for (final c in el.childElements) {
          if (c.localName == name) return int.tryParse(c.text) ?? 0;
        }
        return 0;
      }

      return (
        child('row'),
        child('col'),
        child('rowOff').toDouble(),
        child('colOff').toDouble()
      );
    }

    final from = anchorPoint(fromEl);
    final to = toEl != null
        ? anchorPoint(toEl)
        : (from.$1 + 3, from.$2 + 2, 0.0, 0.0);
    images.add(SheetImage(
      fromRow: from.$1,
      fromCol: from.$2,
      fromRowOff: from.$3,
      fromColOff: from.$4,
      toRow: to.$1,
      toCol: to.$2,
      toRowOff: to.$3,
      toColOff: to.$4,
      mediaPath: mediaPath,
    ));
  }
  return images;
}
