import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import 'chapter_screen.dart';
import 'mapa_screen.dart';
import 'quadros_screen.dart';

/// Aba "Material": atalhos + os três módulos com seus capítulos.
class MaterialTab extends StatelessWidget {
  const MaterialTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final p = context.pal;
        final st = AppState.I;
        final caps = [for (final m in st.modulos) ...m.capitulos];
        final feitos = caps.where((c) => st.capFeito[c.id] ?? false).length;
        final minutos = caps.fold<int>(0, (a, c) => a + c.minutos);
        final sub = caps.isEmpty
            ? 'Texto organizado por módulo e capítulo'
            : '${caps.length} capítulos · $feitos concluídos · ${fmtMin(minutos)} de leitura';
        return Material(
          color: p.bg,
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 110),
              children: [
                TituloAba('Material', sub: sub),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _Atalho(
                            icone: Icons.compare_arrows_rounded,
                            titulo: 'Quadros comparativos',
                            sub: 'X versus Y, tudo num lugar só',
                            onTap: () => abrir(context, const QuadrosScreen()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Atalho(
                            icone: Icons.account_tree_outlined,
                            titulo: 'Mapa do conteúdo',
                            sub: 'Módulos, capítulos e seções',
                            onTap: () => abrir(context, const MapaScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (st.modulos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: Text(
                      st.pronto
                          ? 'O material ainda não foi carregado. Feche e abra o app de novo.'
                          : 'Carregando o material…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.inkSoft, fontSize: 14.5),
                    ),
                  ),
                for (final m in st.modulos) _SecaoModulo(modulo: m),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Atalho extends StatelessWidget {
  final IconData icone;
  final String titulo, sub;
  final VoidCallback onTap;
  const _Atalho({required this.icone, required this.titulo, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Painel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: p.soft(p.primary, .12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icone, size: 20, color: p.primary),
          ),
          const SizedBox(height: 10),
          Text(
            titulo,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25, color: p.ink),
          ),
          const SizedBox(height: 3),
          Text(sub, style: TextStyle(fontSize: 12.5, height: 1.3, color: p.inkSoft)),
        ],
      ),
    );
  }
}

class _SecaoModulo extends StatelessWidget {
  final Modulo modulo;
  const _SecaoModulo({required this.modulo});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = AppState.I;
    final cor = p.modulo(modulo.id);
    final caps = modulo.capitulos;
    final feitos = caps.where((c) => st.capFeito[c.id] ?? false).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(color: p.soft(cor, .14), borderRadius: BorderRadius.circular(12)),
                child: Icon(moduloIcone(modulo.id), color: cor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modulo.titulo,
                      style: TextStyle(fontFamily: kSerif, fontSize: 24, height: 1.15, color: p.ink),
                    ),
                    if (modulo.subtitulo.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(modulo.subtitulo, style: TextStyle(fontSize: 13.5, height: 1.35, color: p.inkSoft)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Barra(caps.isEmpty ? 0 : feitos / caps.length, cor: cor)),
              const SizedBox(width: 10),
              Text(
                '$feitos/${caps.length} · ${fmtMin(modulo.minutos)}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (caps.isEmpty)
            Painel(
              child: Text(
                'Os capítulos deste módulo ainda não estão disponíveis.',
                style: TextStyle(color: p.inkSoft, fontSize: 14),
              ),
            )
          else
            Painel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < caps.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 60, color: p.line),
                    _LinhaCapitulo(cap: caps[i], cor: cor),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LinhaCapitulo extends StatelessWidget {
  final Chapter cap;
  final Color cor;
  const _LinhaCapitulo({required this.cap, required this.cor});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = AppState.I;
    final feito = st.capFeito[cap.id] ?? false;
    final pos = st.capPos[cap.id] ?? 0;
    final andamento = !feito && pos > .02;
    return InkWell(
      onTap: () => abrir(context, ChapterScreen(chapterId: cap.id)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: feito ? cor : p.soft(cor, .1),
                shape: BoxShape.circle,
                border: andamento ? Border.all(color: cor, width: 1.6) : null,
              ),
              child: feito
                  ? Icon(Icons.check_rounded, size: 18, color: p.dark ? p.bg : Colors.white)
                  : Text(
                      '${cap.ordem}',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cor),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cap.titulo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: feito ? p.inkSoft : p.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(fmtMin(cap.minutos), style: TextStyle(fontSize: 12.5, color: p.inkSoft)),
                      Selo(nomePrioridade(cap.prioridade), cor: corPrioridade(p, cap.prioridade)),
                      if (andamento)
                        Selo('Continuar · ${(pos * 100).round()}%', cor: cor, icone: Icons.play_arrow_rounded),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Icon(Icons.chevron_right_rounded, color: p.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}
