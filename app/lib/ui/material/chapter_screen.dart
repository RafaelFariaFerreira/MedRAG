import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../services/copilot.dart';
import '../../theme.dart';
import '../flashcards/sessao_flash.dart';
import '../questions/sessao_questoes.dart';
import '../widgets/common.dart';
import '../widgets/md.dart';
import 'blocks.dart';

/// Leitor de um capítulo do material.
class ChapterScreen extends StatefulWidget {
  const ChapterScreen({super.key, required this.chapterId, this.blocoInicial});
  final String chapterId;
  final String? blocoInicial;

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends State<ChapterScreen> {
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _progresso = ValueNotifier<double>(0);
  final Map<String, GlobalKey> _chaves = {};
  Timer? _salvar;
  bool _dica = false;
  late final TelaCtx _ctx;

  Chapter? get _cap => AppState.I.capitulos[widget.chapterId];

  @override
  void initState() {
    super.initState();
    blocoSelecionado.value = null;
    final cap = _cap;
    if (cap != null) {
      for (final b in cap.blocos) {
        _chaves['${b['id']}'] = GlobalKey();
      }
    }
    _ctx = TelaCtx(
      cap == null ? 'Material' : '${moduloNome(cap.modulo)} › ${cap.titulo}',
      _textoCtx,
      sugestoes: const [
        'Explique esta seção de outro jeito',
        'Me faça 3 perguntas sobre este capítulo',
        'Qual a pegadinha clássica daqui?',
        'Crie um mnemônico para isto',
      ],
    );
    _scroll.addListener(_aoRolar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restaurar());
    _verDica();
  }

  @override
  void dispose() {
    if (_salvar?.isActive ?? false) {
      _salvar!.cancel();
      AppState.I.marcarCapitulo(widget.chapterId, pos: _progresso.value);
    }
    if (blocoSelecionado.value?.startsWith('${widget.chapterId}#') ?? false) blocoSelecionado.value = null;
    _scroll.dispose();
    _progresso.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ leitura

  Future<void> _verDica() async {
    final v = await Db.meta('dica_material');
    if (!mounted || v != null) return;
    setState(() => _dica = true);
  }

  void _fecharDica() {
    setState(() => _dica = false);
    Db.setMeta('dica_material', '1');
  }

  void _aoRolar() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final max = pos.maxScrollExtent;
    final f = max <= 0 ? 0.0 : (pos.pixels / max).clamp(0.0, 1.0).toDouble();
    _progresso.value = f;
    _salvar?.cancel();
    _salvar = Timer(const Duration(milliseconds: 900), () => AppState.I.marcarCapitulo(widget.chapterId, pos: f));
  }

  String? _topoDe(String id) {
    for (final b in _cap?.blocos ?? const <Json>[]) {
      if (blocoContem(b, id)) return '${b['id']}';
    }
    return null;
  }

  Future<void> _restaurar() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted || !_scroll.hasClients) return;
    final alvo = widget.blocoInicial;
    if (alvo != null) {
      final topo = _topoDe(alvo);
      final ctx = topo == null ? null : _chaves[topo]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: .04,
        );
        return;
      }
    }
    final f = AppState.I.capPos[widget.chapterId] ?? 0;
    if (f > .01) _scroll.jumpTo(f * _scroll.position.maxScrollExtent);
  }

  void _irPara(String id) {
    final ctx = _chaves[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: .04,
    );
  }

  /// Blocos do topo que estão visíveis agora + título da seção em que ela está.
  ({List<Json> blocos, String? secao}) _visiveis() {
    final cap = _cap;
    final vp = _viewportKey.currentContext?.findRenderObject();
    if (cap == null || vp is! RenderBox || !vp.attached || !vp.hasSize) return (blocos: const [], secao: null);
    final topo = vp.localToGlobal(Offset.zero).dy;
    final base = topo + vp.size.height;
    final vis = <Json>[];
    String? secao;
    String? ultimoTitulo;
    for (final b in cap.blocos) {
      final ro = _chaves['${b['id']}']?.currentContext?.findRenderObject();
      if (b['tipo'] == 'titulo' && vis.isEmpty) ultimoTitulo = '${b['texto']}';
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final y = ro.localToGlobal(Offset.zero).dy;
      final h = ro.size.height;
      if (y + h > topo && y < base) {
        if (vis.isEmpty) secao = ultimoTitulo;
        vis.add(b);
      } else if (vis.isNotEmpty) {
        break;
      }
    }
    return (blocos: vis, secao: secao);
  }

  String _textoCtx() {
    final cap = _cap;
    if (cap == null) return '';
    final b = StringBuffer()
      ..writeln('Capítulo: ${cap.titulo} (módulo ${moduloNome(cap.modulo)}, cap. ${cap.ordem})')
      ..writeln('Resumo: ${cap.resumo}');
    if (cap.objetivos.isNotEmpty) b.writeln('Objetivos: ${cap.objetivos.join('; ')}');
    final v = _visiveis();
    if (v.blocos.isNotEmpty) {
      b.writeln();
      b.writeln('[O QUE ELA ESTÁ VENDO AGORA NA TELA — seção: ${v.secao ?? 'abertura do capítulo'}]');
      for (final x in v.blocos) {
        final t = textoPlano(x);
        if (t.isNotEmpty) b.writeln(t);
      }
    }
    b.writeln();
    b.writeln('[CAPÍTULO COMPLETO]');
    for (final x in cap.blocos) {
      final t = textoPlano(x);
      if (t.isNotEmpty) b.writeln(t);
    }
    return b.toString();
  }

  // ------------------------------------------------------------ ações

  void _fonte(double delta) {
    final atual = AppState.I.escalaTexto;
    final v = (((atual + delta) * 100).round() / 100).clamp(.85, 1.4).toDouble();
    if (v == atual) return;
    AppState.I.setPref('escala_texto', v.toStringAsFixed(2));
  }

  void _marcar(bool feito, {bool avisar = true}) {
    AppState.I.marcarCapitulo(widget.chapterId, feito: feito);
    if (!avisar) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(feito ? 'Capítulo concluído. Bom trabalho!' : 'Capítulo marcado como não concluído.'),
        action: feito ? SnackBarAction(label: 'Desfazer', onPressed: () => _marcar(false, avisar: false)) : null,
      ),
    );
  }

  Chapter? _proximo(Chapter cap) {
    final todos = [for (final m in AppState.I.modulos) ...m.capitulos];
    final i = todos.indexWhere((c) => c.id == cap.id);
    return i >= 0 && i + 1 < todos.length ? todos[i + 1] : null;
  }

  List<Flashcard> _cartoes(Chapter cap) {
    final doCap = AppState.I.cartoes.where((c) => c.capitulo == cap.id).toList();
    return doCap.isNotEmpty ? doCap : AppState.I.cartoes.where((c) => c.modulo == cap.modulo).toList();
  }

  void _aviso(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  void _secoes(Chapter cap, Color cor) {
    final titulos = [
      for (final b in cap.blocos)
        if (b['tipo'] == 'titulo') b,
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final p = ctx.pal;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  'Seções do capítulo',
                  style: TextStyle(fontFamily: kSerif, fontSize: 22, color: p.ink),
                ),
              ),
              if (titulos.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Este capítulo não tem seções marcadas.', style: TextStyle(color: p.inkSoft)),
                ),
              for (final t in titulos)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(Icons.subdirectory_arrow_right_rounded, color: cor),
                  title: MdText('${t['texto']}', style: const TextStyle(fontSize: 15, height: 1.35)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _irPara('${t['id']}');
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final cap = _cap;
    if (cap == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não encontrei este capítulo.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => Navigator.maybePop(context), child: const Text('Voltar ao material')),
              ],
            ),
          ),
        ),
      );
    }
    return CtxCopiloto(
      ctx: _ctx,
      child: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final p = context.pal;
          final cor = p.modulo(cap.modulo);
          final e = AppState.I.escalaTexto;
          final feito = AppState.I.capFeito[cap.id] ?? false;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Text(
                '${moduloNome(cap.modulo)} · Cap. ${cap.ordem}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                _BotaoFonte(
                  rotulo: 'A−',
                  tamanho: 14,
                  ativo: e > .85,
                  onTap: () => _fonte(-.1),
                  dica: 'Diminuir texto',
                ),
                _BotaoFonte(rotulo: 'A+', tamanho: 18, ativo: e < 1.4, onTap: () => _fonte(.1), dica: 'Aumentar texto'),
                PopupMenuButton<String>(
                  tooltip: 'Mais opções',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) => switch (v) {
                    'feito' => _marcar(!feito),
                    'secoes' => _secoes(cap, cor),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'feito',
                      child: Row(
                        children: [
                          Icon(feito ? Icons.radio_button_unchecked : Icons.check_circle_outline, size: 20),
                          const SizedBox(width: 10),
                          Text(feito ? 'Marcar como não concluído' : 'Marcar como concluído'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'secoes',
                      child: Row(
                        children: [Icon(Icons.toc_rounded, size: 20), SizedBox(width: 10), Text('Ir para uma seção')],
                      ),
                    ),
                  ],
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: ValueListenableBuilder<double>(
                  valueListenable: _progresso,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 3,
                    backgroundColor: p.soft(cor, .12),
                    valueColor: AlwaysStoppedAnimation(cor),
                  ),
                ),
              ),
            ),
            body: SingleChildScrollView(
              key: _viewportKey,
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(10, 6, 10, 40 + MediaQuery.paddingOf(context).bottom),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cabecalho(p, cap, cor, e, feito),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.topCenter,
                        child: _dica ? _dicaToque(p, cor) : const SizedBox(width: double.infinity),
                      ),
                      const SizedBox(height: 4),
                      for (final b in cap.blocos)
                        BlockView(
                          key: _chaves['${b['id']}'],
                          bloco: b,
                          capId: cap.id,
                          cor: cor,
                          alvo: widget.blocoInicial,
                        ),
                      _rodape(p, cap, cor, feito),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cabecalho(Pal p, Chapter cap, Color cor, double e, bool feito) {
    final pr = cap.prioridade;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Selo(moduloNome(cap.modulo), cor: cor, icone: moduloIcone(cap.modulo)),
              Selo('Capítulo ${cap.ordem}', cor: p.inkSoft),
              if (feito) Selo('Concluído', cor: cor, icone: Icons.check_rounded, cheio: true),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            cap.titulo,
            style: TextStyle(fontFamily: kSerif, fontSize: 29 * e, height: 1.12, color: p.ink),
          ),
          if (cap.resumo.isNotEmpty) ...[
            const SizedBox(height: 10),
            MdText(
              cap.resumo,
              style: TextStyle(fontSize: 16 * e, height: 1.45, color: p.inkSoft),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 16, color: p.inkSoft),
                  const SizedBox(width: 4),
                  Text('${fmtMin(cap.minutos)} de leitura', style: TextStyle(fontSize: 13, color: p.inkSoft)),
                ],
              ),
              Selo(nomePrioridade(pr), cor: corPrioridade(p, pr), icone: Icons.local_fire_department_outlined),
            ],
          ),
          if (cap.objetivos.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: p.soft(cor, .07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.soft(cor, .25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Rotulo('Você vai sair daqui sabendo', cor: cor),
                  const SizedBox(height: 8),
                  for (final o in cap.objetivos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(Icons.arrow_right_alt_rounded, size: 18, color: cor),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: MdText(o, style: TextStyle(fontSize: 14.5 * e, height: 1.45)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dicaToque(Pal p, Color cor) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_outlined, size: 20, color: p.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Toque em qualquer trecho para anotar, destacar ou perguntar ao copiloto.',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink),
            ),
          ),
          IconButton(
            tooltip: 'Entendi',
            icon: Icon(Icons.close_rounded, size: 20, color: p.inkSoft),
            onPressed: _fecharDica,
          ),
        ],
      ),
    ),
  );

  Widget _rodape(Pal p, Chapter cap, Color cor, bool feito) {
    final prox = _proximo(cap);
    final questoes = AppState.I.questoesDoTopicos(cap.topicos);
    final cartoes = _cartoes(cap);
    final fg = p.dark ? p.bg : Colors.white;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: p.line, height: 1),
          const SizedBox(height: 20),
          CampoNota(
            kind: 'capitulo',
            ref: cap.id,
            rotulo: 'Minhas anotações do capítulo',
            dica: 'O que ficou, o que confundiu, o que revisar…',
            minLinhas: 3,
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: feito
                ? Container(
                    key: const ValueKey('feito'),
                    constraints: const BoxConstraints(minHeight: 50),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: p.soft(cor, .12), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, color: cor, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Capítulo concluído',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cor),
                          ),
                        ),
                      ],
                    ),
                  )
                : FilledButton.icon(
                    key: const ValueKey('concluir'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cor,
                      foregroundColor: fg,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () => _marcar(true),
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text('Concluir capítulo'),
                  ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft),
            onPressed: () => questoes.isEmpty
                ? _aviso('Ainda não há questões de prova com os temas deste capítulo.')
                : abrir(context, SessaoQuestoes(titulo: cap.titulo, questoes: questoes)),
            icon: Icon(Icons.quiz_outlined, color: cor),
            label: Text(
              'Praticar questões deste tema${questoes.isEmpty ? '' : ' (${questoes.length})'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft),
            onPressed: () => cartoes.isEmpty
                ? _aviso('Ainda não há flashcards deste módulo.')
                : abrir(context, SessaoFlash(titulo: 'Flashcards · ${cap.titulo}', cartoes: cartoes)),
            icon: Icon(Icons.style_outlined, color: cor),
            label: Text(
              'Flashcards deste capítulo${cartoes.isEmpty ? '' : ' (${cartoes.length})'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (prox != null) ...[
            const SizedBox(height: 22),
            Painel(
              onTap: () =>
                  Navigator.of(context)
                      .pushReplacement(MaterialPageRoute(builder: (_) => ChapterScreen(chapterId: prox.id))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Rotulo('Próximo capítulo', cor: p.modulo(prox.modulo)),
                        const SizedBox(height: 6),
                        Text(
                          prox.titulo,
                          style: TextStyle(fontFamily: kSerif, fontSize: 19, height: 1.2, color: p.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${moduloNome(prox.modulo)} · ${fmtMin(prox.minutos)}',
                          style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.arrow_forward_rounded, color: p.modulo(prox.modulo)),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 22),
            Center(
              child: Text('Você chegou ao fim do material.', style: TextStyle(fontSize: 13.5, color: p.inkSoft)),
            ),
          ],
        ],
      ),
    );
  }
}

class _BotaoFonte extends StatelessWidget {
  final String rotulo, dica;
  final double tamanho;
  final bool ativo;
  final VoidCallback onTap;
  const _BotaoFonte({
    required this.rotulo,
    required this.tamanho,
    required this.ativo,
    required this.onTap,
    required this.dica,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: dica,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: ativo ? onTap : null,
        child: SizedBox(
          width: 42,
          height: 44,
          child: Center(
            child: Text(
              rotulo,
              style: TextStyle(fontFamily: kSerif, fontSize: tamanho, color: ativo ? p.ink : p.inkFaint),
            ),
          ),
        ),
      ),
    );
  }
}
