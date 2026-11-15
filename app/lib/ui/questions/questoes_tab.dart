import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import 'question_widgets.dart';
import 'sessao_questoes.dart';

const _modulos = ['tireoide', 'linfadenopatias', 'linfomas'];

/// Questões "únicas" para praticar: sem repetições e sem as fora do escopo.
List<Question> _pool() => AppState.I.questoes.where((q) => q.representante && !q.foraDoEscopo).toList();

class QuestoesTab extends StatelessWidget {
  const QuestoesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.bg,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: AppState.I,
          builder: (context, _) {
            final st = AppState.I;
            final pool = _pool();
            if (st.questoes.isEmpty) {
              return ListView(
                children: [
                  const TituloAba('Questões'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                    child: Text(
                      st.pronto
                          ? 'Nenhuma questão carregada. Confira se o conteúdo do app foi gerado (questoes.json).'
                          : 'Carregando as questões…',
                      style: TextStyle(color: p.inkSoft, height: 1.45),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 110),
              children: [
                const TituloAba('Questões', sub: 'Provas antigas do professor, organizadas por tema'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _Resumo(pool: pool),
                ),
                const _Secao('Praticar agora'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _Atalhos(pool: pool),
                ),
                const _Secao('Por tema'),
                for (final m in _modulos)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _ModuloTemas(modulo: m, pool: pool),
                  ),
                const _Secao(
                  'Por prova (simulado)',
                  sub: 'A prova inteira, na ordem original, com cronômetro — inclusive as repetidas.',
                ),
                for (final e in st.provas)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _ProvaTile(prova: e),
                  ),
                const _Secao('Por formato'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _Formatos(pool: pool),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  final String? sub;
  const _Secao(this.titulo, {this.sub});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Rotulo(titulo),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, style: TextStyle(fontSize: 13, color: p.inkSoft, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  final List<Question> pool;
  const _Resumo({required this.pool});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = AppState.I.desempenho(pool);
    final media = d.media;
    return Painel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${d.feitas}',
                        style: TextStyle(fontFamily: kSerif, fontSize: 30, color: p.ink),
                      ),
                      TextSpan(
                        text: ' / ${d.total}',
                        style: TextStyle(fontSize: 16, color: p.inkSoft),
                      ),
                    ],
                  ),
                ),
                Text('questões respondidas', style: TextStyle(fontSize: 13, color: p.inkSoft)),
                const SizedBox(height: 10),
                Barra(d.total == 0 ? 0 : d.feitas / d.total, cor: p.primary),
              ],
            ),
          ),
          Container(width: 1, height: 58, margin: const EdgeInsets.symmetric(horizontal: 18), color: p.line),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                media == null ? '—' : pct(media),
                style: TextStyle(
                  fontFamily: kSerif,
                  fontSize: 30,
                  color: media == null ? p.inkFaint : (media >= .7 ? p.ok : (media >= .5 ? p.warn : p.bad)),
                ),
              ),
              Text('aproveitamento', style: TextStyle(fontSize: 13, color: p.inkSoft)),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ atalhos

class _Atalhos extends StatelessWidget {
  final List<Question> pool;
  const _Atalhos({required this.pool});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = AppState.I;
    final maisCaem = pool.where((q) => q.freq >= 2).toList()..sort((a, b) => b.freq.compareTo(a.freq));
    final vistos = <String>{};
    final erradas = [
      for (final q in st.questoes)
        if (st.errada(q.id) && vistos.add(q.grupo)) q,
    ];

    void abrirMaisCaem() => abrir(context, SessaoQuestoes(titulo: 'As que mais caem', questoes: maisCaem));

    return Column(
      children: [
        _Atalho(
          icone: Icons.local_fire_department_outlined,
          cor: p.primary,
          titulo: 'As que mais caem',
          sub: maisCaem.isEmpty
              ? 'Nenhuma questão repetida entre provas.'
              : '${maisCaem.length} questões que caíram em 2 provas ou mais',
          onTap: maisCaem.isEmpty ? null : abrirMaisCaem,
        ),
        const SizedBox(height: 8),
        _Atalho(
          icone: Icons.replay_rounded,
          cor: p.bad,
          titulo: 'Refazer as que errei',
          sub: erradas.isEmpty
              ? 'Nenhuma errada até agora. Comece pelas que mais caem.'
              : '${erradas.length} ${erradas.length == 1 ? 'questão' : 'questões'} abaixo de 70%',
          onTap: erradas.isEmpty
              ? (maisCaem.isEmpty ? null : abrirMaisCaem)
              : () => abrir(context, SessaoQuestoes(titulo: 'Refazer as que errei', questoes: erradas)),
        ),
        const SizedBox(height: 8),
        _Atalho(
          icone: Icons.shuffle_rounded,
          cor: p.inkSoft,
          titulo: '10 aleatórias',
          sub: 'Mistura de temas e formatos, para testar a memória',
          onTap: pool.isEmpty
              ? null
              : () {
                  final qs = [...pool]..shuffle(Random());
                  abrir(context, SessaoQuestoes(titulo: '10 aleatórias', questoes: qs.take(10).toList()));
                },
        ),
      ],
    );
  }
}

class _Atalho extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo, sub;
  final VoidCallback? onTap;
  const _Atalho({required this.icone, required this.cor, required this.titulo, required this.sub, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Painel(
      raio: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.soft(cor), borderRadius: BorderRadius.circular(12)),
            child: Icon(icone, color: cor, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 13, color: p.inkSoft, height: 1.3)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: onTap == null ? p.line : p.inkFaint),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ por tema

class _ModuloTemas extends StatefulWidget {
  final String modulo;
  final List<Question> pool;
  const _ModuloTemas({required this.modulo, required this.pool});
  @override
  State<_ModuloTemas> createState() => _ModuloTemasState();
}

class _ModuloTemasState extends State<_ModuloTemas> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = AppState.I;
    final cor = p.modulo(widget.modulo);
    final doModulo = widget.pool.where((q) => q.modulo == widget.modulo).toList();
    final d = st.desempenho(doModulo);
    final topicos = [
      for (final t in topicoNomes.keys)
        if (moduloDoTopico(t) == widget.modulo) (t, widget.pool.where((q) => q.topicos.contains(t)).toList()),
    ].where((e) => e.$2.isNotEmpty).toList();

    return Painel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _aberto = !_aberto),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: p.soft(cor), borderRadius: BorderRadius.circular(12)),
                    child: Icon(moduloIcone(widget.modulo), color: cor, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          moduloNome(widget.modulo),
                          style: TextStyle(fontFamily: kSerif, fontSize: 20, color: p.ink, height: 1.2),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${doModulo.length} questões · ${d.feitas} feitas'
                          '${d.media == null ? '' : ' · ${pct(d.media!)}'}',
                          style: TextStyle(fontSize: 13, color: p.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _aberto ? .5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, color: p.inkSoft),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Barra(d.total == 0 ? 0 : d.feitas / d.total, cor: cor, altura: 4),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_aberto
                ? const SizedBox(width: double.infinity, height: 12)
                : Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Column(
                      children: [
                        if (doModulo.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text('Ainda não há questões deste módulo.', style: TextStyle(color: p.inkSoft)),
                          )
                        else
                          _LinhaTema(
                            titulo: 'Todas de ${moduloNome(widget.modulo)}',
                            questoes: doModulo,
                            cor: cor,
                            forte: true,
                          ),
                        for (final (t, qs) in topicos) _LinhaTema(titulo: topicoNome(t), questoes: qs, cor: cor),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LinhaTema extends StatelessWidget {
  final String titulo;
  final List<Question> questoes;
  final Color cor;
  final bool forte;
  const _LinhaTema({required this.titulo, required this.questoes, required this.cor, this.forte = false});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = AppState.I.desempenho(questoes);
    final media = d.media;
    return InkWell(
      onTap: () => abrir(context, SessaoQuestoes(titulo: titulo, questoes: questoes)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: forte ? cor : p.ink,
                    fontWeight: forte ? FontWeight.w600 : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${questoes.length}', style: TextStyle(fontSize: 13, color: p.inkSoft)),
              SizedBox(
                width: 52,
                child: Text(
                  media == null ? '—' : pct(media),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: media == null ? p.inkFaint : (media >= .7 ? p.ok : (media >= .5 ? p.warn : p.bad)),
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ por prova

class _ProvaTile extends StatelessWidget {
  final Exam prova;
  const _ProvaTile({required this.prova});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = AppState.I;
    final todas = st.questoes.where((q) => q.provaId == prova.id).toList();
    final qs = [...todas.where((q) => !q.foraDoEscopo), ...todas.where((q) => q.foraDoEscopo)];
    final d = st.desempenho(qs);
    final fonte = prova.gabaritoFonte;
    final fonteBoa = fonte == 'oficial' || fonte == 'foto';
    final fora = todas.where((q) => q.foraDoEscopo).length;
    return Painel(
      raio: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      onTap: qs.isEmpty
          ? null
          : () => abrir(context, SessaoQuestoes(titulo: 'Simulado · ${prova.titulo}', questoes: qs, simulado: true)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prova.titulo,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (prova.temas.isNotEmpty) prova.temas,
                    prova.periodo == 'desconhecido' ? 'período desconhecido' : prova.periodo,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: p.inkSoft, height: 1.3),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Selo(
                      fonteGabarito(fonte),
                      cor: fonteBoa ? p.ok : p.inkSoft,
                      icone: fonteBoa ? Icons.verified_outlined : Icons.help_outline,
                    ),
                    Selo('${qs.length} questões', cor: p.inkSoft),
                    if (fora > 0) Selo('$fora fora da P2', cor: p.warn),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                d.media == null ? '—' : pct(d.media!),
                style: TextStyle(
                  fontFamily: kSerif,
                  fontSize: 24,
                  color: d.media == null ? p.inkFaint : (d.media! >= .7 ? p.ok : (d.media! >= .5 ? p.warn : p.bad)),
                ),
              ),
              Text(d.media == null ? 'não feita' : 'última nota', style: TextStyle(fontSize: 11.5, color: p.inkSoft)),
            ],
          ),
          Icon(Icons.chevron_right_rounded, color: p.inkFaint),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ por formato

class _Formatos extends StatelessWidget {
  final List<Question> pool;
  const _Formatos({required this.pool});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final formatos = [
      ('multipla', 'Objetivas', Icons.radio_button_checked_outlined),
      ('vf', 'V ou F', Icons.rule_rounded),
      ('discursiva', 'Discursivas / casos', Icons.edit_note_rounded),
      ('lacunas', 'Completar', Icons.text_fields_rounded),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (tipo, nome, icone) in formatos)
              Builder(
                builder: (context) {
                  final qs = pool.where((q) => q.tipo == tipo).toList();
                  final d = AppState.I.desempenho(qs);
                  return SizedBox(
                    width: w,
                    child: Painel(
                      raio: 16,
                      padding: const EdgeInsets.all(14),
                      onTap: qs.isEmpty ? null : () => abrir(context, SessaoQuestoes(titulo: nome, questoes: qs)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icone, color: qs.isEmpty ? p.inkFaint : p.primary, size: 22),
                          const SizedBox(height: 10),
                          Text(
                            nome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            qs.isEmpty
                                ? 'nenhuma'
                                : '${qs.length} · ${d.media == null ? '${d.feitas} feitas' : pct(d.media!)}',
                            style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
