import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/copilot.dart';
import '../../theme.dart';
import '../questions/sessao_questoes.dart';
import '../widgets/common.dart';

String nomeFormato(String tipo) => switch (tipo) {
      'multipla' => 'Múltipla escolha',
      'vf' => 'V ou F',
      'discursiva' => 'Discursiva',
      'lacunas' => 'Lacunas',
      _ => tipo.isEmpty ? 'Outro' : '${tipo[0].toUpperCase()}${tipo.substring(1)}',
    };

/// Análise das provas antigas: o que pesa, em que formato, o que se repete.
class RaioXScreen extends StatelessWidget {
  const RaioXScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = AppState.I;
    final qs = s.questoes.where((q) => !q.foraDoEscopo).toList();

    final porTopico = <String, int>{};
    final porModulo = <String, int>{};
    final porFormato = <String, int>{};
    for (final q in qs) {
      for (final t in q.topicos) {
        porTopico[t] = (porTopico[t] ?? 0) + 1;
      }
      porModulo[q.modulo] = (porModulo[q.modulo] ?? 0) + 1;
      porFormato[q.tipo] = (porFormato[q.tipo] ?? 0) + 1;
    }
    List<MapEntry<String, int>> ord(Map<String, int> m) => m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topicos = ord(porTopico).where((e) => e.key != 'fora-escopo').take(15).toList();
    final modulos = ord(porModulo);
    final formatos = ord(porFormato);
    final repetidas = qs.where((q) => q.freq >= 2 && q.representante).toList()
      ..sort((a, b) => b.freq.compareTo(a.freq));

    final ctx = TelaCtx('Raio-X da prova', () {
      final b = StringBuffer('Raio-X das provas antigas (${qs.length} questões, ${s.provas.length} provas).\n');
      b.writeln('Por módulo: ${modulos.map((e) => '${moduloNome(e.key)} ${e.value}').join(', ')}');
      b.writeln('Por formato: ${formatos.map((e) => '${nomeFormato(e.key)} ${e.value}').join(', ')}');
      b.writeln('Tópicos mais cobrados: ${topicos.map((e) => '${topicoNome(e.key)} (${e.value})').join('; ')}');
      b.writeln('Questões repetidas: ${repetidas.length}');
      return b.toString();
    }, sugestoes: const [
      'Com base nisso, o que eu priorizo?',
      'Quais as questões que mais se repetem?',
      'Que formato de questão devo treinar mais?',
    ]);

    return CtxCopiloto(
      ctx: ctx,
      child: Scaffold(
        appBar: AppBar(title: const Text('Raio-X da prova')),
        body: qs.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Ainda não há questões carregadas para analisar.',
                      textAlign: TextAlign.center, style: TextStyle(color: p.inkSoft)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                children: [
                  _Leitura(qs: qs, modulos: modulos, topicos: topicos, repetidas: repetidas.length),
                  const SizedBox(height: 22),
                  const Rotulo('Tópicos que mais caem'),
                  const SizedBox(height: 4),
                  Text('Toque num tópico para treinar só ele.', style: TextStyle(fontSize: 13, color: p.inkSoft)),
                  const SizedBox(height: 10),
                  Painel(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [
                      for (final e in topicos)
                        _BarraItem(
                          rotulo: topicoNome(e.key),
                          valor: e.value,
                          max: topicos.first.value,
                          cor: p.modulo(moduloDoTopico(e.key)),
                          onTap: () {
                            final lista = s.questoesDoTopicos([e.key]);
                            if (lista.isEmpty) return;
                            abrir(context, SessaoQuestoes(titulo: topicoNome(e.key), questoes: lista));
                          },
                        ),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  const Rotulo('Por módulo'),
                  const SizedBox(height: 10),
                  Painel(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [
                      for (final e in modulos)
                        _BarraItem(
                          rotulo: moduloNome(e.key),
                          valor: e.value,
                          max: modulos.first.value,
                          cor: p.modulo(e.key),
                          sufixo: '${(e.value * 100 / qs.length).round()}%',
                        ),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  const Rotulo('Por formato'),
                  const SizedBox(height: 10),
                  Painel(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [
                      for (final e in formatos)
                        _BarraItem(
                          rotulo: nomeFormato(e.key),
                          valor: e.value,
                          max: formatos.first.value,
                          cor: p.primary,
                          sufixo: '${(e.value * 100 / qs.length).round()}%',
                        ),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  const Rotulo('Repetidas entre provas'),
                  const SizedBox(height: 4),
                  Text(
                    repetidas.isEmpty
                        ? 'Nenhuma questão idêntica apareceu em mais de uma prova.'
                        : 'Caíram mais de uma vez. São as apostas mais seguras.',
                    style: TextStyle(fontSize: 13, color: p.inkSoft),
                  ),
                  const SizedBox(height: 10),
                  for (final q in repetidas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _Repetida(q: q),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Leitura extends StatelessWidget {
  final List<Question> qs;
  final List<MapEntry<String, int>> modulos, topicos;
  final int repetidas;
  const _Leitura({required this.qs, required this.modulos, required this.topicos, required this.repetidas});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final provas = qs.map((q) => q.provaId).toSet().length;
    final topMod = modulos.isEmpty ? null : modulos.first;
    final discursivas = qs.where((q) => q.tipo == 'discursiva').length;
    final base = TextStyle(fontSize: 14.5, height: 1.55, color: p.ink);
    final b = TextStyle(fontWeight: FontWeight.w700, color: p.ink);
    return Painel(
      color: p.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('O que os dados dizem', style: TextStyle(fontFamily: kSerif, fontSize: 22, height: 1.2, color: p.ink)),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(style: base, children: [
            TextSpan(text: '${qs.length} questões', style: b),
            TextSpan(text: ' de $provas provas. '),
            if (topMod != null) ...[
              const TextSpan(text: 'O módulo que mais pesa é '),
              TextSpan(text: moduloNome(topMod.key), style: b.copyWith(color: p.modulo(topMod.key))),
              TextSpan(text: ' (${(topMod.value * 100 / qs.length).round()}% das questões). '),
            ],
            if (topicos.length >= 3) ...[
              const TextSpan(text: 'Os tópicos campeões: '),
              TextSpan(text: topicos.take(3).map((e) => topicoNome(e.key)).join(', '), style: b),
              const TextSpan(text: '. '),
            ],
            TextSpan(
                text: '${(discursivas * 100 / qs.length).round()}% são discursivas — treine escrever o diagnóstico '
                    'completo. '),
            if (repetidas > 0) TextSpan(text: '$repetidas questões se repetiram entre provas.'),
          ]),
        ),
      ]),
    );
  }
}

class _BarraItem extends StatelessWidget {
  final String rotulo;
  final int valor, max;
  final Color cor;
  final String? sufixo;
  final VoidCallback? onTap;
  const _BarraItem(
      {required this.rotulo, required this.valor, required this.max, required this.cor, this.sufixo, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.ink, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Text(sufixo == null ? '$valor' : '$valor · $sufixo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.inkSoft)),
            if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: p.inkFaint),
          ]),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) => Align(
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: (c.maxWidth * (max == 0 ? 0 : valor / max)).clamp(4.0, c.maxWidth),
                height: 8,
                decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(99)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Repetida extends StatelessWidget {
  final Question q;
  const _Repetida({required this.q});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = AppState.I;
    final cor = p.modulo(q.modulo);
    final provas = q.provasDoGrupo.map((id) => s.provaPorId[id]?.titulo ?? id).toList();
    return Painel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => abrir(context, SessaoQuestoes(titulo: 'Questão repetida', questoes: [q])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Selo('caiu em ${q.freq} provas', cor: cor, icone: Icons.repeat_rounded),
          const SizedBox(width: 6),
          Flexible(
            child: Text(nomeFormato(q.tipo),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.inkSoft)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(_limpo(q.enunciado),
            maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.45, color: p.ink)),
        if (provas.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(provas.join(' · '),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.inkFaint)),
        ],
      ]),
    );
  }
}

String _limpo(String s) => s.replaceAll(RegExp(r'\*\*|__|`'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
