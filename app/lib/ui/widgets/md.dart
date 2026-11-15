import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// Texto com marcação leve: **negrito**, *itálico* e `código`.
List<InlineSpan> mdSpans(String s, TextStyle base, {Color? codeBg}) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`', dotAll: true);
  var i = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > i) spans.add(TextSpan(text: s.substring(i, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(
          children: mdSpans(m.group(1)!, base, codeBg: codeBg),
          style: const TextStyle(fontWeight: FontWeight.w700)));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
    } else {
      spans.add(TextSpan(
          text: m.group(3),
          style: TextStyle(fontFamily: 'monospace', fontSize: (base.fontSize ?? 14) * .93, backgroundColor: codeBg)));
    }
    i = m.end;
  }
  if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
  return spans;
}

class MdText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? align;
  const MdText(this.text, {super.key, this.style, this.align});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final base = TextStyle(fontSize: 15, height: 1.5, color: p.ink).merge(style);
    return Text.rich(TextSpan(children: mdSpans(text, base, codeBg: p.surfaceAlt), style: base), textAlign: align);
  }
}

/// Renderizador de Markdown em blocos (para as respostas do copiloto):
/// títulos, listas, tabelas, citações, código e parágrafos. Tolerante a texto
/// incompleto, porque é usado enquanto a resposta ainda está chegando.
class MdView extends StatelessWidget {
  final String data;
  final double fontSize;
  const MdView(this.data, {super.key, this.fontSize = 14.5});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final base = TextStyle(fontSize: fontSize, height: 1.5, color: p.ink);
    final out = <Widget>[];
    final linhas = data.replaceAll('\r', '').split('\n');
    final par = <String>[];

    void fecharPar() {
      if (par.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: mdSpans(par.join('\n'), base, codeBg: p.surfaceAlt), style: base)),
      ));
      par.clear();
    }

    var i = 0;
    while (i < linhas.length) {
      final l = linhas[i];
      final t = l.trim();
      if (t.isEmpty) {
        fecharPar();
        i++;
        continue;
      }
      // bloco de código
      if (t.startsWith('```')) {
        fecharPar();
        final cod = <String>[];
        i++;
        while (i < linhas.length && !linhas[i].trim().startsWith('```')) {
          cod.add(linhas[i]);
          i++;
        }
        i++;
        out.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10)),
          child: Text(cod.join('\n'), style: TextStyle(fontFamily: 'monospace', fontSize: fontSize - 1.5, color: p.ink)),
        ));
        continue;
      }
      // título
      final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t);
      if (h != null) {
        fecharPar();
        final nivel = h.group(1)!.length;
        final st = base.copyWith(
            fontSize: fontSize + (nivel <= 1 ? 4 : nivel == 2 ? 2.5 : 1), fontWeight: FontWeight.w700, height: 1.3);
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : 6, bottom: 6),
          child: Text.rich(TextSpan(children: mdSpans(h.group(2)!, st), style: st)),
        ));
        i++;
        continue;
      }
      // linha horizontal
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(t)) {
        fecharPar();
        out.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: p.line)));
        i++;
        continue;
      }
      // tabela
      if (t.startsWith('|')) {
        fecharPar();
        final rows = <List<String>>[];
        while (i < linhas.length && linhas[i].trim().startsWith('|')) {
          var r = linhas[i].trim();
          if (r.length > 1 && r.endsWith('|')) r = r.substring(0, r.length - 1);
          final cels = (r.startsWith('|') ? r.substring(1) : r).split('|').map((c) => c.trim()).toList();
          final sep = cels.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c) || c.isEmpty);
          if (!sep) rows.add(cels);
          i++;
        }
        if (rows.isNotEmpty) out.add(_tabela(p, rows, base));
        continue;
      }
      // citação
      if (t.startsWith('>')) {
        fecharPar();
        final q = <String>[];
        while (i < linhas.length && linhas[i].trim().startsWith('>')) {
          q.add(linhas[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        final st = base.copyWith(color: p.inkSoft);
        out.add(Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: p.line, width: 3))),
          child: Text.rich(TextSpan(children: mdSpans(q.join('\n'), st), style: st)),
        ));
        continue;
      }
      // item de lista
      final li = RegExp(r'^(\s*)([-*•]|\d+[.)])\s+(.*)$').firstMatch(l);
      if (li != null) {
        fecharPar();
        final nivel = (li.group(1)!.replaceAll('\t', '  ').length / 2).floor().clamp(0, 3);
        final marcador = li.group(2)!;
        final num = RegExp(r'\d').hasMatch(marcador);
        final corpo = StringBuffer(li.group(3)!);
        i++;
        // continuação do item (linhas recuadas que não são novo item)
        while (i < linhas.length &&
            linhas[i].trim().isNotEmpty &&
            linhas[i].startsWith('  ') &&
            !RegExp(r'^\s*([-*•]|\d+[.)])\s+').hasMatch(linhas[i])) {
          corpo.write(' ${linhas[i].trim()}');
          i++;
        }
        out.add(Padding(
          padding: EdgeInsets.only(left: 2.0 + nivel * 16, bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: num ? 24 : 16,
              child: Text(num ? marcador.replaceAll(')', '.') : '•',
                  style: base.copyWith(color: p.inkSoft, fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text.rich(TextSpan(children: mdSpans('$corpo', base, codeBg: p.surfaceAlt), style: base))),
          ]),
        ));
        continue;
      }
      par.add(t);
      i++;
    }
    fecharPar();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: out);
  }

  Widget _tabela(Pal p, List<List<String>> rows, TextStyle base) {
    final n = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final st = base.copyWith(fontSize: fontSize - 1.5, height: 1.35);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border.all(color: p.line), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: n <= 2 ? const IntrinsicColumnWidth(flex: 1) : const IntrinsicColumnWidth(),
          border: TableBorder(horizontalInside: BorderSide(color: p.line), verticalInside: BorderSide(color: p.line)),
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(color: r == 0 ? p.surfaceAlt : p.surface),
                children: [
                  for (var c = 0; c < n; c++)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                        child: Text.rich(TextSpan(
                          children: mdSpans(c < rows[r].length ? rows[r][c] : '', st),
                          style: r == 0 ? st.copyWith(fontWeight: FontWeight.w700) : st,
                        )),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
