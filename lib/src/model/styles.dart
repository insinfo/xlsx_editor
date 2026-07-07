/// Modelo de estilos OOXML (styles.xml + theme1.xml), espelhando as tabelas
/// normalizadas do formato: fonts[], fills[], borders[], numFmts{}, cellXfs[].
library;

import 'dart:math' as math;

/// Cor OOXML: uma de rgb (ARGB hex), indexed, theme(+tint) ou auto.
class XlsxColor {
  final String? rgb; // 'FFRRGGBB' ou 'RRGGBB'
  final int? indexed;
  final int? theme;
  final double tint;
  final bool auto;

  const XlsxColor.rgbHex(this.rgb)
      : indexed = null,
        theme = null,
        tint = 0,
        auto = false;
  const XlsxColor.indexedColor(this.indexed)
      : rgb = null,
        theme = null,
        tint = 0,
        auto = false;
  const XlsxColor.themeColor(this.theme, [this.tint = 0])
      : rgb = null,
        indexed = null,
        auto = false;
  const XlsxColor.autoColor()
      : rgb = null,
        indexed = null,
        theme = null,
        tint = 0,
        auto = true;

  /// Resolve para CSS '#RRGGBB' usando o tema; [fallback] para auto.
  String css(Theme theme, {String fallback = '#000000'}) {
    final rgbHex = rgb;
    if (rgbHex != null) {
      final hex = rgbHex.length == 8 ? rgbHex.substring(2) : rgbHex;
      return '#$hex';
    }
    final idx = indexed;
    if (idx != null) return _indexedPalette[idx] ?? fallback;
    final th = this.theme;
    if (th != null) return _applyTint(theme.colorFor(th), tint);
    return fallback;
  }

  static String _applyTint(String cssHex, double tint) {
    if (tint == 0) return cssHex;
    var r = int.parse(cssHex.substring(1, 3), radix: 16);
    var g = int.parse(cssHex.substring(3, 5), radix: 16);
    var b = int.parse(cssHex.substring(5, 7), radix: 16);
    // Tint OOXML: aproximação via HSL (lum' = lum*(1+tint) p/ tint<0,
    // lum' = lum*(1-tint)+tint p/ tint>0), aplicada por canal (aprox. usual).
    int adjust(int c) {
      final v = tint < 0 ? c * (1 + tint) : c * (1 - tint) + 255 * tint;
      return math.max(0, math.min(255, v.round()));
    }

    r = adjust(r);
    g = adjust(g);
    b = adjust(b);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
}

/// Paleta indexed legada (subconjunto padrão do Excel).
const Map<int, String> _indexedPalette = {
  0: '#000000', 1: '#FFFFFF', 2: '#FF0000', 3: '#00FF00',
  4: '#0000FF', 5: '#FFFF00', 6: '#FF00FF', 7: '#00FFFF',
  8: '#000000', 9: '#FFFFFF', 10: '#FF0000', 11: '#00FF00',
  12: '#0000FF', 13: '#FFFF00', 14: '#FF00FF', 15: '#00FFFF',
  16: '#800000', 17: '#008000', 18: '#000080', 19: '#808000',
  20: '#800080', 21: '#008080', 22: '#C0C0C0', 23: '#808080',
  24: '#9999FF', 25: '#993366', 26: '#FFFFCC', 27: '#CCFFFF',
  28: '#660066', 29: '#FF8080', 30: '#0066CC', 31: '#CCCCFF',
  32: '#000080', 33: '#FF00FF', 34: '#FFFF00', 35: '#00FFFF',
  36: '#800080', 37: '#800000', 38: '#008080', 39: '#0000FF',
  40: '#00CCFF', 41: '#CCFFFF', 42: '#CCFFCC', 43: '#FFFF99',
  44: '#99CCFF', 45: '#FF99CC', 46: '#CC99FF', 47: '#FFCC99',
  48: '#3366FF', 49: '#33CCCC', 50: '#99CC00', 51: '#FFCC00',
  52: '#FF9900', 53: '#FF6600', 54: '#666699', 55: '#969696',
  56: '#003366', 57: '#339966', 58: '#003300', 59: '#333300',
  60: '#993300', 61: '#993366', 62: '#333399', 63: '#333333',
  64: '#000000', // system foreground
  65: '#FFFFFF', // system background
};

/// Tema (a:clrScheme). Índices já na ordem de referência do SpreadsheetML:
/// 0=lt1, 1=dk1, 2=lt2, 3=dk2, 4..9=accent1..6, 10=hlink, 11=folHlink.
class Theme {
  /// Cores CSS '#RRGGBB' na ordem do clrScheme (dk1,lt1,dk2,lt2,accent1..6,...).
  final List<String> clrScheme;

  const Theme(this.clrScheme);

  factory Theme.fallback() => const Theme([
        '#000000', '#FFFFFF', '#44546A', '#E7E6E6', // dk1 lt1 dk2 lt2
        '#4472C4', '#ED7D31', '#A5A5A5', '#FFC000', // accent1..4
        '#5B9BD5', '#70AD47', '#0563C1', '#954F72', // accent5..6 hlink folHlink
      ]);

  /// Excel troca os slots 0↔1 (dk1/lt1) e 2↔3 (dk2/lt2) ao indexar.
  String colorFor(int themeIndex) {
    var i = themeIndex;
    if (i == 0) {
      i = 1;
    } else if (i == 1) {
      i = 0;
    } else if (i == 2) {
      i = 3;
    } else if (i == 3) {
      i = 2;
    }
    if (i < 0 || i >= clrScheme.length) return '#000000';
    return clrScheme[i];
  }
}

class XlsxFont {
  final String name;
  final double size; // pontos
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final XlsxColor color;

  const XlsxFont({
    this.name = 'Calibri',
    this.size = 11,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color = const XlsxColor.autoColor(),
  });

  XlsxFont copyWith({
    String? name,
    double? size,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    XlsxColor? color,
  }) =>
      XlsxFont(
        name: name ?? this.name,
        size: size ?? this.size,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
        color: color ?? this.color,
      );
}

class XlsxFill {
  final String patternType; // none | solid | gray125 | ...
  final XlsxColor? fgColor;
  final XlsxColor? bgColor;

  const XlsxFill({this.patternType = 'none', this.fgColor, this.bgColor});

  bool get isVisible => patternType != 'none';
}

class BorderSide {
  final String style; // none|thin|medium|thick|hair|dotted|dashed|double|...
  final XlsxColor color;

  const BorderSide(
      {this.style = 'none', this.color = const XlsxColor.autoColor()});

  bool get isVisible => style != 'none';
}

class XlsxBorder {
  final BorderSide left, right, top, bottom;

  const XlsxBorder({
    this.left = const BorderSide(),
    this.right = const BorderSide(),
    this.top = const BorderSide(),
    this.bottom = const BorderSide(),
  });
}

class XlsxAlignment {
  final String horizontal; // general|left|center|right|fill|justify|...
  final String vertical; // top|center|bottom|justify|distributed
  final bool wrapText;
  final int textRotation;
  final int indent;
  final bool shrinkToFit;

  const XlsxAlignment({
    this.horizontal = 'general',
    this.vertical = 'bottom',
    this.wrapText = false,
    this.textRotation = 0,
    this.indent = 0,
    this.shrinkToFit = false,
  });
}

/// Registro <xf> de cellXfs.
class CellXf {
  final int numFmtId;
  final int fontId;
  final int fillId;
  final int borderId;
  final XlsxAlignment? alignment;

  const CellXf({
    this.numFmtId = 0,
    this.fontId = 0,
    this.fillId = 0,
    this.borderId = 0,
    this.alignment,
  });
}

/// Tabelas de estilo do workbook (espelho de styles.xml).
class StyleTable {
  final List<XlsxFont> fonts;
  final List<XlsxFill> fills;
  final List<XlsxBorder> borders;
  final List<CellXf> cellXfs;
  final Map<int, String> numFmts; // id -> formatCode customizado

  StyleTable({
    List<XlsxFont>? fonts,
    List<XlsxFill>? fills,
    List<XlsxBorder>? borders,
    List<CellXf>? cellXfs,
    Map<int, String>? numFmts,
  })  : fonts = fonts ?? [const XlsxFont()],
        fills = fills ?? [const XlsxFill()],
        borders = borders ?? [const XlsxBorder()],
        cellXfs = cellXfs ?? [const CellXf()],
        numFmts = numFmts ?? {};

  /// Marca quantos registros vieram do arquivo (novos são gravados ao salvar).
  int originalFontCount = 0;
  int originalFillCount = 0;
  int originalBorderCount = 0;
  int originalXfCount = 0;

  CellXf xfAt(int index) =>
      index >= 0 && index < cellXfs.length ? cellXfs[index] : cellXfs[0];

  XlsxFont fontOf(CellXf xf) =>
      xf.fontId >= 0 && xf.fontId < fonts.length ? fonts[xf.fontId] : fonts[0];

  XlsxFill fillOf(CellXf xf) =>
      xf.fillId >= 0 && xf.fillId < fills.length ? fills[xf.fillId] : fills[0];

  XlsxBorder borderOf(CellXf xf) => xf.borderId >= 0 &&
          xf.borderId < borders.length
      ? borders[xf.borderId]
      : borders[0];

  /// formatCode efetivo do xf (customizado ou builtin id).
  String? numFmtCodeOf(CellXf xf) => numFmts[xf.numFmtId];

  int _indexOfOrAdd<T>(List<T> list, T item, bool Function(T, T) eq) {
    for (var i = 0; i < list.length; i++) {
      if (eq(list[i], item)) return i;
    }
    list.add(item);
    return list.length - 1;
  }

  /// Deriva um novo xf a partir de [base] com campos trocados; deduplica.
  int deriveXf(
    int baseIndex, {
    XlsxFont? font,
    XlsxFill? fill,
    XlsxBorder? border,
    int? numFmtId,
    XlsxAlignment? alignment,
  }) {
    final base = xfAt(baseIndex);
    final fontId = font == null
        ? base.fontId
        : _indexOfOrAdd(fonts, font, _fontEquals);
    final fillId = fill == null
        ? base.fillId
        : _indexOfOrAdd(fills, fill, _fillEquals);
    final borderId = border == null
        ? base.borderId
        : _indexOfOrAdd(borders, border, _borderEquals);
    final xf = CellXf(
      numFmtId: numFmtId ?? base.numFmtId,
      fontId: fontId,
      fillId: fillId,
      borderId: borderId,
      alignment: alignment ?? base.alignment,
    );
    for (var i = 0; i < cellXfs.length; i++) {
      if (_xfEquals(cellXfs[i], xf)) return i;
    }
    cellXfs.add(xf);
    return cellXfs.length - 1;
  }

  /// Registra formatCode custom e devolve o id (>=164).
  int ensureNumFmt(String code) {
    for (final e in numFmts.entries) {
      if (e.value == code) return e.key;
    }
    var id = 164;
    while (numFmts.containsKey(id)) {
      id++;
    }
    numFmts[id] = code;
    return id;
  }

  static bool _colorEquals(XlsxColor a, XlsxColor b) =>
      a.rgb == b.rgb &&
      a.indexed == b.indexed &&
      a.theme == b.theme &&
      a.tint == b.tint &&
      a.auto == b.auto;

  static bool _fontEquals(XlsxFont a, XlsxFont b) =>
      a.name == b.name &&
      a.size == b.size &&
      a.bold == b.bold &&
      a.italic == b.italic &&
      a.underline == b.underline &&
      a.strike == b.strike &&
      _colorEquals(a.color, b.color);

  static bool _fillEquals(XlsxFill a, XlsxFill b) =>
      a.patternType == b.patternType &&
      _optColorEquals(a.fgColor, b.fgColor) &&
      _optColorEquals(a.bgColor, b.bgColor);

  static bool _optColorEquals(XlsxColor? a, XlsxColor? b) {
    if (a == null || b == null) return identical(a, b) || a == b;
    return _colorEquals(a, b);
  }

  static bool _sideEquals(BorderSide a, BorderSide b) =>
      a.style == b.style && _colorEquals(a.color, b.color);

  static bool _borderEquals(XlsxBorder a, XlsxBorder b) =>
      _sideEquals(a.left, b.left) &&
      _sideEquals(a.right, b.right) &&
      _sideEquals(a.top, b.top) &&
      _sideEquals(a.bottom, b.bottom);

  static bool _alignEquals(XlsxAlignment? a, XlsxAlignment? b) {
    if (a == null || b == null) return a == b;
    return a.horizontal == b.horizontal &&
        a.vertical == b.vertical &&
        a.wrapText == b.wrapText &&
        a.textRotation == b.textRotation &&
        a.indent == b.indent &&
        a.shrinkToFit == b.shrinkToFit;
  }

  static bool _xfEquals(CellXf a, CellXf b) =>
      a.numFmtId == b.numFmtId &&
      a.fontId == b.fontId &&
      a.fillId == b.fillId &&
      a.borderId == b.borderId &&
      _alignEquals(a.alignment, b.alignment);
}
