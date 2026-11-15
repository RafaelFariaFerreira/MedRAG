import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../copilot/copilot_sheet.dart';
import '../widgets/common.dart';
import '../widgets/md.dart';

// =====================================================================================
// Utilidades
// =====================================================================================

String pct(double v) => '${(v * 100).round()}%';

String fmtPontos(num n) {
  final s = n == n.roundToDouble() ? '${n.toInt()}' : '$n'.replaceAll('.', ',');
  return '$s pt';
}

String nomeTipo(String t) => switch (t) {
  'multipla' => 'Objetiva',
  'vf' => 'V ou F',
  'discursiva' => 'Discursiva',
  'lacunas' => 'Completar',
  _ => t,
};

String tituloProva(Question q) => AppState.I.provaPorId[q.provaId]?.titulo ?? q.provaId;

const _acentos = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Normaliza para comparar respostas curtas: sem acentos, maiúsculas, espaços, hífens e pontos.
String normalizar(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_acentos[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[\s\-–—.]'), '');
}

/// Caso clínico: oferece roteiro de resposta.
bool ehCasoClinico(Question q) {
  final t = [q.enunciado, for (final s in q.subitens) '${s['pergunta'] ?? ''}'].join(' ').toLowerCase();
  return t.contains('discutir') || t.contains('diagnóstico');
}

String _subKey(Json s) => '${s['letra'] ?? ''}';

// =====================================================================================
// Estado de uma questão dentro de uma sessão (sobrevive à troca de página do PageView)
// =====================================================================================

class QuestaoCtrl extends ChangeNotifier {
  final Question q;
  QuestaoCtrl(this.q);

  String? escolha; // múltipla
  final Map<int, bool> marcas = {}; // V ou F
  final Map<String, bool> checks = {}; // discursiva: "<letra>#<i>"
  final Map<int, bool> lacunaOk = {}; // lacunas, depois de corrigir
  bool modeloVisivel = false;
  bool corrigida = false;
  double? nota;

  /// Muda quando a questão é reiniciada (força os campos a recarregar).
  int geracao = 0;

  /// O widget ativo registra aqui como gravar o que ainda está pendente de salvar.
  VoidCallback? flush;

  bool get mostraGabarito => corrigida || modeloVisivel;
  bool get respondida => nota != null;

  void mudou() => notifyListeners();

  bool _vivo = true;

  @override
  void dispose() {
    _vivo = false;
    super.dispose();
  }

  void registrar(double n, [Json? detalhe]) {
    nota = n;
    corrigida = true;
    AppState.I.registrarTentativa(q.id, n, detalhe);
    notifyListeners();
  }

  /// Subchaves de resposta escrita usadas por esta questão.
  List<String> get _subs => switch (q.tipo) {
    'discursiva' => q.subitens.isEmpty ? [''] : [for (final s in q.subitens) _subKey(s)],
    'lacunas' => [for (var i = 0; i < q.lacunas.length; i++) '$i'],
    _ => const [],
  };

  _Snapshot? _backup;

  /// Limpa o estado da questão (respostas e correção), mantendo as anotações. Pode ser desfeito.
  void tentarDeNovo() {
    flush?.call();
    final textos = {for (final s in _subs) s: AppState.I.resposta(q.id, s)};
    _backup = _Snapshot(
      escolha,
      Map.of(marcas),
      Map.of(checks),
      Map.of(lacunaOk),
      modeloVisivel,
      corrigida,
      nota,
      textos,
    );
    for (final s in _subs) {
      if (textos[s]!.isNotEmpty) AppState.I.salvarResposta(q.id, s, '');
    }
    escolha = null;
    marcas.clear();
    checks.clear();
    lacunaOk.clear();
    modeloVisivel = false;
    corrigida = false;
    nota = null;
    geracao++;
    notifyListeners();
  }

  void desfazer() {
    final b = _backup;
    if (b == null || !_vivo) return;
    flush?.call();
    escolha = b.escolha;
    marcas
      ..clear()
      ..addAll(b.marcas);
    checks
      ..clear()
      ..addAll(b.checks);
    lacunaOk
      ..clear()
      ..addAll(b.lacunaOk);
    modeloVisivel = b.modeloVisivel;
    corrigida = b.corrigida;
    nota = b.nota;
    b.textos.forEach((s, t) => AppState.I.salvarResposta(q.id, s, t));
    _backup = null;
    geracao++;
    notifyListeners();
  }

  /// Texto da questão para o contexto do copiloto.
  String contexto() {
    final b = StringBuffer();
    final p = AppState.I;
    b.writeln('${tituloProva(q)} · Questão ${q.numero} (${nomeTipo(q.tipo)}; módulo ${moduloNome(q.modulo)})');
    if (q.foraDoEscopo) b.writeln('(Questão fora do escopo da P2.)');
    b.writeln('Enunciado: ${q.enunciado}');
    switch (q.tipo) {
      case 'multipla':
        if (q.pedeIncorreta) b.writeln('A questão pede a alternativa INCORRETA.');
        for (final a in q.alternativas) {
          b.writeln('${a['letra']}) ${a['texto']}');
        }
        b.writeln(
          escolha == null
              ? 'Ela ainda não marcou nenhuma alternativa.'
              : 'Ela marcou: $escolha${corrigida ? '' : ' (ainda não confirmou)'}.',
        );
        if (mostraGabarito) b.writeln('Gabarito: ${q.correta ?? 'não definido'}.');
      case 'vf':
        for (var i = 0; i < q.itens.length; i++) {
          final it = q.itens[i];
          final m = marcas[i];
          b.writeln(
            '${i + 1}. ${it['texto']} — ela marcou: ${m == null
                ? '(nada)'
                : m
                ? 'V'
                : 'F'}',
          );
          final just = p.nota('vf', '${q.id}#$i');
          if (just.isNotEmpty) b.writeln('   Justificativa dela: $just');
          if (mostraGabarito) {
            b.writeln('   Gabarito: ${it['resposta'] == true ? 'V' : 'F'} — ${it['justificativa'] ?? ''}');
          }
        }
      case 'discursiva':
        if (q.subitens.isEmpty) {
          final r = p.resposta(q.id);
          b.writeln('Resposta dela: ${r.trim().isEmpty ? '(em branco)' : r}');
          if (mostraGabarito) {
            b.writeln('Resposta-modelo: ${q.respostaModelo}');
            if (q.checklist.isNotEmpty) b.writeln('Pontos-chave: ${q.checklist.join('; ')}');
          }
        } else {
          for (final s in q.subitens) {
            final k = _subKey(s);
            final r = p.resposta(q.id, k);
            b.writeln('$k) ${s['pergunta'] ?? ''}');
            b.writeln('   Resposta dela: ${r.trim().isEmpty ? '(em branco)' : r}');
            if (mostraGabarito) {
              b.writeln('   Resposta-modelo: ${s['resposta_modelo'] ?? ''}');
              final ck = List<String>.from((s['checklist'] as List?) ?? const []);
              if (ck.isNotEmpty) b.writeln('   Pontos-chave: ${ck.join('; ')}');
            }
          }
        }
      case 'lacunas':
        for (var i = 0; i < q.lacunas.length; i++) {
          final l = q.lacunas[i];
          final r = p.resposta(q.id, '$i');
          b.writeln(
            '${dicaLimpa(l, i)} — ela escreveu: ${r.trim().isEmpty ? '(em branco)' : r}'
            '${mostraGabarito ? ' · gabarito: ${l['resposta']}' : ''}',
          );
        }
    }
    if (mostraGabarito) {
      if (q.explicacao.isNotEmpty) b.writeln('Explicação: ${q.explicacao}');
      if (q.observacao.isNotEmpty) b.writeln('Observação: ${q.observacao}');
      b.writeln('Fonte do gabarito: ${fonteGabarito(q.gabaritoFonte)} (confiança ${q.confianca}).');
      if (nota != null) b.writeln('Nota dela nesta tentativa: ${pct(nota!)}.');
    } else {
      b.writeln('(Ela ainda não viu o gabarito — não entregue a resposta a menos que ela peça.)');
    }
    final n = p.nota('questao', q.id);
    if (n.isNotEmpty) b.writeln('Anotação dela: $n');
    return b.toString();
  }
}

class _Snapshot {
  final String? escolha;
  final Map<int, bool> marcas;
  final Map<String, bool> checks;
  final Map<int, bool> lacunaOk;
  final bool modeloVisivel, corrigida;
  final double? nota;
  final Map<String, String> textos;
  _Snapshot(
    this.escolha,
    this.marcas,
    this.checks,
    this.lacunaOk,
    this.modeloVisivel,
    this.corrigida,
    this.nota,
    this.textos,
  );
}

String dicaLimpa(Json l, int i) =>
    '${i + 1}. ${'${l['dica'] ?? ''}'.replaceFirst(RegExp(r'^\s*\d+\s*[.)\-–]\s*'), '')}';

// =====================================================================================
// Cartão de questão
// =====================================================================================

class QuestaoCard extends StatelessWidget {
  final QuestaoCtrl ctrl;
  const QuestaoCard({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final q = ctrl.q;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) => ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          CabecalhoQuestao(q: q),
          const SizedBox(height: 16),
          switch (q.tipo) {
            'multipla' => _Multipla(ctrl: ctrl),
            'vf' => _VouF(ctrl: ctrl),
            'discursiva' => _Discursiva(key: ValueKey('d${ctrl.geracao}'), ctrl: ctrl),
            'lacunas' => _Lacunas(key: ValueKey('l${ctrl.geracao}'), ctrl: ctrl),
            _ => Text('Formato de questão não reconhecido (${q.tipo}).', style: TextStyle(color: context.pal.inkSoft)),
          },
          if (ctrl.mostraGabarito) ...[const SizedBox(height: 18), RodapeGabarito(q: q)],
          const SizedBox(height: 18),
          CampoNota(key: ValueKey('nota-${q.id}'), kind: 'questao', ref: q.id),
          if (ctrl.mostraGabarito) ...[
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  ctrl.tentarDeNovo();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: const Text('Questão reiniciada. Suas anotações continuam aqui.'),
                        action: SnackBarAction(label: 'Desfazer', onPressed: ctrl.desfazer),
                      ),
                    );
                },
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Tentar de novo'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CabecalhoQuestao extends StatelessWidget {
  final Question q;
  const CabecalhoQuestao({super.key, required this.q});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cor = p.modulo(q.modulo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Selo('${tituloProva(q)} · Q${q.numero}', cor: p.inkSoft, icone: Icons.description_outlined),
            Selo(moduloNome(q.modulo), cor: cor, icone: moduloIcone(q.modulo)),
            Selo(nomeTipo(q.tipo), cor: p.inkSoft),
            if (q.freq > 1) Selo('caiu em ${q.freq} provas', cor: p.primary, icone: Icons.repeat_rounded),
            if (q.pontos != null) Selo(fmtPontos(q.pontos!), cor: p.inkSoft),
            if (q.foraDoEscopo) Selo('fora da P2', cor: p.warn, icone: Icons.block_outlined),
          ],
        ),
        const SizedBox(height: 14),
        MdText(q.enunciado, style: const TextStyle(fontSize: 16, height: 1.5)),
      ],
    );
  }
}

/// Explicação, fonte do gabarito e observação — mostrado depois de corrigir.
class RodapeGabarito extends StatelessWidget {
  final Question q;
  const RodapeGabarito({super.key, required this.q});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fonte = q.gabaritoFonte;
    final naoOficial = const {'chat', 'notebooklm', 'inferido'}.contains(fonte);
    final aviso = naoOficial
        ? 'Gabarito não oficial — confira com o material.'
        : q.confianca != 'alta'
        ? 'Gabarito com confiança ${q.confianca == 'baixa' ? 'baixa' : 'média'} — confira.'
        : null;
    final fonteBoa = fonte == 'oficial' || fonte == 'foto';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (q.explicacao.isNotEmpty)
          Painel(
            color: p.surfaceAlt,
            borda: Colors.transparent,
            raio: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [const Rotulo('Comentário'), const SizedBox(height: 6), MdText(q.explicacao)],
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Selo(
              fonteGabarito(fonte),
              cor: fonteBoa ? p.ok : p.inkSoft,
              icone: fonteBoa ? Icons.verified_outlined : Icons.help_outline,
            ),
            Selo(
              'confiança ${switch (q.confianca) {
                'alta' => 'alta',
                'baixa' => 'baixa',
                _ => 'média',
              }}',
              cor: p.inkSoft,
            ),
          ],
        ),
        if (aviso != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: p.inkSoft),
              const SizedBox(width: 6),
              Expanded(
                child: Text(aviso, style: TextStyle(fontSize: 13, color: p.inkSoft, height: 1.4)),
              ),
            ],
          ),
        ],
        if (q.observacao.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sticky_note_2_outlined, size: 15, color: p.inkSoft),
                    const SizedBox(width: 6),
                    const Rotulo('Observação'),
                  ],
                ),
                const SizedBox(height: 6),
                MdText(q.observacao, style: TextStyle(fontSize: 13.5, color: p.inkSoft)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Faixa de resultado ("Você acertou" / "Resposta certa: B").
class _Resultado extends StatelessWidget {
  final bool ok;
  final String texto;
  const _Resultado({required this.ok, required this.texto});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cor = ok ? p.ok : p.bad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: p.soft(cor), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, color: cor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontWeight: FontWeight.w600, color: cor, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _botaoLargo(Widget b) => SizedBox(width: double.infinity, child: b);

// =====================================================================================
// Múltipla escolha
// =====================================================================================

class _Multipla extends StatelessWidget {
  final QuestaoCtrl ctrl;
  const _Multipla({required this.ctrl});

  void _confirmar() {
    final q = ctrl.q;
    if (q.correta == null) {
      ctrl.corrigida = true;
      ctrl.mudou();
      return;
    }
    final acertou = ctrl.escolha == q.correta;
    ctrl.registrar(acertou ? 1 : 0, {'escolha': ctrl.escolha, 'correta': q.correta});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final q = ctrl.q;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (q.pedeIncorreta) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: p.soft(p.warn, .14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.soft(p.warn, .4)),
            ),
            child: Row(
              children: [
                Icon(Icons.priority_high_rounded, size: 18, color: p.warn),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Marque a INCORRETA',
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.warn, letterSpacing: .3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final a in q.alternativas) _alternativa(context, a),
        const SizedBox(height: 6),
        if (!ctrl.corrigida)
          _botaoLargo(FilledButton(onPressed: ctrl.escolha == null ? null : _confirmar, child: const Text('Confirmar')))
        else if (q.correta == null)
          const _Resultado(ok: true, texto: 'Esta questão não tem gabarito definido.')
        else if (ctrl.escolha == q.correta)
          const _Resultado(ok: true, texto: 'Você acertou!')
        else
          _Resultado(ok: false, texto: 'Resposta certa: ${q.correta}'),
      ],
    );
  }

  Widget _alternativa(BuildContext context, Json a) {
    final p = context.pal;
    final q = ctrl.q;
    final letra = '${a['letra']}';
    final sel = ctrl.escolha == letra;
    final certa = q.correta == letra;
    var borda = p.line;
    Color? fundo;
    var corLetra = p.inkSoft;
    IconData? icone;
    var apagada = false;
    if (!ctrl.corrigida) {
      if (sel) {
        borda = p.primary;
        fundo = p.soft(p.primary, .08);
        corLetra = p.primary;
      }
    } else if (certa) {
      borda = p.ok;
      fundo = p.soft(p.ok);
      corLetra = p.ok;
      icone = Icons.check_circle_rounded;
    } else if (sel) {
      borda = p.bad;
      fundo = p.soft(p.bad);
      corLetra = p.bad;
      icone = Icons.cancel_rounded;
    } else {
      apagada = true;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: apagada ? .55 : 1,
        child: Painel(
          raio: 14,
          borda: borda,
          color: fundo,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          onTap: ctrl.corrigida
              ? null
              : () {
                  ctrl.escolha = letra;
                  ctrl.mudou();
                },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: sel && !ctrl.corrigida ? p.primary : Colors.transparent,
                  border: Border.all(color: corLetra, width: 1.4),
                ),
                child: Text(
                  letra,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: sel && !ctrl.corrigida ? p.onPrimary : corLetra,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(padding: const EdgeInsets.only(top: 3), child: MdText('${a['texto'] ?? ''}')),
              ),
              if (icone != null) ...[const SizedBox(width: 6), Icon(icone, color: corLetra, size: 20)],
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================================
// V ou F
// =====================================================================================

class _VouF extends StatelessWidget {
  final QuestaoCtrl ctrl;
  const _VouF({required this.ctrl});

  void _corrigir() {
    final itens = ctrl.q.itens;
    var acertos = 0, validos = 0;
    for (var i = 0; i < itens.length; i++) {
      final r = itens[i]['resposta'];
      if (r is! bool) continue;
      validos++;
      if (ctrl.marcas[i] == r) acertos++;
    }
    ctrl.registrar(validos == 0 ? 0 : acertos / validos, {
      'marcas': {for (final e in ctrl.marcas.entries) '${e.key}': e.value},
      'acertos': acertos,
      'itens': validos,
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final itens = ctrl.q.itens;
    final todos = ctrl.marcas.length >= itens.length;
    var acertos = 0;
    for (var i = 0; i < itens.length; i++) {
      if (ctrl.marcas[i] == itens[i]['resposta']) acertos++;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < itens.length; i++) ...[_item(context, i, itens[i]), const SizedBox(height: 12)],
        if (!ctrl.corrigida) ...[
          _botaoLargo(
            FilledButton(
              onPressed: todos ? _corrigir : null,
              child: Text(todos ? 'Corrigir' : 'Marque todos os itens (${ctrl.marcas.length}/${itens.length})'),
            ),
          ),
        ] else
          _Resultado(
            ok: acertos == itens.length,
            texto: acertos == itens.length
                ? 'Todos certos! ($acertos de ${itens.length})'
                : '$acertos de ${itens.length} itens certos',
          ),
        if (!ctrl.corrigida) ...[
          const SizedBox(height: 8),
          Text(
            'Na prova, justifique as falsas — escreva a sua justificativa embaixo de cada item.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: p.inkFaint),
          ),
        ],
      ],
    );
  }

  Widget _item(BuildContext context, int i, Json it) {
    final p = context.pal;
    final marca = ctrl.marcas[i];
    final certa = it['resposta'];
    final ok = marca == certa;
    return Painel(
      raio: 14,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borda: ctrl.corrigida ? (ok ? p.soft(p.ok, .6) : p.soft(p.bad, .6)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${i + 1}.',
                  style: TextStyle(fontWeight: FontWeight.w700, color: p.inkSoft, height: 1.5),
                ),
              ),
              Expanded(child: MdText('${it['texto'] ?? ''}')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _botaoVF(context, i, true, certa)),
              const SizedBox(width: 10),
              Expanded(child: _botaoVF(context, i, false, certa)),
            ],
          ),
          if (ctrl.corrigida) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                  size: 18,
                  color: ok ? p.ok : p.bad,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    certa is! bool
                        ? 'Item sem gabarito definido.'
                        : ok
                        ? 'Certo — é ${certa ? 'VERDADEIRA' : 'FALSA'}.'
                        : 'Resposta: ${certa ? 'VERDADEIRA' : 'FALSA'}.',
                    style: TextStyle(fontWeight: FontWeight.w600, color: ok ? p.ok : p.bad),
                  ),
                ),
              ],
            ),
            if ('${it['justificativa'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 6),
              MdText('${it['justificativa']}', style: TextStyle(fontSize: 14, color: p.inkSoft)),
            ],
          ],
          const SizedBox(height: 10),
          CampoNota(
            key: ValueKey('vf-${ctrl.q.id}#$i'),
            kind: 'vf',
            ref: '${ctrl.q.id}#$i',
            rotulo: 'Minha justificativa',
            dica: 'Se for falsa, por quê?',
            minLinhas: 1,
          ),
        ],
      ),
    );
  }

  Widget _botaoVF(BuildContext context, int i, bool valor, Object? certa) {
    final p = context.pal;
    final sel = ctrl.marcas[i] == valor;
    var cor = p.primary;
    if (ctrl.corrigida) {
      if (valor == certa) {
        cor = p.ok;
      } else if (sel) {
        cor = p.bad;
      } else {
        cor = p.inkFaint;
      }
    }
    final cheio = sel;
    final destacar = ctrl.corrigida && valor == certa && !sel;
    return Material(
      color: cheio ? cor : (destacar ? p.soft(p.ok) : p.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cheio || destacar ? cor : p.line, width: destacar ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ctrl.corrigida
            ? null
            : () {
                ctrl.marcas[i] = valor;
                ctrl.mudou();
              },
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                valor ? 'V' : 'F',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: cheio ? p.surface : (destacar ? p.ok : p.ink),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  valor ? 'Verdadeiro' : 'Falso',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cheio ? p.surface : p.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================================
// Campos de texto com salvamento automático (base de discursiva e lacunas)
// =====================================================================================

mixin _Autosave<T extends StatefulWidget> on State<T> {
  QuestaoCtrl get ctrlQ;
  final Map<String, TextEditingController> campos = {};
  final Map<String, Timer> _timers = {};

  TextEditingController campo(String sub) =>
      campos.putIfAbsent(sub, () => TextEditingController(text: AppState.I.resposta(ctrlQ.q.id, sub)));

  void mudouCampo(String sub) {
    _timers[sub]?.cancel();
    _timers[sub] = Timer(const Duration(milliseconds: 600), () {
      _timers.remove(sub);
      AppState.I.salvarResposta(ctrlQ.q.id, sub, campos[sub]!.text);
    });
  }

  void salvarPendentes() {
    for (final sub in _timers.keys.toList()) {
      _timers.remove(sub)!.cancel();
      AppState.I.salvarResposta(ctrlQ.q.id, sub, campos[sub]!.text);
    }
  }

  @override
  void initState() {
    super.initState();
    ctrlQ.flush = salvarPendentes;
  }

  @override
  void dispose() {
    salvarPendentes();
    if (ctrlQ.flush == salvarPendentes) ctrlQ.flush = null;
    for (final c in campos.values) {
      c.dispose();
    }
    super.dispose();
  }
}

// =====================================================================================
// Discursiva / caso clínico
// =====================================================================================

class _Discursiva extends StatefulWidget {
  final QuestaoCtrl ctrl;
  const _Discursiva({super.key, required this.ctrl});
  @override
  State<_Discursiva> createState() => _DiscursivaState();
}

class _DiscursivaState extends State<_Discursiva> with _Autosave<_Discursiva> {
  @override
  QuestaoCtrl get ctrlQ => widget.ctrl;
  Question get q => widget.ctrl.q;

  final Map<String, FocusNode> _focos = {};
  String _ativo = '';

  static const _roteiro = [
    'Diagnóstico completo',
    'Morfologia',
    'Imuno-histoquímica (+/−)',
    'Evolução',
    'Diferenciais',
  ];

  List<String> get _subs => q.subitens.isEmpty ? [''] : [for (final s in q.subitens) _subKey(s)];

  @override
  void initState() {
    super.initState();
    _ativo = _subs.first;
  }

  @override
  void dispose() {
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  FocusNode _foco(String sub) => _focos.putIfAbsent(sub, () {
    final f = FocusNode();
    f.addListener(() {
      if (f.hasFocus && _ativo != sub) setState(() => _ativo = sub);
    });
    return f;
  });

  void _inserir(String cab) {
    final c = campo(_ativo);
    final t = c.text;
    final sel = c.selection;
    final pos = sel.isValid ? sel.end.clamp(0, t.length) : t.length;
    final antes = t.substring(0, pos);
    final depois = t.substring(pos);
    final prefixo = antes.isEmpty ? '' : (antes.endsWith('\n\n') ? '' : (antes.endsWith('\n') ? '\n' : '\n\n'));
    final ins = '$prefixo$cab: ';
    c.value = TextEditingValue(
      text: antes + ins + depois,
      selection: TextSelection.collapsed(offset: antes.length + ins.length),
    );
    mudouCampo(_ativo);
    _foco(_ativo).requestFocus();
  }

  int get _totalChecks => q.subitens.isEmpty
      ? q.checklist.length
      : q.subitens.fold(0, (a, s) => a + ((s['checklist'] as List?)?.length ?? 0));

  int get _marcados => widget.ctrl.checks.values.where((v) => v).length;

  void _salvarAutoavaliacao() {
    salvarPendentes();
    final total = _totalChecks;
    if (total == 0) return;
    widget.ctrl.registrar(_marcados / total, {
      'checklist': {for (final e in widget.ctrl.checks.entries) e.key: e.value},
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Autoavaliação salva: $_marcados de $total pontos-chave.')));
  }

  void _pedirCorrecao() {
    salvarPendentes();
    final resp = [for (final s in _subs) campo(s).text.trim()];
    if (resp.every((r) => r.isEmpty)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Escreva sua resposta antes de pedir a correção.')));
      return;
    }
    final b = StringBuffer()
      ..writeln('Corrija a minha resposta desta questão discursiva (${tituloProva(q)}, questão ${q.numero}).')
      ..writeln()
      ..writeln('ENUNCIADO: ${q.enunciado}')
      ..writeln();
    if (q.subitens.isEmpty) {
      b
        ..writeln('MINHA RESPOSTA: ${resp.first.isEmpty ? '(em branco)' : resp.first}')
        ..writeln()
        ..writeln('RESPOSTA-MODELO: ${q.respostaModelo}');
      if (q.checklist.isNotEmpty) b.writeln('PONTOS-CHAVE: ${q.checklist.join('; ')}');
    } else {
      for (var i = 0; i < q.subitens.length; i++) {
        final s = q.subitens[i];
        final ck = List<String>.from((s['checklist'] as List?) ?? const []);
        b
          ..writeln('${_subKey(s)}) ${s['pergunta'] ?? ''}')
          ..writeln('   Minha resposta: ${resp[i].isEmpty ? '(em branco)' : resp[i]}')
          ..writeln('   Resposta-modelo: ${s['resposta_modelo'] ?? ''}');
        if (ck.isNotEmpty) b.writeln('   Pontos-chave: ${ck.join('; ')}');
      }
    }
    b
      ..writeln()
      ..write(
        'Diga o que está certo, o que faltou e o que está errado, com a nota que o professor daria, '
        'e termine com uma versão enxuta que tiraria nota máxima.',
      );
    abrirCopiloto(rascunho: b.toString(), enviarJa: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = widget.ctrl;
    final caso = ehCasoClinico(q);
    final total = _totalChecks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caso) ...[
          TextFieldTapRegion(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _subs.length > 1
                      ? 'Roteiro do caso — toque para inserir no item ${_ativo.isEmpty ? '' : '$_ativo) '}em edição:'
                      : 'Roteiro do caso — toque para inserir na resposta:',
                  style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in _roteiro)
                      ActionChip(
                        label: Text(r),
                        avatar: Icon(Icons.add_rounded, size: 16, color: p.primary),
                        labelStyle: TextStyle(fontSize: 12.5, color: p.ink, fontWeight: FontWeight.w500),
                        backgroundColor: p.surface,
                        side: BorderSide(color: p.line),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _inserir(r),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (q.subitens.isEmpty) ...[
          _campo('', 'Escreva sua resposta como escreveria na prova…', 6),
          if (c.modeloVisivel) ...[const SizedBox(height: 12), _modelo(context, '', q.respostaModelo, q.checklist)],
        ] else
          for (final s in q.subitens) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_subKey(s)}) ',
                  style: TextStyle(fontWeight: FontWeight.w800, color: p.modulo(q.modulo), fontSize: 15, height: 1.5),
                ),
                Expanded(child: MdText('${s['pergunta'] ?? ''}')),
              ],
            ),
            const SizedBox(height: 8),
            _campo(_subKey(s), 'Sua resposta para ${_subKey(s)})…', 3),
            if (c.modeloVisivel) ...[
              const SizedBox(height: 10),
              _modelo(
                context,
                _subKey(s),
                '${s['resposta_modelo'] ?? ''}',
                List<String>.from(((s['checklist'] as List?) ?? const []).map((e) => '$e')),
              ),
            ],
            const SizedBox(height: 18),
          ],
        const SizedBox(height: 10),
        if (!c.modeloVisivel)
          _botaoLargo(
            OutlinedButton.icon(
              onPressed: () {
                salvarPendentes();
                c.modeloVisivel = true;
                c.mudou();
              },
              icon: const Icon(Icons.visibility_outlined, size: 19),
              label: const Text('Ver resposta-modelo'),
            ),
          )
        else if (total > 0) ...[
          if (c.corrigida && c.nota != null) ...[
            _Resultado(
              ok: c.nota! >= .7,
              texto: 'Autoavaliação: ${(c.nota! * total).round()} de $total pontos-chave (${pct(c.nota!)})',
            ),
            const SizedBox(height: 10),
          ],
          _botaoLargo(
            FilledButton.icon(
              onPressed: _salvarAutoavaliacao,
              icon: const Icon(Icons.task_alt_rounded, size: 19),
              label: Text('${c.corrigida ? 'Atualizar' : 'Salvar'} autoavaliação ($_marcados/$total)'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _botaoLargo(
          TextButton.icon(
            onPressed: _pedirCorrecao,
            icon: const Icon(Icons.auto_awesome_outlined, size: 19),
            label: const Text('Pedir correção ao copiloto'),
          ),
        ),
      ],
    );
  }

  Widget _campo(String sub, String dica, int linhas) {
    final p = context.pal;
    return TextField(
      controller: campo(sub),
      focusNode: _foco(sub),
      onChanged: (_) => mudouCampo(sub),
      minLines: linhas,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      scrollPadding: const EdgeInsets.only(bottom: 120),
      style: TextStyle(fontSize: 15, height: 1.5, color: p.ink),
      decoration: InputDecoration(hintText: dica),
    );
  }

  Widget _modelo(BuildContext context, String sub, String modelo, List<String> checklist) {
    final p = context.pal;
    final c = widget.ctrl;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: p.soft(p.primary, .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.soft(p.primary, .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Rotulo('Resposta-modelo', cor: p.primary),
          const SizedBox(height: 6),
          if (modelo.trim().isNotEmpty)
            MdText(modelo)
          else
            Text(
              'Sem resposta-modelo escrita — use os pontos-chave abaixo.',
              style: TextStyle(color: p.inkSoft, fontSize: 14),
            ),
          if (checklist.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Rotulo('Minha resposta tinha…'),
            const SizedBox(height: 2),
            for (var i = 0; i < checklist.length; i++)
              CheckboxListTile(
                value: c.checks['$sub#$i'] ?? false,
                onChanged: (v) {
                  c.checks['$sub#$i'] = v ?? false;
                  c.mudou();
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                activeColor: p.ok,
                title: MdText(checklist[i], style: const TextStyle(fontSize: 14, height: 1.4)),
              ),
          ],
        ],
      ),
    );
  }
}

// =====================================================================================
// Lacunas / completar
// =====================================================================================

class _Lacunas extends StatefulWidget {
  final QuestaoCtrl ctrl;
  const _Lacunas({super.key, required this.ctrl});
  @override
  State<_Lacunas> createState() => _LacunasState();
}

class _LacunasState extends State<_Lacunas> with _Autosave<_Lacunas> {
  @override
  QuestaoCtrl get ctrlQ => widget.ctrl;

  bool get _algumPreenchido {
    for (var i = 0; i < widget.ctrl.q.lacunas.length; i++) {
      if (campo('$i').text.trim().isNotEmpty) return true;
    }
    return false;
  }

  void _corrigir() {
    salvarPendentes();
    FocusManager.instance.primaryFocus?.unfocus();
    final c = widget.ctrl;
    final ls = c.q.lacunas;
    var acertos = 0;
    c.lacunaOk.clear();
    for (var i = 0; i < ls.length; i++) {
      final ok =
          normalizar(campo('$i').text) == normalizar('${ls[i]['resposta'] ?? ''}') &&
          campo('$i').text.trim().isNotEmpty;
      c.lacunaOk[i] = ok;
      if (ok) acertos++;
    }
    c.registrar(ls.isEmpty ? 0 : acertos / ls.length, {
      'respostas': [for (var i = 0; i < ls.length; i++) campo('$i').text],
      'acertos': acertos,
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = widget.ctrl;
    final ls = c.q.lacunas;
    final acertos = c.lacunaOk.values.where((v) => v).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ls.length; i++) ...[_lacuna(context, i, ls[i]), const SizedBox(height: 12)],
        const SizedBox(height: 4),
        if (!c.corrigida)
          _botaoLargo(FilledButton(onPressed: _algumPreenchido ? _corrigir : null, child: const Text('Corrigir')))
        else
          _Resultado(
            ok: acertos == ls.length,
            texto: acertos == ls.length
                ? 'Todas certas! ($acertos de ${ls.length})'
                : '$acertos de ${ls.length} certas',
          ),
        if (!c.corrigida) ...[
          const SizedBox(height: 8),
          Text(
            'Acentos, maiúsculas, espaços e hífens não contam na correção.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: p.inkFaint),
          ),
        ],
      ],
    );
  }

  Widget _lacuna(BuildContext context, int i, Json l) {
    final p = context.pal;
    final c = widget.ctrl;
    final ok = c.lacunaOk[i];
    final corBorda = ok == null ? null : (ok ? p.ok : p.bad);
    final dica = dicaLimpa(l, i).replaceFirst(RegExp(r'^\d+\.\s'), '');
    OutlineInputBorder borda(Color cor, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cor, width: w),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.soft(p.modulo(c.q.modulo)), shape: BoxShape.circle),
          child: Text(
            '${i + 1}',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.modulo(c.q.modulo)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MdText(dica, style: const TextStyle(fontSize: 14.5, height: 1.45)),
              const SizedBox(height: 6),
              TextField(
                controller: campo('$i'),
                readOnly: c.corrigida,
                onChanged: (_) {
                  mudouCampo('$i');
                  setState(() {});
                },
                textCapitalization: TextCapitalization.characters,
                textInputAction: i == c.q.lacunas.length - 1 ? TextInputAction.done : TextInputAction.next,
                scrollPadding: const EdgeInsets.only(bottom: 120),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: .6, color: p.ink),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'resposta',
                  suffixIcon: ok == null
                      ? null
                      : Icon(ok ? Icons.check_rounded : Icons.close_rounded, color: corBorda, size: 20),
                  enabledBorder: corBorda == null ? null : borda(corBorda),
                  focusedBorder: corBorda == null ? null : borda(corBorda, 1.6),
                  fillColor: corBorda == null ? null : p.soft(corBorda, .06),
                ),
              ),
              if (ok == false) ...[
                const SizedBox(height: 5),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Resposta: ',
                        style: TextStyle(color: p.inkSoft),
                      ),
                      TextSpan(
                        text: '${l['resposta'] ?? ''}',
                        style: TextStyle(color: p.ok, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
