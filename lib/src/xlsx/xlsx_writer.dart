/// Gravador XLSX round-trip preservador: reescreve apenas as partes
/// modeladas (sheetData/cols/mergeCells, sharedStrings, styles) dentro do
/// DOM original; todas as demais entradas do ZIP são preservadas.
library;

import 'dart:typed_data';

import '../model/styles.dart';
import '../model/workbook.dart';
import '../util/cell_ref.dart';
import '../xml/dom.dart';
import 'xlsx_reader.dart';

Uint8List writeXlsx(XlsxDocument doc) {
  final archive = doc.archive;
  final wb = doc.workbook;

  // sharedStrings: reconstruída a partir da lista (append-only preservador).
  _writeSharedStrings(doc);

  for (final sheet in wb.sheets) {
    final partPath = doc.sheetPartByName[sheet.name];
    if (partPath == null) continue;
    _rewriteSheetPart(archive_readDoc(doc, partPath), sheet, wb, doc, partPath);
  }

  _rewriteStyles(doc);
  _patchWorkbookCalcPr(doc);
  _removeCalcChain(doc);

  return archive.encode();
}

XmlDocument archive_readDoc(XlsxDocument doc, String path) {
  final entry = doc.archive.findEntry(path);
  if (entry == null) throw XlsxReadException('parte ausente: $path');
  return XmlDocument.parseBytes(entry.content);
}

/// Define (ou substitui) um atributo de um elemento.
void _setAttr(XmlElement el, String name, String value) {
  for (final attr in el.attributes) {
    if (attr.qname == name) {
      attr.value = value;
      return;
    }
  }
  el.attributes.add(XmlAttribute(name, value));
}

XmlElement _el(String qname,
        [Map<String, String>? attrs, List<XmlNode>? children]) =>
    XmlElement(
      qname,
      attrs?.entries.map((e) => XmlAttribute(e.key, e.value)).toList(),
      children,
    );

String _numToXml(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    return v.round().toString();
  }
  return v.toString();
}

// ---------------------------------------------------------------------------
// sharedStrings
// ---------------------------------------------------------------------------

void _writeSharedStrings(XlsxDocument doc) {
  final wb = doc.workbook;
  if (wb.sharedStrings.isEmpty) return;
  final children = <XmlNode>[];
  for (final s in wb.sharedStrings) {
    final t = _el('t', null, [XmlText(s)]);
    if (s.startsWith(' ') || s.endsWith(' ')) {
      t.attributes.add(XmlAttribute('xml:space', 'preserve'));
    }
    children.add(_el('si', null, [t]));
  }
  final root = _el(
    'sst',
    {
      'xmlns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
      'count': '${wb.sharedStrings.length}',
      'uniqueCount': '${wb.sharedStrings.length}',
    },
    children,
  );
  final newDoc = XmlDocument(
    declaration:
        XmlDeclaration(version: '1.0', encoding: 'UTF-8', standalone: 'yes'),
    children: [root],
  );
  doc.archive.setFile('xl/sharedStrings.xml', newDoc.toUtf8Bytes());
}

// ---------------------------------------------------------------------------
// worksheet
// ---------------------------------------------------------------------------

/// Índice (ou -1) de um filho direto por qname.
int _childIndex(XmlElement parent, String qname) {
  for (var i = 0; i < parent.children.length; i++) {
    final c = parent.children[i];
    if (c is XmlElement && c.qname == qname) return i;
  }
  return -1;
}

/// Ordem canônica dos filhos de <worksheet> (subconjunto relevante) para
/// inserir elementos novos na posição certa.
const _worksheetOrder = [
  'sheetPr', 'dimension', 'sheetViews', 'sheetFormatPr', 'cols', 'sheetData',
  'sheetCalcPr', 'sheetProtection', 'protectedRanges', 'scenarios',
  'autoFilter', 'sortState', 'dataConsolidate', 'customSheetViews',
  'mergeCells', 'phoneticPr', 'conditionalFormatting', 'dataValidations',
  'hyperlinks', 'printOptions', 'pageMargins', 'pageSetup', 'headerFooter',
  'rowBreaks', 'colBreaks', 'customProperties', 'cellWatches',
  'ignoredErrors', 'smartTags', 'drawing',
];

void _insertInOrder(XmlElement root, XmlElement newChild) {
  final myOrder = _worksheetOrder.indexOf(newChild.qname);
  for (var i = 0; i < root.children.length; i++) {
    final c = root.children[i];
    if (c is! XmlElement) continue;
    final order = _worksheetOrder.indexOf(c.qname);
    if (order > myOrder && order != -1) {
      root.children.insert(i, newChild);
      newChild.parent = root;
      return;
    }
  }
  root.children.add(newChild);
  newChild.parent = root;
}

void _rewriteSheetPart(XmlDocument original, Worksheet sheet, Workbook wb,
    XlsxDocument doc, String partPath) {
  final root = original.rootElement;

  // <dimension>
  final dimIdx = _childIndex(root, 'dimension');
  if (dimIdx >= 0) {
    final dim = root.children[dimIdx] as XmlElement;
    _setAttr(dim, 'ref', CellRange(0, 0, sheet.maxRow, sheet.maxCol).a1);
  }

  // <cols>
  final colsEl = _buildCols(sheet);
  final colsIdx = _childIndex(root, 'cols');
  if (colsIdx >= 0) {
    if (colsEl != null) {
      colsEl.parent = root;
      root.children[colsIdx] = colsEl;
    } else {
      root.children.removeAt(colsIdx);
    }
  } else if (colsEl != null) {
    _insertInOrder(root, colsEl);
  }

  // <sheetData>
  final sheetDataEl = _buildSheetData(sheet, wb);
  final dataIdx = _childIndex(root, 'sheetData');
  if (dataIdx >= 0) {
    sheetDataEl.parent = root;
    root.children[dataIdx] = sheetDataEl;
  } else {
    _insertInOrder(root, sheetDataEl);
  }

  // <mergeCells>
  final mergeIdx = _childIndex(root, 'mergeCells');
  if (sheet.merges.isEmpty) {
    if (mergeIdx >= 0) root.children.removeAt(mergeIdx);
  } else {
    final mergesEl = _el('mergeCells', {'count': '${sheet.merges.length}'},
        [for (final m in sheet.merges) _el('mergeCell', {'ref': m.a1})]);
    if (mergeIdx >= 0) {
      mergesEl.parent = root;
      root.children[mergeIdx] = mergesEl;
    } else {
      _insertInOrder(root, mergesEl);
    }
  }

  doc.archive.setFile(partPath, original.toUtf8Bytes());
}

XmlElement? _buildCols(Worksheet sheet) {
  if (sheet.colProps.isEmpty) return null;
  final indices = sheet.colProps.keys.toList()..sort();
  final children = <XmlNode>[];
  // Agrupa colunas consecutivas com as mesmas propriedades.
  var i = 0;
  while (i < indices.length) {
    final start = indices[i];
    final p = sheet.colProps[start]!;
    var end = start;
    while (i + 1 < indices.length && indices[i + 1] == end + 1) {
      final q = sheet.colProps[indices[i + 1]]!;
      if (q.width != p.width ||
          q.hidden != p.hidden ||
          q.styleIndex != p.styleIndex) {
        break;
      }
      end++;
      i++;
    }
    final attrs = <String, String>{
      'min': '${start + 1}',
      'max': '${end + 1}',
    };
    final w = p.width;
    if (w != null) {
      attrs['width'] = w.toString();
      attrs['customWidth'] = '1';
    } else {
      attrs['width'] = '9';
    }
    if (p.hidden) attrs['hidden'] = '1';
    final s = p.styleIndex;
    if (s != null) attrs['style'] = '$s';
    children.add(_el('col', attrs));
    i++;
  }
  return _el('cols', null, children);
}

XmlElement _buildSheetData(Worksheet sheet, Workbook wb) {
  // Organiza células por linha.
  final byRow = <int, List<(int, Cell)>>{};
  for (final entry in sheet.cells.entries) {
    final ref = CellRef.fromPacked(entry.key);
    if (entry.value.isEmpty && entry.value.styleIndex == 0) continue;
    byRow.putIfAbsent(ref.row, () => []).add((ref.col, entry.value));
  }
  final rowIndices = {...byRow.keys, ...sheet.rowProps.keys}.toList()..sort();

  final rows = <XmlNode>[];
  for (final r in rowIndices) {
    final cellsInRow = byRow[r] ?? const [];
    final props = sheet.rowProps[r];
    if (cellsInRow.isEmpty && props == null) continue;
    final attrs = <String, String>{'r': '${r + 1}'};
    if (props != null) {
      final h = props.height;
      if (h != null) {
        attrs['ht'] = h.toString();
        attrs['customHeight'] = '1';
      }
      if (props.hidden) attrs['hidden'] = '1';
      final s = props.styleIndex;
      if (s != null) {
        attrs['s'] = '$s';
        attrs['customFormat'] = '1';
      }
    }
    final cellNodes = <XmlNode>[];
    final sorted = [...cellsInRow]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (c, cell) in sorted) {
      final node = _buildCell(r, c, cell, wb);
      if (node != null) cellNodes.add(node);
    }
    rows.add(_el('row', attrs, cellNodes));
  }
  return _el('sheetData', null, rows);
}

XmlNode? _buildCell(int row, int col, Cell cell, Workbook wb) {
  final attrs = <String, String>{'r': CellRef(row, col).a1};
  if (cell.styleIndex != 0) attrs['s'] = '${cell.styleIndex}';

  final children = <XmlNode>[];
  final formula = cell.formula;
  if (formula != null) {
    final fAttrs = <String, String>{};
    if (cell.isArrayFormula) {
      fAttrs['t'] = 'array';
      fAttrs['ref'] = CellRef(row, col).a1;
    }
    children.add(_el('f', fAttrs, [XmlText(formula)]));
  }

  switch (cell.value) {
    case NumberValue(:final value):
      children.add(_el('v', null, [XmlText(_numToXml(value))]));
    case TextValue(:final value):
      if (formula != null) {
        attrs['t'] = 'str';
        children.add(_el('v', null, [XmlText(value)]));
      } else {
        attrs['t'] = 's';
        attrs.remove('t');
        // Usa shared strings (índice existente ou novo).
        var idx = wb.sharedStrings.indexOf(value);
        if (idx < 0) {
          wb.sharedStrings.add(value);
          idx = wb.sharedStrings.length - 1;
        }
        attrs['t'] = 's';
        children.add(_el('v', null, [XmlText('$idx')]));
      }
    case BoolValue(:final value):
      attrs['t'] = 'b';
      children.add(_el('v', null, [XmlText(value ? '1' : '0')]));
    case ErrorValue(:final code):
      attrs['t'] = 'e';
      children.add(_el('v', null, [XmlText(code)]));
    case null:
      if (formula == null && cell.styleIndex == 0) return null;
  }
  return _el('c', attrs, children);
}

// ---------------------------------------------------------------------------
// styles.xml — acrescenta registros novos criados pela edição
// ---------------------------------------------------------------------------

void _rewriteStyles(XlsxDocument doc) {
  final st = doc.workbook.styles;
  final hasNew = st.fonts.length > st.originalFontCount ||
      st.fills.length > st.originalFillCount ||
      st.borders.length > st.originalBorderCount ||
      st.cellXfs.length > st.originalXfCount;
  if (!hasNew) return;

  final xmlDoc = archive_readDoc(doc, 'xl/styles.xml');
  final root = xmlDoc.rootElement;

  XmlElement colorEl(String qname, XlsxColor c) {
    final attrs = <String, String>{};
    if (c.rgb != null) {
      attrs['rgb'] = c.rgb!.length == 6 ? 'FF${c.rgb}' : c.rgb!;
    } else if (c.indexed != null) {
      attrs['indexed'] = '${c.indexed}';
    } else if (c.theme != null) {
      attrs['theme'] = '${c.theme}';
      if (c.tint != 0) attrs['tint'] = '${c.tint}';
    } else {
      attrs['auto'] = '1';
    }
    return _el(qname, attrs);
  }

  void ensureListAndAppend(
      String listName, String childName, int originalCount, int newCount,
      XmlElement Function(int index) build) {
    if (newCount <= originalCount) return;
    var listIdx = _childIndex(root, listName);
    XmlElement listEl;
    if (listIdx < 0) {
      listEl = _el(listName, {'count': '0'});
      root.children.insert(0, listEl);
      listEl.parent = root;
    } else {
      listEl = root.children[listIdx] as XmlElement;
    }
    for (var i = originalCount; i < newCount; i++) {
      final el = build(i);
      el.parent = listEl;
      listEl.children.add(el);
    }
    _setAttr(listEl, 'count', '$newCount');
  }

  // numFmts novos (id >= 164 que não estavam no arquivo).
  final numFmtsIdx = _childIndex(root, 'numFmts');
  final existingIds = <int>{};
  if (numFmtsIdx >= 0) {
    final listEl = root.children[numFmtsIdx] as XmlElement;
    for (final f in listEl.childrenNamed('numFmt')) {
      final id = int.tryParse(f.getAttribute('numFmtId') ?? '');
      if (id != null) existingIds.add(id);
    }
    for (final e in st.numFmts.entries) {
      if (e.key >= 164 && !existingIds.contains(e.key)) {
        final el = _el('numFmt',
            {'numFmtId': '${e.key}', 'formatCode': e.value});
        el.parent = listEl;
        listEl.children.add(el);
      }
    }
    _setAttr(listEl, 'count', '${listEl.children.length}');
  }

  ensureListAndAppend('fonts', 'font', st.originalFontCount, st.fonts.length,
      (i) {
    final f = st.fonts[i];
    final children = <XmlNode>[
      if (f.bold) _el('b'),
      if (f.italic) _el('i'),
      if (f.underline) _el('u'),
      if (f.strike) _el('strike'),
      _el('sz', {'val': '${f.size}'}),
      colorEl('color', f.color),
      _el('name', {'val': f.name}),
    ];
    return _el('font', null, children);
  });

  ensureListAndAppend('fills', 'fill', st.originalFillCount, st.fills.length,
      (i) {
    final f = st.fills[i];
    final pattern = _el('patternFill', {'patternType': f.patternType}, [
      if (f.fgColor != null) colorEl('fgColor', f.fgColor!),
      if (f.bgColor != null) colorEl('bgColor', f.bgColor!),
    ]);
    return _el('fill', null, [pattern]);
  });

  ensureListAndAppend(
      'borders', 'border', st.originalBorderCount, st.borders.length, (i) {
    final b = st.borders[i];
    XmlElement side(String name, BorderSide s) => s.isVisible
        ? _el(name, {'style': s.style}, [colorEl('color', s.color)])
        : _el(name);
    return _el('border', null, [
      side('left', b.left),
      side('right', b.right),
      side('top', b.top),
      side('bottom', b.bottom),
      _el('diagonal'),
    ]);
  });

  ensureListAndAppend('cellXfs', 'xf', st.originalXfCount, st.cellXfs.length,
      (i) {
    final xf = st.cellXfs[i];
    final attrs = <String, String>{
      'numFmtId': '${xf.numFmtId}',
      'fontId': '${xf.fontId}',
      'fillId': '${xf.fillId}',
      'borderId': '${xf.borderId}',
      'xfId': '0',
      if (xf.numFmtId != 0) 'applyNumberFormat': '1',
      if (xf.fontId != 0) 'applyFont': '1',
      if (xf.fillId != 0) 'applyFill': '1',
      if (xf.borderId != 0) 'applyBorder': '1',
    };
    final a = xf.alignment;
    final children = <XmlNode>[];
    if (a != null) {
      attrs['applyAlignment'] = '1';
      final alignAttrs = <String, String>{
        if (a.horizontal != 'general') 'horizontal': a.horizontal,
        if (a.vertical != 'bottom') 'vertical': a.vertical,
        if (a.wrapText) 'wrapText': '1',
        if (a.textRotation != 0) 'textRotation': '${a.textRotation}',
        if (a.indent != 0) 'indent': '${a.indent}',
        if (a.shrinkToFit) 'shrinkToFit': '1',
      };
      children.add(_el('alignment', alignAttrs));
    }
    return _el('xf', attrs, children);
  });

  doc.archive.setFile('xl/styles.xml', xmlDoc.toUtf8Bytes());
}

// ---------------------------------------------------------------------------
// workbook.xml / calcChain
// ---------------------------------------------------------------------------

void _patchWorkbookCalcPr(XlsxDocument doc) {
  const path = 'xl/workbook.xml';
  final xmlDoc = archive_readDoc(doc, path);
  final root = xmlDoc.rootElement;
  var calcIdx = _childIndex(root, 'calcPr');
  XmlElement calcEl;
  if (calcIdx < 0) {
    calcEl = _el('calcPr');
    root.children.add(calcEl);
    calcEl.parent = root;
  } else {
    calcEl = root.children[calcIdx] as XmlElement;
  }
  _setAttr(calcEl, 'fullCalcOnLoad', '1');
  doc.archive.setFile(path, xmlDoc.toUtf8Bytes());
}

void _removeCalcChain(XlsxDocument doc) {
  if (!doc.archive.removeFile('xl/calcChain.xml')) return;

  // Remove o Override em [Content_Types].xml.
  const ctPath = '[Content_Types].xml';
  final ct = archive_readDoc(doc, ctPath);
  ct.rootElement.children.removeWhere((n) =>
      n is XmlElement &&
      n.qname == 'Override' &&
      (n.getAttribute('PartName') ?? '') == '/xl/calcChain.xml');
  doc.archive.setFile(ctPath, ct.toUtf8Bytes());

  // Remove a relationship do workbook.
  const relsPath = 'xl/_rels/workbook.xml.rels';
  if (doc.archive.findEntry(relsPath) != null) {
    final rels = archive_readDoc(doc, relsPath);
    rels.rootElement.children.removeWhere((n) =>
        n is XmlElement &&
        n.qname == 'Relationship' &&
        (n.getAttribute('Target') ?? '').contains('calcChain.xml'));
    doc.archive.setFile(relsPath, rels.toUtf8Bytes());
  }
}
