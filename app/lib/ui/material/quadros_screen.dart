import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/copilot.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import 'blocks.dart';
import 'chapter_screen.dart';

/// Todos os quadros comparativos (e as demais tabelas) do material, num lugar só.
class QuadrosScreen extends StatelessWidget {
  const QuadrosScreen({super.key});
  @override
  Widget build(BuildContext context) => const _Quadros();
}

class _Quadro {
  final Chapter cap;
  final Json bloco;
  final String busca;
  _Quadro(this.cap, this.bloco) : busca = _normalizar(textoPlano(bloco));
  bool get comparacao => bloco['comparacao'] == true;
  String get titulo => '${bloco['titulo'] ?? ''}';
}

String _normalizar(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString();
}

class _Quadros extends StatefulWidget {
  const _Quadros();
  @override
  State<_Quadros> createState() => _QuadrosState();
}

class _QuadrosState extends State<_Quadros> {
  String? _modulo; // null = todos
  String _busca = '';
  final _buscaCtl = TextEditingController();
  late final List<_Quadro> _todos = [
    for (final m in AppState.I.modulos)
      for (final c in m.capitulos)
        for (final b in c.todosBlocos)
          if (b['tipo'] == 'tabela') _Quadro(c, b),
  ];
  late final TelaCtx _ctx = TelaCtx(
    'Material › Quadros comparativos',
    () {
      final vis = _filtrados();
      final b = StringBuffer(
        'Quadros comparativos do material'
        '${_modulo == null ? '' : ' (filtro: ${moduloNome(_modulo!)})'}'
        '${_busca.isEmpty ? '' : ' — busca: "$_busca"'}\n',
      );
      b.writeln('Títulos: ${vis.map((q) => q.titulo).join(' · ')}\n');
      for (final q in vis) {
        b.writeln('[${moduloNome(q.cap.modulo)} › ${q.cap.titulo}]');
        b.writeln(textoPlano(q.bloco));
        b.writeln();
      }
      return b.toString();
    },
    sugestoes: const [
      'Quais desses quadros mais caem na prova?',
      'Me teste com um "X versus Y" daqui',
      'Faça um quadro único dos marcadores de IHQ',
    ],
  );

  @override
  void dispose() {
    _buscaCtl.dispose();
    super.dispose();
  }

  List<_Quadro> _filtrados() {
    const ignorar = {'x', 'vs', 'vs.', 'versus', 'e', 'de', 'do', 'da'};
    final termos = _normalizar(_busca)
        .split(RegExp(r'[\s×/,;]+'))
        .where((t) => t.isNotEmpty && !ignorar.contains(t))
        .toList();
    return [
      for (final q in _todos)
        if ((_modulo == null || q.cap.modulo == _modulo) && termos.every(q.busca.contains)) q,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final lista = _filtrados();
    final mods = [
      for (final m in AppState.I.modulos)
        if (_todos.any((q) => q.cap.modulo == m.id)) m,
    ];

    // monta a lista: por módulo, comparativos primeiro e depois as demais tabelas
    final itens = <Widget>[];
    for (final m in mods) {
      final doMod = lista.where((q) => q.cap.modulo == m.id).toList();
      if (doMod.isEmpty) continue;
      final cor = p.modulo(m.id);
      final comp = doMod.where((q) => q.comparacao).toList();
      final outras = doMod.where((q) => !q.comparacao).toList();
      itens.add(_CabecalhoModulo(titulo: m.titulo, cor: cor, n: doMod.length, icone: moduloIcone(m.id)));
      for (final q in comp) {
        itens.add(_ItemQuadro(q: q, cor: cor));
      }
      if (outras.isNotEmpty) {
        itens.add(
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 6), child: Rotulo('Outras tabelas de ${m.titulo}')),
        );
        for (final q in outras) {
          itens.add(_ItemQuadro(q: q, cor: cor));
        }
      }
    }

    return CtxCopiloto(
      ctx: _ctx,
      child: Scaffold(
        appBar: AppBar(title: const Text('Quadros comparativos')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _buscaCtl,
                onChanged: (v) => setState(() => _busca = v.trim()),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar: Graves, Burkitt, CD30, PAAF…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _busca.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar busca',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _buscaCtl.clear();
                            setState(() => _busca = '');
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _Chip(
                    rotulo: 'Todos',
                    ativo: _modulo == null,
                    cor: p.primary,
                    onTap: () => setState(() => _modulo = null),
                  ),
                  for (final m in mods)
                    _Chip(
                      rotulo: m.titulo,
                      ativo: _modulo == m.id,
                      cor: p.modulo(m.id),
                      onTap: () => setState(() => _modulo = _modulo == m.id ? null : m.id),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: p.line),
            Expanded(
              child: itens.isEmpty
                  ? _Vazio(
                      semConteudo: _todos.isEmpty,
                      onLimpar: () {
                        _buscaCtl.clear();
                        setState(() {
                          _busca = '';
                          _modulo = null;
                        });
                      },
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
                      itemCount: itens.length + 1,
                      itemBuilder: (_, i) => i == 0
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: Text(
                                '${lista.length} ${lista.length == 1 ? 'tabela' : 'tabelas'} · '
                                '${lista.where((q) => q.comparacao).length} comparativas',
                                style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                              ),
                            )
                          : itens[i - 1],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String rotulo;
  final bool ativo;
  final Color cor;
  final VoidCallback onTap;
  const _Chip({required this.rotulo, required this.ativo, required this.cor, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: Material(
        color: ativo ? p.soft(cor, .16) : p.surface,
        shape: StadiumBorder(side: BorderSide(color: ativo ? cor : p.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                rotulo,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                  color: ativo ? cor : p.inkSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CabecalhoModulo extends StatelessWidget {
  final String titulo;
  final Color cor;
  final int n;
  final IconData icone;
  const _CabecalhoModulo({required this.titulo, required this.cor, required this.n, required this.icone});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
      child: Row(
        children: [
          Icon(icone, color: cor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(fontFamily: kSerif, fontSize: 24, color: p.ink),
            ),
          ),
          Text(
            '$n',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cor),
          ),
        ],
      ),
    );
  }
}

class _ItemQuadro extends StatelessWidget {
  final _Quadro q;
  final Color cor;
  const _ItemQuadro({required this.q, required this.cor});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Cap. ${q.cap.ordem} · ${q.cap.titulo}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.inkSoft, fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: cor,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => abrir(context, ChapterScreen(chapterId: q.cap.id, blocoInicial: '${q.bloco['id']}')),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('abrir no capítulo'),
                ),
              ],
            ),
          ),
          BlockView(bloco: q.bloco, capId: q.cap.id, cor: cor),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  final bool semConteudo;
  final VoidCallback onLimpar;
  const _Vazio({required this.semConteudo, required this.onLimpar});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined, size: 40, color: p.inkFaint),
            const SizedBox(height: 12),
            Text(
              semConteudo
                  ? 'Os quadros aparecem aqui assim que o material estiver carregado.'
                  : 'Nenhum quadro com esses termos. Tente uma palavra só (ex.: "Hashimoto").',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.45, color: p.inkSoft),
            ),
            if (!semConteudo) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onLimpar, child: const Text('Limpar filtros')),
            ],
          ],
        ),
      ),
    );
  }
}
