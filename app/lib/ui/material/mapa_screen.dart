import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import '../widgets/md.dart';
import 'chapter_screen.dart';

/// Mapa do conteúdo: Módulo → Capítulo → seções, com estado e prioridade.
class MapaScreen extends StatelessWidget {
  const MapaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapa do conteúdo')),
      body: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final p = context.pal;
          final mods = AppState.I.modulos;
          if (mods.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'O mapa aparece assim que o material estiver carregado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.inkSoft, fontSize: 14.5),
                ),
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 40 + MediaQuery.paddingOf(context).bottom),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text(
                  'Toque num capítulo para ver as seções; toque numa seção para abrir o capítulo direto nela.',
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: p.inkSoft),
                ),
              ),
              for (final m in mods) _ModuloNo(modulo: m),
            ],
          );
        },
      ),
    );
  }
}

class _ModuloNo extends StatelessWidget {
  final Modulo modulo;
  const _ModuloNo({required this.modulo});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cor = p.modulo(modulo.id);
    final caps = modulo.capitulos;
    final feitos = caps.where((c) => AppState.I.capFeito[c.id] ?? false).length;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(11)),
                child: Icon(moduloIcone(modulo.id), color: p.dark ? p.bg : Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modulo.titulo,
                      style: TextStyle(fontFamily: kSerif, fontSize: 22, height: 1.15, color: p.ink),
                    ),
                    Text(
                      '$feitos de ${caps.length} capítulos · ${fmtMin(modulo.minutos)}',
                      style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // tronco da árvore
          Container(
            margin: const EdgeInsets.only(left: 17, top: 6),
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: p.soft(cor, .45), width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (caps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('Capítulos ainda não disponíveis.', style: TextStyle(color: p.inkSoft, fontSize: 13.5)),
                  ),
                for (final c in caps) _CapituloNo(cap: c, cor: cor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CapituloNo extends StatefulWidget {
  final Chapter cap;
  final Color cor;
  const _CapituloNo({required this.cap, required this.cor});
  @override
  State<_CapituloNo> createState() => _CapituloNoState();
}

class _CapituloNoState extends State<_CapituloNo> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = AppState.I;
    final cap = widget.cap;
    final cor = widget.cor;
    final feito = st.capFeito[cap.id] ?? false;
    final pos = st.capPos[cap.id] ?? 0;
    final secoes = [
      for (final b in cap.blocos)
        if (b['tipo'] == 'titulo') b,
    ];
    final prefixo = '${cap.id}#';
    final nDest = st.destaques.where((r) => r.startsWith(prefixo)).length;
    final nNotas =
        st.notas.keys.where((k) => k.startsWith('bloco|$prefixo')).length +
        (st.nota('capitulo', cap.id).isNotEmpty ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Painel(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _aberto = !_aberto),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        feito
                            ? Icons.check_circle_rounded
                            : pos > .02
                            ? Icons.timelapse_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 21,
                        color: feito || pos > .02 ? cor : p.inkFaint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cap. ${cap.ordem} · ${cap.titulo}',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3, color: p.ink),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Selo(nomePrioridade(cap.prioridade), cor: corPrioridade(p, cap.prioridade)),
                              Text(
                                '${fmtMin(cap.minutos)} · ${secoes.length} seções',
                                style: TextStyle(fontSize: 12, color: p.inkSoft),
                              ),
                              if (nDest > 0)
                                Selo(
                                  '$nDest destaque${nDest == 1 ? '' : 's'}',
                                  cor: p.warn,
                                  icone: Icons.border_color_outlined,
                                ),
                              if (nNotas > 0)
                                Selo(
                                  '$nNotas anotaç${nNotas == 1 ? 'ão' : 'ões'}',
                                  cor: p.warn,
                                  icone: Icons.edit_note_rounded,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _aberto ? .5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.expand_more_rounded, color: p.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_aberto
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Divider(height: 1, color: p.line),
                          for (final s in secoes)
                            _Secao(
                              texto: '${s['texto']}',
                              cor: cor,
                              onTap: () => abrir(context, ChapterScreen(chapterId: cap.id, blocoInicial: '${s['id']}')),
                            ),
                          InkWell(
                            onTap: () => abrir(context, ChapterScreen(chapterId: cap.id)),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                              child: Row(
                                children: [
                                  Icon(Icons.menu_book_outlined, size: 18, color: cor),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      feito
                                          ? 'Reler o capítulo'
                                          : pos > .02
                                          ? 'Continuar de onde parou (${(pos * 100).round()}%)'
                                          : 'Abrir o capítulo do início',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cor),
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_rounded, size: 18, color: cor),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  final String texto;
  final Color cor;
  final VoidCallback onTap;
  const _Secao({required this.texto, required this.cor, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MdText(texto, style: TextStyle(fontSize: 14, height: 1.35, color: p.ink)),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
