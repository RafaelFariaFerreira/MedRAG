import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../../app_keys.dart';
import '../../data/app_state.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../services/claude.dart';
import '../../services/copilot.dart';
import '../../theme.dart';
import '../more/config_screen.dart';
import '../widgets/md.dart';

/// Sinaliza (para o balão) que a folha está aberta.
final _aberto = ValueNotifier<bool>(false);

/// Pedido feito enquanto a folha já está aberta (ex.: outra ação pediu um rascunho).
final _pedido = ValueNotifier<({String texto, bool enviar})?>(null);

/// Abre o copiloto por cima da tela atual.
Future<void> abrirCopiloto({String? rascunho, bool enviarJa = false}) async {
  if (_aberto.value) {
    if (rascunho != null) _pedido.value = (texto: rascunho, enviar: enviarJa);
    return;
  }
  final ctx = navKey.currentContext;
  if (ctx == null) return;
  final inicial = rascunho ?? (Copiloto.I.rascunho.isNotEmpty ? Copiloto.I.rascunho : null);
  Copiloto.I.rascunho = '';
  _aberto.value = true;
  Copiloto.I.aberto = true;
  final p = ctx.pal;
  try {
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: (p.dark ? Colors.black : const Color(0xFF1C1B1A)).withValues(alpha: p.dark ? .35 : .16),
      builder: (_) => _Folha(rascunho: inicial, enviarJa: enviarJa && inicial != null),
    );
  } finally {
    _aberto.value = false;
    Copiloto.I.aberto = false;
  }
}

// ====================================================================== balão

/// Balão flutuante do copiloto minimizado. Vai no `builder` do MaterialApp, por cima do Navigator.
class BalaoCopiloto extends StatefulWidget {
  const BalaoCopiloto({super.key});
  @override
  State<BalaoCopiloto> createState() => _BalaoCopilotoState();
}

class _BalaoCopilotoState extends State<BalaoCopiloto> with SingleTickerProviderStateMixin {
  static const _tam = 52.0;
  double? _bottom; // distância da borda inferior (null = posição padrão)
  late final AnimationController _pulso =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final teclado = mq.viewInsets.bottom > 0;
    final padrao = mq.padding.bottom + 66 + 14; // acima da barra de navegação
    final minB = mq.padding.bottom + 12;
    final maxB = (mq.size.height - mq.padding.top - _tam - 24).clamp(minB, double.infinity);
    final bottom = (_bottom ?? padrao).clamp(minB, maxB);

    return ListenableBuilder(
      listenable: Listenable.merge([Copiloto.I, AppState.I, _aberto]),
      builder: (context, _) {
        final p = context.pal;
        final ocupado = Copiloto.I.ocupado;
        if (ocupado && !_pulso.isAnimating) {
          _pulso.repeat(reverse: true);
        } else if (!ocupado && _pulso.isAnimating) {
          _pulso.stop();
        }
        final visivel = !teclado && !_aberto.value && AppState.I.pronto && AppState.I.nome.isNotEmpty;
        return Stack(children: [
          Positioned(
            right: 16,
            bottom: bottom,
            child: IgnorePointer(
              ignoring: !visivel,
              child: AnimatedOpacity(
                opacity: visivel ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: AnimatedScale(
                  scale: visivel ? 1 : .8,
                  duration: const Duration(milliseconds: 180),
                  child: GestureDetector(
                    onVerticalDragUpdate: (d) => setState(() => _bottom = (bottom - d.delta.dy).clamp(minB, maxB)),
                    child: Semantics(
                      button: true,
                      label: 'Abrir o copiloto',
                      child: Material(
                        color: p.dark ? p.surfaceAlt : p.ink,
                        elevation: 3,
                        shadowColor: Colors.black.withValues(alpha: .25),
                        shape: const StadiumBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => abrirCopiloto(),
                          child: SizedBox(
                            width: _tam,
                            height: _tam,
                            child: Stack(alignment: Alignment.center, children: [
                              Icon(Icons.auto_awesome_outlined, size: 23, color: p.dark ? p.primary : p.bg),
                              if (ocupado)
                                Positioned(
                                  top: 11,
                                  right: 11,
                                  child: FadeTransition(
                                    opacity: Tween(begin: .35, end: 1.0).animate(_pulso),
                                    child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: p.dark ? p.primary : const Color(0xFF7FD1BE),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

// ====================================================================== folha

class _Folha extends StatefulWidget {
  final String? rascunho;
  final bool enviarJa;
  const _Folha({this.rascunho, this.enviarJa = false});
  @override
  State<_Folha> createState() => _FolhaState();
}

class _FolhaState extends State<_Folha> {
  final _campo = TextEditingController();
  final _foco = FocusNode();
  bool _usarCtx = true;
  bool _seguir = true;
  ScrollController? _sc;

  @override
  void initState() {
    super.initState();
    Copiloto.I.addListener(_mudou);
    _pedido.addListener(_novoPedido);
    if (widget.rascunho != null) {
      _campo.text = widget.rascunho!;
      if (widget.enviarJa) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _enviar());
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _foco.requestFocus();
        });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _irProFim());
  }

  @override
  void dispose() {
    Copiloto.I.removeListener(_mudou);
    _pedido.removeListener(_novoPedido);
    _campo.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _novoPedido() {
    final r = _pedido.value;
    if (r == null || !mounted) return;
    _pedido.value = null;
    _campo.text = r.texto;
    if (r.enviar) {
      _enviar();
    } else {
      _foco.requestFocus();
    }
  }

  void _mudou() {
    if (!mounted) return;
    if (_seguir) WidgetsBinding.instance.addPostFrameCallback((_) => _irProFim());
  }

  void _irProFim({bool animar = false}) {
    final sc = _sc;
    if (!mounted || sc == null || !sc.hasClients) return;
    final max = sc.position.maxScrollExtent;
    if (animar) {
      sc.animateTo(max, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      sc.jumpTo(max);
    }
  }

  Future<void> _enviar([String? texto]) async {
    final t = (texto ?? _campo.text).trim();
    if (t.isEmpty || Copiloto.I.ocupado) return;
    if (texto == null) _campo.clear();
    _seguir = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _irProFim(animar: true));
    await Copiloto.I.enviar(t, usarContexto: _usarCtx);
  }

  Future<void> _tentarDeNovo(ChatMsg erro) async {
    final c = Copiloto.I;
    if (c.ocupado) return;
    final i = c.msgs.indexOf(erro);
    if (i < 1 || c.msgs[i - 1].role != 'user') return;
    final pergunta = c.msgs[i - 1].texto;
    c.msgs.removeRange(i - 1, i + 1);
    try {
      // a pergunta original já foi gravada; evita duplicá-la no histórico salvo
      await Db.db.rawDelete(
          "DELETE FROM chat WHERE id = (SELECT MAX(id) FROM chat WHERE role = 'user' AND texto = ?)", [pergunta]);
    } catch (_) {}
    await _enviar(pergunta);
  }

  Future<void> _limpar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Limpar a conversa?'),
        content: const Text('As mensagens com o copiloto serão apagadas. Suas anotações não são afetadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Limpar')),
        ],
      ),
    );
    if (ok == true) await Copiloto.I.limpar();
  }

  void _abrirConfig() {
    Navigator.of(context).pop();
    navKey.currentState?.push(MaterialPageRoute(builder: (_) => const ConfigScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .45,
        maxChildSize: .96,
        snap: true,
        snapSizes: const [.78],
        builder: (context, sc) {
          _sc = sc;
          return Container(
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(top: BorderSide(color: p.line)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListenableBuilder(
              listenable: Listenable.merge([Copiloto.I, AppState.I]),
              builder: (context, _) {
                final c = Copiloto.I;
                return Column(children: [
                  _cabecalho(p, c),
                  Divider(height: 1, color: p.line),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollUpdateNotification && n.dragDetails != null) {
                          _seguir = n.metrics.pixels >= n.metrics.maxScrollExtent - 48;
                        }
                        return false;
                      },
                      child: c.msgs.isEmpty ? _vazio(p, c, sc) : _lista(p, c, sc),
                    ),
                  ),
                  if (!Claude.temChave) _avisoChave(p),
                  _entrada(p, c),
                ]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _cabecalho(Pal p, Copiloto c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 10),
      child: Column(children: [
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(99)),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.auto_awesome_outlined, size: 20, color: p.primary),
          const SizedBox(width: 8),
          Text('Copiloto', style: TextStyle(fontFamily: kSerif, fontSize: 24, height: 1.1, color: p.ink)),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Opções',
            icon: Icon(Icons.more_vert_rounded, color: p.inkSoft),
            onSelected: (v) {
              if (v == 'limpar') _limpar();
              if (v == 'config') _abrirConfig();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'limpar', enabled: c.msgs.isNotEmpty, child: const Text('Limpar conversa')),
              const PopupMenuItem(value: 'config', child: Text('Configurações')),
            ],
          ),
          IconButton(
            tooltip: 'Minimizar',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.inkSoft),
          ),
        ]),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(left: 12, right: 2),
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: _usarCtx ? p.soft(p.primary) : p.surfaceAlt,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(children: [
            Icon(_usarCtx ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 16, color: _usarCtx ? p.primary : p.inkFaint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _usarCtx ? 'Vendo: ${c.tela.rotulo}' : 'Sem olhar a tela',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _usarCtx ? p.primary : p.inkSoft),
              ),
            ),
            Transform.scale(
              scale: .78,
              child: Switch(
                value: _usarCtx,
                onChanged: (v) => setState(() => _usarCtx = v),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _vazio(Pal p, Copiloto c, ScrollController sc) {
    final nome = AppState.I.nome.trim();
    final sug = c.tela.sugestoes.isNotEmpty ? c.tela.sugestoes : TelaCtx.vazio.sugestoes;
    return ListView(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      children: [
        Text(nome.isEmpty ? 'Oi! No que eu te ajudo?' : 'Oi, $nome. No que eu te ajudo?',
            style: TextStyle(fontFamily: kSerif, fontSize: 24, height: 1.2, color: p.ink)),
        const SizedBox(height: 8),
        Text(
          'Respondo com base no resumo das aulas e nas provas antigas, e sei o que está na sua tela '
          '— dá para perguntar "explica isso de outro jeito".',
          style: TextStyle(fontSize: 14.5, height: 1.5, color: p.inkSoft),
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in sug)
            ActionChip(
              label: Text(s, style: TextStyle(fontSize: 13.5, color: p.ink)),
              avatar: Icon(Icons.north_east_rounded, size: 15, color: p.primary),
              backgroundColor: p.surface,
              side: BorderSide(color: p.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onPressed: Claude.temChave ? () => _enviar(s) : null,
            ),
        ]),
      ],
    );
  }

  Widget _lista(Pal p, Copiloto c, ScrollController sc) {
    return ListView.builder(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      itemCount: c.msgs.length,
      itemBuilder: (context, i) {
        final m = c.msgs[i];
        return m.role == 'user'
            ? _MsgDela(msg: m)
            : _MsgCopiloto(msg: m, onTentar: () => _tentarDeNovo(m), ultima: i == c.msgs.length - 1);
      },
    );
  }

  Widget _avisoChave(Pal p) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(color: p.soft(p.warn), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.key_off_outlined, size: 18, color: p.warn),
        const SizedBox(width: 8),
        Expanded(
          child: Text('O copiloto precisa de uma chave da API para responder.',
              style: TextStyle(fontSize: 13, height: 1.35, color: p.ink)),
        ),
        TextButton(onPressed: _abrirConfig, child: const Text('Configurar')),
      ]),
    );
  }

  Widget _entrada(Pal p, Copiloto c) {
    final ocupado = c.ocupado;
    final bottomSafe = MediaQuery.viewInsetsOf(context).bottom > 0 ? 0.0 : MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 8, 8 + bottomSafe),
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _campo,
            focusNode: _foco,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            style: TextStyle(fontSize: 15, height: 1.4, color: p.ink),
            decoration: InputDecoration(
              hintText: 'Pergunte ao copiloto…',
              fillColor: p.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.line)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.line)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.primary, width: 1.4)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ocupado
              ? IconButton.filledTonal(
                  tooltip: 'Parar',
                  onPressed: c.parar,
                  icon: const Icon(Icons.stop_rounded),
                  style: IconButton.styleFrom(minimumSize: const Size(46, 46)),
                )
              : ListenableBuilder(
                  listenable: _campo,
                  builder: (context, _) => IconButton.filled(
                    tooltip: 'Enviar',
                    onPressed: _campo.text.trim().isEmpty ? null : () => _enviar(),
                    icon: const Icon(Icons.arrow_upward_rounded),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(46, 46),
                      backgroundColor: p.primary,
                      foregroundColor: p.onPrimary,
                      disabledBackgroundColor: p.surfaceAlt,
                      disabledForegroundColor: p.inkFaint,
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

// ====================================================================== mensagens

class _MsgDela extends StatelessWidget {
  final ChatMsg msg;
  const _MsgDela({required this.msg});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (msg.contexto.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 3, right: 4),
            child: Text('em ${msg.contexto}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: p.inkFaint)),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.soft(p.primary, .14),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: SelectableText(msg.texto, style: TextStyle(fontSize: 15, height: 1.45, color: p.ink)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MsgCopiloto extends StatelessWidget {
  final ChatMsg msg;
  final VoidCallback onTentar;
  final bool ultima;
  const _MsgCopiloto({required this.msg, required this.onTentar, required this.ultima});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (msg.erro) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
        decoration: BoxDecoration(
          color: p.soft(p.bad),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.soft(p.bad, .3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline_rounded, size: 18, color: p.bad),
            const SizedBox(width: 8),
            Expanded(child: Text(msg.texto, style: TextStyle(fontSize: 14, height: 1.45, color: p.ink))),
          ]),
          if (ultima)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onTentar,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar de novo'),
                style: TextButton.styleFrom(foregroundColor: p.bad),
              ),
            ),
        ]),
      );
    }
    if (msg.streaming && msg.texto.isEmpty) {
      return const Padding(padding: EdgeInsets.only(bottom: 16), child: _Pensando());
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_outlined, size: 14, color: p.primary),
          const SizedBox(width: 5),
          Text('Copiloto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.primary)),
        ]),
        const SizedBox(height: 6),
        SelectionArea(child: MdView(msg.texto, fontSize: 15)),
        if (msg.streaming)
          const _Cursor()
        else
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: msg.fontes.isEmpty
                  ? const SizedBox.shrink()
                  : Text('Fontes: ${msg.fontes.join(' · ')}',
                      style: TextStyle(fontSize: 12, height: 1.35, color: p.inkFaint)),
            ),
            _BotaoCopiar(texto: msg.texto),
          ]),
      ]),
    );
  }
}

class _Pensando extends StatefulWidget {
  const _Pensando();
  @override
  State<_Pensando> createState() => _PensandoState();
}

class _PensandoState extends State<_Pensando> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(children: [
      Icon(Icons.auto_awesome_outlined, size: 14, color: p.primary),
      const SizedBox(width: 8),
      AnimatedBuilder(
        animation: _a,
        builder: (context, _) => Row(children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Opacity(
                opacity: () {
                  final t = (_a.value * 3 - i) % 3;
                  return t < 1 ? .35 + .65 * (1 - (t - .5).abs() * 2).clamp(0.0, 1.0) : .35;
                }(),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(width: 4),
      Text('pensando…', style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, color: p.inkSoft)),
    ]);
  }
}

class _Cursor extends StatefulWidget {
  const _Cursor();
  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return FadeTransition(
      opacity: Tween(begin: .15, end: .8).animate(_a),
      child: Container(
        width: 8,
        height: 16,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}

class _BotaoCopiar extends StatefulWidget {
  final String texto;
  const _BotaoCopiar({required this.texto});
  @override
  State<_BotaoCopiar> createState() => _BotaoCopiarState();
}

class _BotaoCopiarState extends State<_BotaoCopiar> {
  bool _copiado = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return IconButton(
      tooltip: _copiado ? 'Copiado' : 'Copiar',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      color: _copiado ? p.ok : p.inkFaint,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.texto));
        if (!mounted) return;
        setState(() => _copiado = true);
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (mounted) setState(() => _copiado = false);
      },
      icon: Icon(_copiado ? Icons.check_rounded : Icons.copy_rounded),
    );
  }
}
