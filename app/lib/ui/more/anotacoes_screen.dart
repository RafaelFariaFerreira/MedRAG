import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../services/copilot.dart';
import '../../services/rag.dart';
import '../../theme.dart';
import '../material/chapter_screen.dart';
import '../questions/sessao_questoes.dart';
import '../widgets/common.dart';
import 'busca_screen.dart' show blocoPorId, limparMd, textoDoBloco;

class _Nota {
  final String kind, ref, texto, origem, trecho;
  final Color cor;
  final VoidCallback? Function(BuildContext) abrir;
  _Nota(this.kind, this.ref, this.texto, this.origem, this.trecho, this.cor, this.abrir);
}

/// Todas as anotações e destaques dela, agrupados por tipo.
class AnotacoesScreen extends StatefulWidget {
  const AnotacoesScreen({super.key});
  @override
  State<AnotacoesScreen> createState() => _AnotacoesScreenState();
}

class _AnotacoesScreenState extends State<AnotacoesScreen> {
  String _filtro = '';
  final _c = TextEditingController();

  static const _grupos = [
    ('bloco', 'Trechos do material', Icons.short_text_rounded),
    ('capitulo', 'Capítulos', Icons.menu_book_outlined),
    ('questao', 'Questões', Icons.quiz_outlined),
    ('vf', 'V ou F', Icons.rule_rounded),
    ('destaque', 'Destaques', Icons.border_color_outlined),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static String _corte(String s, [int n = 110]) => s.length <= n ? s : '${s.substring(0, n).trimRight()}…';

  List<_Nota> _montar(Pal p) {
    final s = AppState.I;
    final out = <_Nota>[];

    _Nota doBloco(String kind, String ref, String texto) {
      final i = ref.indexOf('#');
      final capId = i < 0 ? ref : ref.substring(0, i);
      final blocoId = i < 0 ? null : ref.substring(i + 1);
      final cap = s.capitulos[capId];
      final b = cap == null || blocoId == null ? null : blocoPorId(cap, blocoId);
      return _Nota(
        kind,
        ref,
        texto,
        cap?.titulo ?? 'Capítulo $capId',
        b == null ? '' : _corte(textoDoBloco(b)),
        cap == null ? p.inkSoft : p.modulo(cap.modulo),
        (ctx) => cap == null ? null : () => abrir(ctx, ChapterScreen(chapterId: capId, blocoInicial: blocoId)),
      );
    }

    for (final e in s.notas.entries) {
      final k = e.key.indexOf('|');
      if (k < 0) continue;
      final kind = e.key.substring(0, k);
      final ref = e.key.substring(k + 1);
      switch (kind) {
        case 'bloco':
        case 'capitulo':
          out.add(doBloco(kind, ref, e.value));
        case 'questao':
        case 'vf':
          final h = ref.indexOf('#');
          final qid = h < 0 ? ref : ref.substring(0, h);
          final q = s.questaoPorId[qid];
          var trecho = q == null ? '' : _corte(limparMd(q.enunciado));
          if (kind == 'vf' && q != null && h >= 0) {
            final idx = int.tryParse(ref.substring(h + 1));
            if (idx != null && idx >= 0 && idx < q.itens.length) {
              trecho = 'Item ${idx + 1}: ${_corte(limparMd('${q.itens[idx]['texto'] ?? ''}'))}';
            }
          }
          out.add(_Nota(
            kind,
            ref,
            e.value,
            q == null ? 'Questão' : '${s.provaPorId[q.provaId]?.titulo ?? q.provaId} · questão ${q.numero}',
            trecho,
            q == null ? p.inkSoft : p.modulo(q.modulo),
            (ctx) => q == null
                ? null
                : () => abrir(ctx, SessaoQuestoes(titulo: 'Questão ${q.numero}', questoes: [q])),
          ));
        default:
          out.add(_Nota(kind, ref, e.value, ref, '', p.inkSoft, (_) => null));
      }
    }
    for (final ref in s.destaques) {
      out.add(doBloco('destaque', ref, ''));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final todas = _montar(p);
        final f = Rag.semAcento(_filtro.trim());
        final vis = f.isEmpty
            ? todas
            : todas.where((n) => Rag.semAcento('${n.texto} ${n.origem} ${n.trecho}').contains(f)).toList();
        return CtxCopiloto(
          ctx: TelaCtx(
            'Minhas anotações',
            () => [
              for (final n in todas.where((n) => n.texto.isNotEmpty))
                '[${n.origem}] ${n.trecho.isEmpty ? '' : '(${n.trecho}) '}${n.texto}'
            ].join('\n'),
            sugestoes: const [
              'Organize minhas anotações num resumo',
              'Tem algo errado nas minhas anotações?',
              'Me teste com base no que eu anotei',
            ],
          ),
          child: Scaffold(
            appBar: AppBar(title: const Text('Minhas anotações')),
            body: todas.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
                    child: Column(children: [
                      Icon(Icons.edit_note_rounded, size: 40, color: p.warn),
                      const SizedBox(height: 12),
                      Text(
                        'Nada anotado ainda. No material, toque num trecho para anotar ou destacar; '
                        'nas questões, use o campo "Minha anotação". Tudo aparece aqui.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14.5, height: 1.5, color: p.inkSoft),
                      ),
                    ]),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    children: [
                      TextField(
                        controller: _c,
                        onChanged: (v) => setState(() => _filtro = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar nas anotações',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _filtro.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpar',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _c.clear();
                                    setState(() => _filtro = '');
                                  },
                                ),
                        ),
                      ),
                      if (vis.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Text('Nenhuma anotação com "$_filtro".',
                              textAlign: TextAlign.center, style: TextStyle(color: p.inkSoft)),
                        ),
                      for (final g in _grupos)
                        if (vis.any((n) => n.kind == g.$1)) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                            child: Row(children: [
                              Icon(g.$3, size: 16, color: p.inkSoft),
                              const SizedBox(width: 6),
                              Rotulo('${g.$2} · ${vis.where((n) => n.kind == g.$1).length}'),
                            ]),
                          ),
                          for (final n in vis.where((n) => n.kind == g.$1))
                            Padding(padding: const EdgeInsets.only(bottom: 8), child: _CartaoNota(nota: n)),
                        ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _CartaoNota extends StatelessWidget {
  final _Nota nota;
  const _CartaoNota({required this.nota});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final acao = nota.abrir(context);
    final destaque = nota.kind == 'destaque';
    return Painel(
      onTap: acao,
      raio: 14,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: nota.cor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(nota.origem,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.inkSoft)),
              ),
            ]),
            if (nota.trecho.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: destaque ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : EdgeInsets.zero,
                decoration: destaque
                    ? BoxDecoration(color: p.marca, borderRadius: BorderRadius.circular(4))
                    : null,
                child: Text(nota.trecho,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, height: 1.4, color: destaque ? p.ink : p.inkFaint, fontStyle: FontStyle.italic)),
              ),
            ],
            if (nota.texto.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: p.nota,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.soft(p.warn, .35)),
                ),
                child: Text(nota.texto, style: TextStyle(fontSize: 14, height: 1.45, color: p.ink)),
              ),
            ],
          ]),
        ),
        if (acao != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Icon(Icons.chevron_right_rounded, color: p.inkFaint),
          ),
      ]),
    );
  }
}
