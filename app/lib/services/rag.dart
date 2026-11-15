import 'dart:math' as math;

import '../data/models.dart';

/// Recuperação lexical (BM25) sobre os trechos dos arquivos .md processados
/// (resumo das aulas + provas antigas com OCR). É a etapa "R" do RAG do copiloto:
/// roda no aparelho, sem rede, sobre a tabela `rag_chunks` do SQLite.
class Rag {
  final List<RagChunk> chunks;
  late final List<Map<String, int>> _tf;
  late final List<int> _len;
  late final Map<String, int> _df;
  late final double _avgLen;

  Rag(this.chunks) {
    _tf = [];
    _len = [];
    _df = {};
    for (final c in chunks) {
      // o título da seção pesa mais: entra duas vezes
      final toks = tokens('${c.secao} ${c.secao} ${c.texto}');
      final tf = <String, int>{};
      for (final t in toks) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      _tf.add(tf);
      _len.add(toks.length);
      for (final t in tf.keys) {
        _df[t] = (_df[t] ?? 0) + 1;
      }
    }
    _avgLen = _len.isEmpty ? 1 : _len.reduce((a, b) => a + b) / _len.length;
  }

  static const _stop = {
    'a', 'o', 'as', 'os', 'um', 'uma', 'uns', 'umas', 'de', 'do', 'da', 'dos',
    'das', 'em', 'no', 'na', 'nos', 'nas', 'por', 'para', 'pra', 'com', 'sem', 'sob',
    'sobre', 'entre', 'e', 'ou', 'mas', 'que', 'se', 'como', 'qual', 'quais', 'quando', 'onde',
    'porque', 'pq', 'ao', 'aos', 'pela', 'pelo', 'pelas', 'pelos', 'ser', 'sao', 'foi', 'tem',
    'ter', 'ha', 'isso', 'isto', 'esse', 'essa', 'este', 'esta', 'aquele', 'ele', 'ela', 'eles',
    'elas', 'eu', 'me', 'meu', 'minha', 'seu', 'sua', 'nao', 'sim', 'mais', 'menos', 'muito',
    'ja', 'tambem', 'so', 'ate', 'the', 'of', 'vai', 'pode', 'podem', 'tipo', 'explique', 'explica',
    'fale', 'diga', 'quero', 'saber', 'diferenca',
  };

  static const _acentos = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'ê': 'e', 'è': 'e', 'í': 'i', 'ì': 'i',
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ò': 'o', 'ú': 'u', 'ü': 'u', 'ù': 'u', 'ç': 'c', 'ñ': 'n',
  };

  static String semAcento(String s) {
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      b.write(_acentos[ch] ?? ch);
    }
    return b.toString();
  }

  /// Radical bem leve para português (plural e alguns sufixos), suficiente
  /// para casar "folículos/folicular/foliculares", "linfoma/linfomas".
  static String raiz(String t) {
    if (t.length <= 4 || RegExp(r'^\d').hasMatch(t)) return t;
    for (final suf in ['icos', 'icas', 'ares', 'oes', 'ais', 'eis', 'ico', 'ica', 'ar', 'es', 'os', 'as', 's', 'o', 'a', 'e']) {
      if (t.length - suf.length >= 4 && t.endsWith(suf)) return t.substring(0, t.length - suf.length);
    }
    return t;
  }

  static List<String> tokens(String s) {
    final limpo = semAcento(s).replaceAll(RegExp(r'[^a-z0-9+\-]+'), ' ');
    final out = <String>[];
    for (var t in limpo.split(' ')) {
      t = t.replaceAll(RegExp(r'^-+|-+$'), '');
      if (t.isEmpty) continue;
      // "bcl-2" -> bcl2 ; "cd20+" -> cd20
      t = t.replaceAll('-', '').replaceAll('+', '');
      if (t.length < 2 || _stop.contains(t)) continue;
      out.add(raiz(t));
    }
    return out;
  }

  /// Devolve os [k] trechos mais relevantes. [reforco] (ex.: título do capítulo
  /// aberto na tela) entra com peso menor, para puxar o contexto certo quando a
  /// pergunta é vaga ("explica isso de outro jeito").
  List<RagChunk> buscar(String consulta, {String reforco = '', int k = 7}) {
    final q = <String, double>{};
    for (final t in tokens(consulta)) {
      q[t] = (q[t] ?? 0) + 1.0;
    }
    for (final t in tokens(reforco)) {
      q[t] = (q[t] ?? 0) + 0.35;
    }
    if (q.isEmpty || chunks.isEmpty) return const [];
    const k1 = 1.4, b = 0.72;
    final n = chunks.length;
    final scores = <(int, double)>[];
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      final tf = _tf[i];
      q.forEach((t, peso) {
        final f = tf[t];
        if (f == null) return;
        final df = _df[t] ?? 0;
        final idf = math.log(1 + (n - df + 0.5) / (df + 0.5));
        s += peso * idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * _len[i] / _avgLen));
      });
      if (s > 0) scores.add((i, s));
    }
    scores.sort((a, b) => b.$2.compareTo(a.$2));
    if (scores.isEmpty) return const [];
    final corte = scores.first.$2 * 0.28;
    return [for (final s in scores.take(k)) if (s.$2 >= corte) chunks[s.$1]];
  }
}
