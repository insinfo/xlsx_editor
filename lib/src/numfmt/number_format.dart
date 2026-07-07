/// Motor de formatação numérica ECMA-376 (formatCode de xlsx) em Dart puro.
///
/// Renderização fixa em pt-BR: separador decimal `,` e de milhar `.`
/// (o formatCode em si usa convenção US: `.` decimal e `,` agrupamento).
///
/// Decisões documentadas:
/// - Arredondamento: metade para longe do zero ("half away from zero"),
///   aplicado sobre a representação decimal em string do valor (evita erro
///   binário: `1.005` com `0.00` -> `1,01`).
/// - Datas: sistema 1900 COM o bug do 29/02/1900 (serial 60); dia 0 é
///   tratado como 30/12/1899 (época efetiva para seriais >= 61).
/// - Frações (`?/?`): fora de escopo; builtins 12/13 renderizam como General.
/// - `General` não usa notação científica (simplificação); limita a ~11
///   dígitos significativos.
/// - `0.##` com valor inteiro emite o separador decimal (`1,`), como o Excel.
library;

/// Resultado de uma formatação: texto pronto + cor declarada na seção usada.
class FormattedResult {
  final String text;

  /// Cor declarada na seção usada, ex.: "FF0000" para [Red]; null se nenhuma.
  final String? colorArgbHex; // sem '#', formato AARRGGBB ou RRGGBB

  /// Posição em [text] onde havia um preenchimento `*x` (formatos contábeis:
  /// "R$" ancorado à esquerda, número à direita). null se não há `*`.
  final int? splitIndex;

  const FormattedResult(this.text, [this.colorArgbHex, this.splitIndex]);

  @override
  String toString() => 'FormattedResult($text, $colorArgbHex, $splitIndex)';
}

/// Formato numérico ECMA-376 compilado (imutável, cacheado).
class NumberFormat {
  /// Código de formato original.
  final String code;

  final List<_Section> _sections;

  /// True se o código representa data/hora (tokens y m d h s fora de
  /// literais; inclui decorrido `[h]` `[mm]` `[ss]`).
  final bool isDateTime;

  NumberFormat._(this.code, this._sections, this.isDateTime);

  static final Map<String, NumberFormat> _cache = {};

  /// Compila um formatCode ECMA-376. Cacheia internamente.
  factory NumberFormat.compile(String formatCode) =>
      _cache.putIfAbsent(formatCode, () => _compile(formatCode));

  /// Retorna o formato builtin para o id (0..49) ou General se desconhecido.
  factory NumberFormat.builtin(int numFmtId) =>
      NumberFormat.compile(_builtinCodes[numFmtId] ?? 'General');

  static NumberFormat _compile(String formatCode) {
    final parts = _splitSections(formatCode);
    final sections = <_Section>[];
    for (var i = 0; i < parts.length && i < 4; i++) {
      sections.add(_parseSection(parts[i]));
    }
    final isDate = sections.any((s) => s.isDate);
    return NumberFormat._(formatCode, sections, isDate);
  }

  /// value: num, String, bool ou null (célula vazia -> texto vazio).
  FormattedResult format(Object? value) {
    if (value == null) return const FormattedResult('');
    if (value is bool) return _formatText(value ? 'VERDADEIRO' : 'FALSO');
    if (value is num) return _formatNumber(value);
    return _formatText(value.toString());
  }

  // ---------------------------------------------------------------- números

  FormattedResult _formatNumber(num v) {
    _Section sec;
    var autoSign = false; // prefixa '-' quando a seção não traz o sinal
    num rv = v;
    if (_sections.any((s) => s.cond != null)) {
      // Seções condicionais: primeira condição satisfeita; senão a primeira
      // sem condição; senão a última. Sinal automático para negativos.
      sec = _sections.firstWhere(
        (s) => s.cond != null && s.cond!.matches(v),
        orElse: () => _sections.firstWhere(
          (s) => s.cond == null,
          orElse: () => _sections.last,
        ),
      );
      autoSign = v < 0;
      rv = v.abs();
    } else if (_sections.length == 1) {
      sec = _sections[0];
      autoSign = v < 0;
      rv = v.abs();
    } else if (v > 0) {
      sec = _sections[0];
    } else if (v < 0) {
      // Seção negativa usa o valor absoluto (sinal vem do formato).
      sec = _sections[1];
      rv = v.abs();
    } else {
      sec = _sections.length >= 3 ? _sections[2] : _sections[0];
    }
    var (out, split) = _renderTokens(sec, number: rv);
    if (autoSign && !sec.isDate) {
      out = '-$out';
      if (split != null) split += 1;
    }
    return FormattedResult(out, sec.colorHex, split);
  }

  // ----------------------------------------------------------------- texto

  FormattedResult _formatText(String s) {
    _Section? sec;
    if (_sections.length == 4) {
      sec = _sections[3];
    } else {
      for (final cand in _sections) {
        if (cand.hasText) {
          sec = cand;
          break;
        }
      }
    }
    if (sec == null) return FormattedResult(s);
    final (out, split) = _renderTokens(sec, text: s);
    return FormattedResult(out, sec.colorHex, split);
  }

  // ------------------------------------------------------------ renderização

  /// Renderiza os tokens; retorna o texto e a posição do primeiro `*` (fill).
  (String, int?) _renderTokens(_Section sec, {num? number, String? text}) {
    final sb = StringBuffer();
    int? split;
    _DateParts? dp;
    if (sec.isDate && number != null) dp = _dateParts(number, sec);
    for (final t in sec.toks) {
      if (t is _LitTok) {
        sb.write(t.text);
      } else if (t is _SpaceTok) {
        sb.write(' '); // `_x` vira um espaço
      } else if (t is _FillTok) {
        split ??= sb.length; // `*x`: divisão esquerda/direita
      } else if (t is _TextTok) {
        sb.write(text ?? (number != null ? _general(number) : ''));
      } else if (t is _GeneralTok) {
        sb.write(number != null ? _general(number) : (text ?? ''));
      } else if (t is _NumTok) {
        if (number != null) {
          sb.write(_renderNumber(t.spec, number, sec.percents));
        }
      } else if (t is _DateTok) {
        if (dp != null) sb.write(_renderDateTok(t, dp, sec));
      } else if (t is _ElapsedTok) {
        if (dp != null) sb.write(_renderElapsed(t, dp, sec));
      } else if (t is _AmPmTok) {
        if (dp != null) sb.write(dp.h < 12 ? 'AM' : 'PM');
      } else if (t is _SubSecTok) {
        if (dp != null) {
          final ms3 = dp.ms.toString().padLeft(3, '0');
          sb.write(',');
          sb.write(ms3.padRight(t.digits, '0').substring(0, t.digits));
        }
      }
    }
    return (sb.toString(), split);
  }

  // ------------------------------------------------------- número decimal

  String _renderNumber(_NumSpec sp, num v, int percents) {
    // Escala por string: % -> +2 casas por ocorrência; ',' final -> -3.
    final shift = percents * 2 - sp.scale * 3;
    final dec = _decompose(v, shift);
    if (sp.hasExp) return _renderSci(sp, dec);
    final r = _roundAt(dec.ip, dec.fp, sp.fracPh.length);
    final sb = StringBuffer(_mapInt(sp.intPh, r.$1, sp.grouping));
    if (sp.hasPoint) {
      sb.write(',');
      sb.write(_mapFrac(sp.fracPh, r.$2));
    }
    return sb.toString();
  }

  /// Notação científica `E+00`/`E-00`; com N placeholders inteiros o expoente
  /// é múltiplo de N (engenharia, ex.: `##0.0E+0`).
  String _renderSci(_NumSpec sp, _Dec dec) {
    final p = sp.intPh.isEmpty ? 1 : sp.intPh.length;
    final all = '${dec.ip}${dec.fp}';
    var first = -1;
    for (var i = 0; i < all.length; i++) {
      if (all.codeUnitAt(i) != 0x30) {
        first = i;
        break;
      }
    }
    var e = 0;
    var mip = '';
    var mfp = ''.padRight(sp.fracPh.length, '0');
    if (first >= 0) {
      var k = dec.ip.length - first; // valor = 0.sig... * 10^k
      var sig = all.substring(first);
      while (true) {
        e = _floorDiv(k - 1, p) * p;
        final g = k - e; // dígitos inteiros da mantissa (1..p)
        final mi = sig.length >= g ? sig.substring(0, g) : sig.padRight(g, '0');
        final mf = sig.length > g ? sig.substring(g) : '';
        final r = _roundAt(mi, mf, sp.fracPh.length);
        if (r.$1.length > g) {
          // Arredondamento estourou (ex.: 9.99 -> 10.0): renormaliza.
          k += 1;
          sig = '1';
          continue;
        }
        mip = r.$1;
        mfp = r.$2;
        break;
      }
    }
    final sb = StringBuffer(_mapInt(sp.intPh, mip, sp.grouping));
    if (sp.hasPoint) {
      sb.write(',');
      sb.write(_mapFrac(sp.fracPh, mfp));
    }
    sb.write('E');
    sb.write(e < 0 ? '-' : (sp.expPlus ? '+' : ''));
    sb.write(e.abs().toString().padLeft(sp.expDigits, '0'));
    return sb.toString();
  }

  /// Mapeia dígitos inteiros nos placeholders, com agrupamento pt-BR (`.`).
  /// `digits` sem zeros à esquerda ('' quando a parte inteira é zero — assim
  /// `#`/`?` não mostram o zero, como no Excel).
  String _mapInt(List<String> ph, String digits, bool grouping) {
    final n = ph.length;
    final width = digits.length > n ? digits.length : n;
    final rev = <String>[]; // montado da direita para a esquerda
    for (var i = 0; i < width; i++) {
      String? ch;
      if (i < digits.length) {
        ch = digits[digits.length - 1 - i];
      } else {
        final p = ph[n - 1 - i];
        ch = p == '0' ? '0' : (p == '?' ? ' ' : null); // '#' -> nada
      }
      if (ch == null) continue;
      if (grouping && i > 0 && i % 3 == 0 && ch != ' ') rev.add('.');
      rev.add(ch);
    }
    return rev.reversed.join();
  }

  /// Mapeia dígitos fracionários (já com o tamanho dos placeholders):
  /// zeros finais insignificantes: `#` some, `?` vira espaço.
  String _mapFrac(List<String> ph, String frac) {
    var last = -1;
    for (var i = 0; i < ph.length; i++) {
      if (frac[i] != '0' || ph[i] == '0') last = i;
    }
    final sb = StringBuffer();
    for (var i = 0; i < ph.length; i++) {
      if (i <= last) {
        sb.write(frac[i]);
      } else if (ph[i] == '?') {
        sb.write(' ');
      }
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------- General

  /// `General`: inteiros sem decimais nem agrupamento; demais valores com até
  /// ~11 dígitos significativos, zeros finais removidos, decimal `,`.
  String _general(num v) {
    if (v is int) return v.toString();
    final d = v.toDouble();
    if (d.isNaN || d.isInfinite) return d.toString();
    if (d == d.roundToDouble() && d.abs() < 1e15) return d.toStringAsFixed(0);
    final dec = _decompose(d, 0);
    final intLen = dec.ip.isEmpty ? 1 : dec.ip.length;
    var decimals = 11 - intLen;
    if (decimals < 0) decimals = 0;
    final r = _roundAt(dec.ip, dec.fp, decimals);
    var fp = r.$2;
    var end = fp.length;
    while (end > 0 && fp.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    fp = fp.substring(0, end);
    final sign = dec.neg ? '-' : '';
    final ip = r.$1.isEmpty ? '0' : r.$1;
    return fp.isEmpty ? '$sign$ip' : '$sign$ip,$fp';
  }

  // ------------------------------------------------------------- data/hora

  static const int _dayMs = 86400000;

  _DateParts _dateParts(num serial, _Section sec) {
    var raw = (serial * _dayMs).round();
    // Excel trunca as unidades exibidas (12:34:56 com hh:mm -> 12:34); só o
    // ruído sub-segundo é arredondado ao segundo, exceto se `ss.0` é exibido.
    if (!sec.hasSubSec) raw = _floorDiv(raw + 500, 1000) * 1000;
    final days = _floorDiv(raw, _dayMs);
    final msOfDay = raw - days * _dayMs;
    int y, mo, d, wd;
    if (days == 60) {
      // Bug do Lotus: 29/02/1900 fictício (Excel diz que é quarta-feira).
      y = 1900;
      mo = 2;
      d = 29;
      wd = 3;
    } else {
      final base =
          days >= 61 ? DateTime.utc(1899, 12, 30) : DateTime.utc(1899, 12, 31);
      final dt = base.add(Duration(days: days));
      y = dt.year;
      mo = dt.month;
      d = dt.day;
      wd = dt.weekday % 7; // 0=domingo..6=sábado
    }
    return _DateParts(
      y: y,
      mo: mo,
      d: d,
      wd: wd,
      h: msOfDay ~/ 3600000,
      mi: (msOfDay ~/ 60000) % 60,
      s: (msOfDay ~/ 1000) % 60,
      ms: msOfDay % 1000,
      totalMs: raw,
    );
  }

  static const _monthsFull = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];
  static const _monthsAbbr = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  static const _weekFull = [
    'domingo',
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado',
  ];
  static const _weekAbbr = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];

  String _renderDateTok(_DateTok t, _DateParts dp, _Section sec) {
    switch (t.letter) {
      case 'y':
        return t.count >= 3
            ? dp.y.toString().padLeft(4, '0')
            : (dp.y % 100).toString().padLeft(2, '0');
      case 'm': // mês
        if (t.count >= 5) return _monthsFull[dp.mo - 1].substring(0, 1);
        if (t.count == 4) return _monthsFull[dp.mo - 1];
        if (t.count == 3) return _monthsAbbr[dp.mo - 1];
        return t.count == 2
            ? dp.mo.toString().padLeft(2, '0')
            : dp.mo.toString();
      case 'n': // minuto (m desambiguado)
        return t.count >= 2
            ? dp.mi.toString().padLeft(2, '0')
            : dp.mi.toString();
      case 'd':
        if (t.count >= 4) return _weekFull[dp.wd];
        if (t.count == 3) return _weekAbbr[dp.wd];
        return t.count == 2 ? dp.d.toString().padLeft(2, '0') : dp.d.toString();
      case 'h':
        var h = dp.h;
        if (sec.hasAmPm) {
          h = h % 12;
          if (h == 0) h = 12;
        }
        return t.count >= 2 ? h.toString().padLeft(2, '0') : h.toString();
      case 's':
        return t.count >= 2 ? dp.s.toString().padLeft(2, '0') : dp.s.toString();
    }
    return '';
  }

  /// Tempo decorrido `[h]` `[mm]` `[ss]` (remanescente conforme unidades
  /// maiores presentes na seção).
  String _renderElapsed(_ElapsedTok t, _DateParts dp, _Section sec) {
    int v;
    switch (t.unit) {
      case 'h':
        v = dp.totalMs ~/ 3600000;
        break;
      case 'm':
        v = dp.totalMs ~/ 60000;
        if (sec.hasHour) v %= 60;
        break;
      default: // 's'
        v = dp.totalMs ~/ 1000;
        if (sec.hasMinute) {
          v %= 60;
        } else if (sec.hasHour) {
          v %= 3600;
        }
    }
    return v.toString().padLeft(t.width, '0');
  }

  // --------------------------------------------------- decomposição decimal

  /// Converte num em dígitos decimais exatos (expande notação `e`), com o
  /// ponto decimal deslocado por [shift] casas (escala %/milhar sem erro
  /// binário). `ip` sem zeros à esquerda ('' se a parte inteira é zero).
  static _Dec _decompose(num v, int shift) {
    var s = v.toString();
    var neg = false;
    if (s.startsWith('-')) {
      neg = true;
      s = s.substring(1);
    }
    if (s == 'NaN' || s == 'Infinity') return _Dec(neg, '', '');
    var exp = 0;
    final ei = s.indexOf('e');
    if (ei >= 0) {
      exp = int.parse(s.substring(ei + 1));
      s = s.substring(0, ei);
    }
    String digits;
    int point;
    final pi = s.indexOf('.');
    if (pi >= 0) {
      digits = s.substring(0, pi) + s.substring(pi + 1);
      point = pi;
    } else {
      digits = s;
      point = s.length;
    }
    point += exp + shift;
    String ip, fp;
    if (point <= 0) {
      ip = '';
      fp = '0' * (-point) + digits;
    } else if (point >= digits.length) {
      ip = digits + '0' * (point - digits.length);
      fp = '';
    } else {
      ip = digits.substring(0, point);
      fp = digits.substring(point);
    }
    var start = 0;
    while (start < ip.length && ip.codeUnitAt(start) == 0x30) {
      start++;
    }
    return _Dec(neg, ip.substring(start), fp);
  }

  /// Arredonda (ip, fp) para [n] casas: metade para longe do zero, em string.
  /// Retorna (ip sem zeros à esquerda, fp com exatamente n dígitos).
  static (String, String) _roundAt(String ip, String fp, int n) {
    if (fp.length <= n) return (ip, fp.padRight(n, '0'));
    final keep = fp.substring(0, n);
    final up = fp.codeUnitAt(n) >= 0x35; // dígito >= '5'
    var all = ip + keep;
    if (up) {
      final chars = all.codeUnits.toList();
      var i = chars.length - 1;
      var carry = true;
      while (i >= 0 && carry) {
        if (chars[i] == 0x39) {
          chars[i] = 0x30;
        } else {
          chars[i]++;
          carry = false;
        }
        i--;
      }
      all = String.fromCharCodes(chars);
      if (carry) all = '1$all';
    }
    var nip = all.substring(0, all.length - n);
    final nfp = all.substring(all.length - n);
    var start = 0;
    while (start < nip.length && nip.codeUnitAt(start) == 0x30) {
      start++;
    }
    return (nip.substring(start), nfp);
  }

  static int _floorDiv(int a, int b) {
    final q = a ~/ b;
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
  }

  // ------------------------------------------------------------- compilação

  /// Divide o código em seções por `;` respeitando aspas, escapes e `[..]`.
  static List<String> _splitSections(String code) {
    final out = <String>[];
    final sb = StringBuffer();
    var i = 0;
    while (i < code.length) {
      final c = code[i];
      if (c == '"') {
        final j = code.indexOf('"', i + 1);
        if (j < 0) {
          sb.write(code.substring(i));
          i = code.length;
        } else {
          sb.write(code.substring(i, j + 1));
          i = j + 1;
        }
      } else if (c == r'\' && i + 1 < code.length) {
        sb.write(code.substring(i, i + 2));
        i += 2;
      } else if (c == '[') {
        final j = code.indexOf(']', i);
        if (j < 0) {
          sb.write(code.substring(i));
          i = code.length;
        } else {
          sb.write(code.substring(i, j + 1));
          i = j + 1;
        }
      } else if (c == ';') {
        out.add(sb.toString());
        sb.clear();
        i++;
      } else {
        sb.write(c);
        i++;
      }
    }
    out.add(sb.toString());
    return out;
  }

  static const Map<String, String> _colors = {
    'black': '000000',
    'blue': '0000FF',
    'cyan': '00FFFF',
    'green': '00FF00',
    'magenta': 'FF00FF',
    'red': 'FF0000',
    'white': 'FFFFFF',
    'yellow': 'FFFF00',
  };

  static final RegExp _condRe =
      RegExp(r'^(<=|>=|<>|[<>=])\s*(-?\d+(?:\.\d+)?)$');
  static final RegExp _colorNRe =
      RegExp(r'^color\s*\d+$', caseSensitive: false);
  static final RegExp _elapsedRe =
      RegExp(r'^([hms])\1*$', caseSensitive: false);

  static _Section _parseSection(String src) {
    final raws = <_Raw>[];
    String? colorHex;
    _Cond? cond;
    var percents = 0;

    var i = 0;
    while (i < src.length) {
      final c = src[i];
      if (c == '"') {
        final j = src.indexOf('"', i + 1);
        final end = j < 0 ? src.length : j;
        raws.add(_Raw.lit(src.substring(i + 1, end)));
        i = j < 0 ? src.length : j + 1;
      } else if (c == r'\') {
        if (i + 1 < src.length) raws.add(_Raw.lit(src[i + 1]));
        i += 2;
      } else if (c == '_') {
        raws.add(_Raw(_RK.space)); // `_x` -> espaço
        i += 2;
      } else if (c == '*') {
        raws.add(const _Raw(_RK.fill)); // `*x` -> marca ponto de divisão
        i += 2;
      } else if (c == '[') {
        final j = src.indexOf(']', i);
        final content = j < 0 ? src.substring(i + 1) : src.substring(i + 1, j);
        i = j < 0 ? src.length : j + 1;
        if (content.startsWith(r'$')) {
          // [$TEXT-hexlocale] -> emite TEXT literal (ex.: [$R$-416] -> R$).
          final cur = content.substring(1);
          final dash = cur.lastIndexOf('-');
          final txt = dash >= 0 ? cur.substring(0, dash) : cur;
          if (txt.isNotEmpty) raws.add(_Raw.lit(txt));
        } else if (_elapsedRe.hasMatch(content)) {
          raws.add(
            _Raw(_RK.elapsed,
                text: content[0].toLowerCase(), n: content.length),
          );
        } else if (_colors.containsKey(content.toLowerCase())) {
          colorHex = _colors[content.toLowerCase()];
        } else if (_colorNRe.hasMatch(content)) {
          // [Color n] -> cor indexada ignorada.
        } else {
          final m = _condRe.firstMatch(content);
          if (m != null) {
            cond = _Cond(m.group(1)!, double.parse(m.group(2)!));
          }
          // Demais tags ([$-416], [DBNum1]...) são ignoradas.
        }
      } else if (c == '@') {
        raws.add(_Raw(_RK.text));
        i++;
      } else if (c == '%') {
        raws.add(_Raw(_RK.percent));
        percents++;
        i++;
      } else if ((c == 'G' || c == 'g') &&
          i + 7 <= src.length &&
          src.substring(i, i + 7).toLowerCase() == 'general') {
        raws.add(_Raw(_RK.general));
        i += 7;
      } else if ('yYmMdDhHsS'.contains(c)) {
        final letter = c.toLowerCase();
        var j = i;
        while (j < src.length && src[j].toLowerCase() == letter) {
          j++;
        }
        raws.add(_Raw(_RK.dateRun, text: letter, n: j - i));
        i = j;
      } else if ((c == 'a' || c == 'A') &&
          i + 5 <= src.length &&
          src.substring(i, i + 5).toLowerCase() == 'am/pm') {
        raws.add(_Raw(_RK.ampm));
        i += 5;
      } else if ((c == 'a' || c == 'A') &&
          i + 3 <= src.length &&
          src.substring(i, i + 3).toLowerCase() == 'a/p') {
        raws.add(_Raw(_RK.ampm));
        i += 3;
      } else if (c == '0' || c == '#' || c == '?') {
        raws.add(_Raw(_RK.digit, text: c));
        i++;
      } else if (c == '.') {
        raws.add(_Raw(_RK.point));
        i++;
      } else if (c == ',') {
        raws.add(_Raw(_RK.comma));
        i++;
      } else if ((c == 'E' || c == 'e') &&
          i + 1 < src.length &&
          (src[i + 1] == '+' || src[i + 1] == '-')) {
        raws.add(_Raw(_RK.expMark, text: src[i + 1]));
        i += 2;
      } else {
        // Literais sem aspas: $ - + / ( ) : espaço e demais chars.
        raws.add(_Raw.lit(c));
        i++;
      }
    }

    final isDate = raws.any(
      (r) => r.k == _RK.dateRun || r.k == _RK.ampm || r.k == _RK.elapsed,
    );
    final toks = isDate ? _buildDateTokens(raws) : _buildNumberTokens(raws);

    var hasHour = false, hasMinute = false, hasAmPm = false, hasSubSec = false;
    for (final t in toks) {
      if (t is _DateTok) {
        if (t.letter == 'h') hasHour = true;
        if (t.letter == 'n') hasMinute = true;
      } else if (t is _ElapsedTok) {
        if (t.unit == 'h') hasHour = true;
        if (t.unit == 'm') hasMinute = true;
      } else if (t is _AmPmTok) {
        hasAmPm = true;
      } else if (t is _SubSecTok) {
        hasSubSec = true;
      }
    }

    return _Section(
      toks: toks,
      colorHex: colorHex,
      cond: cond,
      percents: percents,
      isDate: isDate,
      hasText: toks.any((t) => t is _TextTok),
      hasHour: hasHour,
      hasMinute: hasMinute,
      hasAmPm: hasAmPm,
      hasSubSec: hasSubSec,
    );
  }

  /// Seção de data: resolve `m` (mês vs minuto) e `ss.0` (subsegundos).
  static List<_Tok> _buildDateTokens(List<_Raw> raws) {
    final toks = <_Tok>[];
    var i = 0;
    while (i < raws.length) {
      final r = raws[i];
      switch (r.k) {
        case _RK.lit:
          toks.add(_LitTok(r.text));
          break;
        case _RK.space:
          toks.add(const _SpaceTok());
          break;
        case _RK.fill:
          toks.add(const _FillTok());
          break;
        case _RK.text:
          toks.add(const _TextTok());
          break;
        case _RK.percent:
          toks.add(const _LitTok('%'));
          break;
        case _RK.dateRun:
          toks.add(_DateTok(r.text, r.n));
          break;
        case _RK.ampm:
          toks.add(const _AmPmTok());
          break;
        case _RK.elapsed:
          toks.add(_ElapsedTok(
              r.text == 'h' ? 'h' : (r.text == 'm' ? 'm' : 's'), r.n));
          break;
        case _RK.point:
          // `.0` logo após segundos -> subsegundos; senão literal.
          var j = i + 1;
          var zeros = 0;
          while (j < raws.length &&
              raws[j].k == _RK.digit &&
              raws[j].text == '0') {
            zeros++;
            j++;
          }
          final prevIsSec = toks.isNotEmpty &&
              ((toks.last is _DateTok &&
                      (toks.last as _DateTok).letter == 's') ||
                  (toks.last is _ElapsedTok &&
                      (toks.last as _ElapsedTok).unit == 's'));
          if (zeros > 0 && prevIsSec) {
            toks.add(_SubSecTok(zeros));
            i = j - 1;
          } else {
            toks.add(const _LitTok('.'));
          }
          break;
        case _RK.comma:
          toks.add(const _LitTok(','));
          break;
        case _RK.digit:
        case _RK.expMark:
        case _RK.general:
          break; // sem significado em seção de data
      }
      i++;
    }
    // Desambiguação de m/mm: minuto se o token de data anterior for hora, ou
    // se o próximo token de data for segundos.
    _Tok? prevDate;
    for (var a = 0; a < toks.length; a++) {
      final t = toks[a];
      if (t is _DateTok && t.letter == 'm' && t.count <= 2) {
        var minute = false;
        if (prevDate is _DateTok && prevDate.letter == 'h') minute = true;
        if (prevDate is _ElapsedTok && prevDate.unit == 'h') minute = true;
        if (!minute) {
          for (var b = a + 1; b < toks.length; b++) {
            final nt = toks[b];
            if (nt is _DateTok) {
              minute = nt.letter == 's';
              break;
            }
            if (nt is _ElapsedTok) {
              minute = nt.unit == 's';
              break;
            }
            if (nt is _AmPmTok) break;
          }
        }
        if (minute) toks[a] = _DateTok('n', t.count);
      }
      if (t is _DateTok || t is _ElapsedTok) prevDate = toks[a];
    }
    return toks;
  }

  /// Seção numérica/texto: agrupa o primeiro bloco contíguo de
  /// dígitos/ponto/vírgulas em um único token de número.
  static List<_Tok> _buildNumberTokens(List<_Raw> raws) {
    final toks = <_Tok>[];
    var numDone = false;
    var i = 0;
    while (i < raws.length) {
      final r = raws[i];
      switch (r.k) {
        case _RK.lit:
          toks.add(_LitTok(r.text));
          i++;
          break;
        case _RK.space:
          toks.add(const _SpaceTok());
          i++;
          break;
        case _RK.fill:
          toks.add(const _FillTok());
          i++;
          break;
        case _RK.text:
          toks.add(const _TextTok());
          i++;
          break;
        case _RK.percent:
          toks.add(const _LitTok('%'));
          i++;
          break;
        case _RK.general:
          toks.add(const _GeneralTok());
          i++;
          break;
        case _RK.ampm:
        case _RK.dateRun:
        case _RK.elapsed:
          i++; // não ocorre (seção não é de data)
          break;
        case _RK.expMark:
          toks.add(_LitTok('E${r.text}'));
          i++;
          break;
        case _RK.digit:
        case _RK.point:
        case _RK.comma:
          var j = i;
          while (j < raws.length &&
              (raws[j].k == _RK.digit ||
                  raws[j].k == _RK.point ||
                  raws[j].k == _RK.comma)) {
            j++;
          }
          final run = raws.sublist(i, j);
          if (numDone || !run.any((x) => x.k == _RK.digit)) {
            // Clusters extras (frações/telefone fora de escopo) ou run sem
            // placeholder: vírgula/ponto viram literais.
            for (final x in run) {
              if (x.k == _RK.comma) toks.add(const _LitTok(','));
              if (x.k == _RK.point) toks.add(const _LitTok(','));
            }
            i = j;
            break;
          }
          // Expoente imediatamente após o cluster.
          var expPlus = false;
          var expDigits = 0;
          var hasExp = false;
          if (j < raws.length && raws[j].k == _RK.expMark) {
            var k2 = j + 1;
            var cnt = 0;
            while (k2 < raws.length && raws[k2].k == _RK.digit) {
              cnt++;
              k2++;
            }
            if (cnt > 0) {
              hasExp = true;
              expPlus = raws[j].text == '+';
              expDigits = cnt;
              j = k2;
            }
          }
          toks.add(_NumTok(_buildNumSpec(run, hasExp, expPlus, expDigits)));
          numDone = true;
          i = j;
          break;
      }
    }
    return toks;
  }

  static _NumSpec _buildNumSpec(
    List<_Raw> run,
    bool hasExp,
    bool expPlus,
    int expDigits,
  ) {
    final intPh = <String>[];
    final fracPh = <String>[];
    var hasPoint = false;
    var grouping = false;
    var scale = 0;
    // Índices do primeiro/último dígito antes do ponto: vírgula entre eles é
    // milhar; vírgula depois do último é escala (/1000); antes, ignorada.
    var firstIntDigit = -1;
    var lastIntDigit = -1;
    var pointIdx = run.length;
    for (var i = 0; i < run.length; i++) {
      if (run[i].k == _RK.point) {
        pointIdx = i;
        break;
      }
      if (run[i].k == _RK.digit) {
        firstIntDigit = firstIntDigit < 0 ? i : firstIntDigit;
        lastIntDigit = i;
      }
    }
    for (var i = 0; i < run.length; i++) {
      final r = run[i];
      if (r.k == _RK.digit) {
        if (hasPoint) {
          fracPh.add(r.text);
        } else {
          intPh.add(r.text);
        }
      } else if (r.k == _RK.point) {
        hasPoint = true;
      } else if (r.k == _RK.comma) {
        if (i < pointIdx && i > firstIntDigit && i < lastIntDigit) {
          grouping = true; // vírgula entre dígitos -> milhar
        } else if (lastIntDigit >= 0 && i > lastIntDigit) {
          scale++; // vírgula após os dígitos -> /1000
        }
      }
    }
    return _NumSpec(
      intPh: intPh,
      fracPh: fracPh,
      hasPoint: hasPoint,
      grouping: grouping,
      scale: scale,
      hasExp: hasExp,
      expPlus: expPlus,
      expDigits: expDigits,
    );
  }

  // Builtins ECMA-376 (moeda em R$ para 5..8 e 42/44; datas em pt-BR).
  static const Map<int, String> _builtinCodes = {
    0: 'General',
    1: '0',
    2: '0.00',
    3: '#,##0',
    4: '#,##0.00',
    5: r'"R$" #,##0;\-"R$" #,##0',
    6: r'"R$" #,##0;[Red]\-"R$" #,##0',
    7: r'"R$" #,##0.00;\-"R$" #,##0.00',
    8: r'"R$" #,##0.00;[Red]\-"R$" #,##0.00',
    9: '0%',
    10: '0.00%',
    11: '0.00E+00',
    12: 'General', // # ?/?  (frações fora de escopo)
    13: 'General', // # ??/??
    14: 'dd/mm/yyyy',
    15: 'd-mmm-yy',
    16: 'd-mmm',
    17: 'mmm-yy',
    18: 'h:mm AM/PM',
    19: 'h:mm:ss AM/PM',
    20: 'h:mm',
    21: 'h:mm:ss',
    22: 'dd/mm/yyyy hh:mm',
    37: '#,##0_);(#,##0)',
    38: '#,##0_);[Red](#,##0)',
    39: '#,##0.00_);(#,##0.00)',
    40: '#,##0.00_);[Red](#,##0.00)',
    41: r'_-* #,##0_-;\-* #,##0_-;_-* "-"_-;_-@_-',
    42: r'_-"R$" * #,##0_-;\-"R$" * #,##0_-;_-"R$" * "-"_-;_-@_-',
    43: r'_-* #,##0.00_-;\-* #,##0.00_-;_-* "-"??_-;_-@_-',
    44: r'_-"R$" * #,##0.00_-;\-"R$" * #,##0.00_-;_-"R$" * "-"??_-;_-@_-',
    45: 'mm:ss',
    46: '[h]:mm:ss',
    47: 'mm:ss.0',
    48: '##0.0E+0',
    49: '@',
  };
}

// ------------------------------------------------------------------ modelos

class _Dec {
  final bool neg;
  final String ip; // dígitos inteiros sem zeros à esquerda ('' se zero)
  final String fp; // dígitos fracionários
  const _Dec(this.neg, this.ip, this.fp);
}

class _Cond {
  final String op;
  final double value;
  const _Cond(this.op, this.value);

  bool matches(num v) {
    switch (op) {
      case '<':
        return v < value;
      case '<=':
        return v <= value;
      case '>':
        return v > value;
      case '>=':
        return v >= value;
      case '<>':
        return v != value;
      default: // '='
        return v == value;
    }
  }
}

class _NumSpec {
  final List<String> intPh; // placeholders '0' '#' '?' da parte inteira
  final List<String> fracPh; // idem, parte fracionária
  final bool hasPoint;
  final bool grouping; // milhar
  final int scale; // nº de vírgulas de escala (/1000 cada)
  final bool hasExp;
  final bool expPlus; // E+ mostra sinal positivo
  final int expDigits;
  const _NumSpec({
    required this.intPh,
    required this.fracPh,
    required this.hasPoint,
    required this.grouping,
    required this.scale,
    required this.hasExp,
    required this.expPlus,
    required this.expDigits,
  });
}

class _Section {
  final List<_Tok> toks;
  final String? colorHex;
  final _Cond? cond;
  final int percents;
  final bool isDate;
  final bool hasText;
  final bool hasHour;
  final bool hasMinute;
  final bool hasAmPm;
  final bool hasSubSec; // exibe `ss.0` (não arredonda ao segundo)
  const _Section({
    required this.toks,
    required this.colorHex,
    required this.cond,
    required this.percents,
    required this.isDate,
    required this.hasText,
    required this.hasHour,
    required this.hasMinute,
    required this.hasAmPm,
    required this.hasSubSec,
  });
}

class _DateParts {
  final int y, mo, d, wd, h, mi, s, ms;
  final int totalMs; // desde o dia 0 (p/ tempo decorrido)
  const _DateParts({
    required this.y,
    required this.mo,
    required this.d,
    required this.wd,
    required this.h,
    required this.mi,
    required this.s,
    required this.ms,
    required this.totalMs,
  });
}

// Tokens compilados.
abstract class _Tok {
  const _Tok();
}

class _LitTok extends _Tok {
  final String text;
  const _LitTok(this.text);
}

class _FillTok extends _Tok {
  const _FillTok();
}

class _SpaceTok extends _Tok {
  const _SpaceTok();
}

class _TextTok extends _Tok {
  const _TextTok();
}

class _GeneralTok extends _Tok {
  const _GeneralTok();
}

class _NumTok extends _Tok {
  final _NumSpec spec;
  const _NumTok(this.spec);
}

/// letter: y, m(mês), n(minuto), d, h, s.
class _DateTok extends _Tok {
  final String letter;
  final int count;
  const _DateTok(this.letter, this.count);
}

class _ElapsedTok extends _Tok {
  final String unit; // h, m, s
  final int width;
  const _ElapsedTok(this.unit, this.width);
}

class _AmPmTok extends _Tok {
  const _AmPmTok();
}

class _SubSecTok extends _Tok {
  final int digits;
  const _SubSecTok(this.digits);
}

// Tokens brutos do scanner.
enum _RK {
  lit,
  space,
  fill,
  text,
  general,
  percent,
  digit,
  point,
  comma,
  expMark,
  dateRun,
  ampm,
  elapsed,
}

class _Raw {
  final _RK k;
  final String text;
  final int n;
  const _Raw(this.k, {this.text = '', this.n = 0});
  const _Raw.lit(this.text)
      : k = _RK.lit,
        n = 0;
}
