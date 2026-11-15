import 'package:material_ui/material_ui.dart';

import '../../theme.dart';
import '../material/quadros_screen.dart';
import '../widgets/common.dart';
import 'anotacoes_screen.dart';
import 'busca_screen.dart';
import 'config_screen.dart';
import 'raiox_screen.dart';

class MaisTab extends StatelessWidget {
  const MaisTab({super.key});

  @override
  Widget build(BuildContext context) {
    final itens = <(IconData, String, String, Widget Function())>[
      (Icons.insights_outlined, 'Raio-X da prova', 'O que mais caiu nas provas antigas e o que se repete',
          () => const RaioXScreen()),
      (Icons.table_chart_outlined, 'Quadros comparativos', 'Todas as tabelas lado a lado, num lugar só',
          () => const QuadrosScreen()),
      (Icons.edit_note_rounded, 'Minhas anotações', 'Tudo o que você anotou e destacou',
          () => const AnotacoesScreen()),
      (Icons.search_rounded, 'Busca', 'Procurar em capítulos, questões e flashcards', () => const BuscaScreen()),
      (Icons.tune_rounded, 'Configurações', 'Nome, tema, tamanho do texto, copiloto e créditos',
          () => const ConfigScreen()),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        const TituloAba('Mais'),
        const SizedBox(height: 4),
        for (final it in itens)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _Entrada(icone: it.$1, titulo: it.$2, descricao: it.$3, onTap: () => abrir(context, it.$4())),
          ),
      ],
    );
  }
}

class _Entrada extends StatelessWidget {
  final IconData icone;
  final String titulo, descricao;
  final VoidCallback onTap;
  const _Entrada({required this.icone, required this.titulo, required this.descricao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Painel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: p.soft(p.primary), borderRadius: BorderRadius.circular(12)),
          child: Icon(icone, size: 21, color: p.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 2),
            Text(descricao,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: p.inkSoft)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: p.inkFaint),
      ]),
    );
  }
}
