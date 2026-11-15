import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/copilot.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import '../widgets/md.dart';

// =====================================================================================
// Filas de revisão (usadas também pela aba)
// =====================================================================================

/// Mesmos intervalos de AppState.avaliarCartao (em minutos), para mostrar nos botões.
const intervalosFlashMin = [1, 10, 40, 150, 480, 1440];

int proximaCaixa(FlashState? s, int rating) {
  final box = s?.box ?? 0;
  if (rating == 0) return 0;
  if (rating == 1) return box.clamp(1, 5);
  return (box + (rating == 3 ? 2 : 1)).clamp(1, 5);
}

/// Alterna os módulos (tireoide, linfadenopatias, linfomas…) mantendo a ordem dentro de cada um.
List<Flashcard> intercalarModulos(Iterable<Flashcard> cs) {
  final grupos = <String, List<Flashcard>>{};
  for (final c in cs) {
    grupos.putIfAbsent(c.modulo, () => []).add(c);
  }
  final filas = grupos.values.toList();
  final n = filas.fold(0, (a, f) => a + f.length);
  final out = <Flashcard>[];
  for (var i = 0; out.length < n; i++) {
    for (final f in filas) {
      if (i < f.length) out.add(f[i]);
    }
  }
  return out;
}

/// Vencidos (mais atrasados primeiro) + até [maxNovos] novos, intercalando módulos.
List<Flashcard> filaRevisao(Iterable<Flashcard> cs, {int? maxNovos = 15}) {
  final st = AppState.I;
  final vencidos = cs.where(st.cartaoVencido).toList()
    ..sort((a, b) => st.flash[a.id]!.due.compareTo(st.flash[b.id]!.due));
  final novos = intercalarModulos(cs.where(st.cartaoNovo));
  return [...intercalarModulos(vencidos), ...(maxNovos == null ? novos : novos.take(maxNovos))];
}

/// Todos os cartões, do que vence antes para o que vence depois (revisão adiantada).
List<Flashcard> filaAdiantada(Iterable<Flashcard> cs) {
  final st = AppState.I;
  return cs.toList()..sort((a, b) => (st.flash[a.id]?.due ?? 0).compareTo(st.flash[b.id]?.due ?? 0));
}

/// Minutos até o próximo cartão (entre os já estudados) vencer; null se nenhum.
int? minutosAteProximo(Iterable<Flashcard> cs) {
  final st = AppState.I;
  final agora = DateTime.now().millisecondsSinceEpoch;
  int? menor;
  for (final c in cs) {
    final s = st.flash[c.id];
    if (s == null || s.due <= agora) continue;
    if (menor == null || s.due < menor) menor = s.due;
  }
  return menor == null ? null : max(1, ((menor - agora) / 60000).ceil());
}

// =====================================================================================
// Sessão
// =====================================================================================

class SessaoFlash extends StatefulWidget {
  const SessaoFlash({super.key, required this.titulo, required this.cartoes});
  final String titulo;
  final List<Flashcard> cartoes;

  @override
  State<SessaoFlash> createState() => _SessaoFlashState();
}

class _SessaoFlashState extends State<SessaoFlash> {
  late List<Flashcard> _fila = [...widget.cartoes];
  int _i = 0;
  int _rodada = 0;
  bool _virado = false;
  bool _dica = false;
  final _contagem = [0, 0, 0, 0];
  late TelaCtx _ctx;

  bool get _fim => _i >= _fila.length;

  static const _rotulos = ['Errei', 'Difícil', 'Bom', 'Fácil'];

  @override
  void initState() {
    super.initState();
    _ctx = _ctxAtual();
  }

  TelaCtx _ctxAtual() {
    if (_fim) {
      return TelaCtx('Flashcards · resumo', () {
        final b = StringBuffer('Ela terminou uma sessão de flashcards (${widget.titulo}): ');
        for (var r = 0; r < 4; r++) {
          b.write('${_rotulos[r]}: ${_contagem[r]}${r < 3 ? ', ' : '.'}');
        }
        return b.toString();
      }, sugestoes: const ['Me faça 5 perguntas rápidas sobre o que eu errei', 'Me dê um macete para lembrar disto']);
    }
    final c = _fila[_i];
    return TelaCtx('Flashcard · ${moduloNome(c.modulo)}', () {
      final b = StringBuffer();
      if (c.topico.isNotEmpty) b.writeln('Tópico: ${topicoNome(c.topico)}');
      b.writeln('Frente do cartão: ${c.frente}');
      if (c.dica.isNotEmpty && (_dica || _virado)) b.writeln('Dica: ${c.dica}');
      if (_virado) {
        b.writeln('Verso (resposta): ${c.verso}');
      } else {
        b.writeln('(Ela ainda não virou o cartão — não entregue a resposta a menos que ela peça.)');
      }
      return b.toString();
    }, sugestoes: const ['Explique este cartão com um exemplo', 'Me dê um macete para lembrar disto']);
  }

  void _virar() => setState(() => _virado = !_virado);

  void _avaliar(int r) {
    final c = _fila[_i];
    AppState.I.avaliarCartao(c.id, r);
    _contagem[r]++;
    if (r == 0) _fila.add(c);
    setState(() {
      _i++;
      _virado = false;
      _dica = false;
      _ctx = _ctxAtual();
    });
  }

  void _continuar() {
    var nova = filaRevisao(widget.cartoes);
    if (nova.isEmpty) nova = filaAdiantada(widget.cartoes);
    setState(() {
      _fila = nova;
      _i = 0;
      _rodada++;
      _virado = false;
      _dica = false;
      for (var r = 0; r < 4; r++) {
        _contagem[r] = 0;
      }
      _ctx = _ctxAtual();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (widget.cartoes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.titulo)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.style_outlined, size: 40, color: p.inkFaint),
                const SizedBox(height: 12),
                Text('Nenhum cartão neste baralho.', style: TextStyle(fontSize: 16, color: p.ink)),
                const SizedBox(height: 6),
                Text(
                  'Escolha outro baralho ou crie um cartão na aba Flashcards.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.inkSoft),
                ),
                const SizedBox(height: 18),
                OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
              ],
            ),
          ),
        ),
      );
    }
    final total = _fila.length;
    return CtxCopiloto(
      ctx: _ctx,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.titulo, overflow: TextOverflow.ellipsis)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
              child: Row(
                children: [
                  Expanded(child: Barra(total == 0 ? 1 : _i / total, cor: p.primary, altura: 5)),
                  const SizedBox(width: 12),
                  Text(
                    _fim ? 'Concluído' : '${_i + 1} de $total',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.inkSoft),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: _fim
                      ? _Resumo(
                          key: ValueKey('fim$_rodada'),
                          contagem: _contagem,
                          cartoes: widget.cartoes,
                          onContinuar: _continuar,
                        )
                      : _CartaoVirando(
                          key: ValueKey('c$_rodada-$_i'),
                          cartao: _fila[_i],
                          virado: _virado,
                          dicaVisivel: _dica,
                          onVirar: _virar,
                          onDica: () => setState(() => _dica = true),
                        ),
                ),
              ),
            ),
            if (!_fim) _controles(context),
          ],
        ),
      ),
    );
  }

  Widget _controles(BuildContext context) {
    final p = context.pal;
    final s = AppState.I.flash[_fila[_i].id];
    final cores = [p.bad, p.warn, p.primary, p.ok];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: !_virado
              ? SizedBox(
                  key: const ValueKey('mostrar'),
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _virar,
                    icon: const Icon(Icons.flip_rounded, size: 20),
                    label: const Text('Mostrar resposta'),
                  ),
                )
              : Row(
                  key: const ValueKey('notas'),
                  children: [
                    for (var r = 0; r < 4; r++) ...[
                      if (r > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _BotaoNota(
                          rotulo: _rotulos[r],
                          intervalo: fmtMin(intervalosFlashMin[proximaCaixa(s, r)]),
                          cor: cores[r],
                          onTap: () => _avaliar(r),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _BotaoNota extends StatelessWidget {
  final String rotulo, intervalo;
  final Color cor;
  final VoidCallback onTap;
  const _BotaoNota({required this.rotulo, required this.intervalo, required this.cor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.soft(cor, .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.soft(cor, .45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                rotulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: cor),
              ),
              const SizedBox(height: 2),
              Text(intervalo, maxLines: 1, style: TextStyle(fontSize: 11.5, color: p.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================================
// Cartão com animação de virar
// =====================================================================================

class _CartaoVirando extends StatelessWidget {
  final Flashcard cartao;
  final bool virado, dicaVisivel;
  final VoidCallback onVirar, onDica;
  const _CartaoVirando({
    super.key,
    required this.cartao,
    required this.virado,
    required this.dicaVisivel,
    required this.onVirar,
    required this.onDica,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: virado ? 'Cartão virado: resposta' : 'Cartão: pergunta. Toque para virar.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onVirar,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: virado ? 1 : 0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          builder: (context, t, _) {
            final frente = t < .5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0012)
                ..rotateY(t * pi),
              child: frente
                  ? _face(context, false)
                  : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(pi),
                      child: _face(context, true),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _face(BuildContext context, bool verso) {
    final p = context.pal;
    final cor = p.modulo(cartao.modulo);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: verso ? p.soft(cor, .5) : p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 4, color: verso ? cor : p.soft(cor, .5)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Selo(moduloNome(cartao.modulo), cor: cor, icone: moduloIcone(cartao.modulo)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cartao.minha ? 'Meu cartão' : (cartao.topico.isEmpty ? '' : topicoNome(cartao.topico)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: p.inkSoft),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: max(0, c.maxHeight - 24)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: verso ? _conteudoVerso(context) : _conteudoFrente(context),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app_outlined, size: 15, color: p.inkFaint),
                const SizedBox(width: 5),
                Text(
                  verso ? 'Toque para ver a pergunta' : 'Toque para virar',
                  style: TextStyle(fontSize: 12, color: p.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _conteudoFrente(BuildContext context) {
    final p = context.pal;
    return [
      MdText(
        cartao.frente,
        align: TextAlign.center,
        style: const TextStyle(fontSize: 21, height: 1.4, fontWeight: FontWeight.w600),
      ),
      if (cartao.dica.isNotEmpty) ...[
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: dicaVisivel
              ? Container(
                  key: const ValueKey('dica'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    'Dica: ${cartao.dica}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: p.inkSoft),
                  ),
                )
              : TextButton.icon(
                  key: const ValueKey('verdica'),
                  onPressed: onDica,
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                  label: const Text('ver dica'),
                ),
        ),
      ],
    ];
  }

  List<Widget> _conteudoVerso(BuildContext context) {
    final p = context.pal;
    return [
      MdText(
        cartao.frente,
        align: TextAlign.center,
        style: TextStyle(fontSize: 14, color: p.inkSoft, height: 1.4),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: SizedBox(width: 48, child: Divider(height: 1, color: p.line)),
      ),
      MdText(cartao.verso, align: TextAlign.center, style: const TextStyle(fontSize: 18.5, height: 1.5)),
    ];
  }
}

// =====================================================================================
// Resumo da sessão
// =====================================================================================

class _Resumo extends StatelessWidget {
  final List<int> contagem;
  final List<Flashcard> cartoes;
  final VoidCallback onContinuar;
  const _Resumo({super.key, required this.contagem, required this.cartoes, required this.onContinuar});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final total = contagem.fold(0, (a, b) => a + b);
    final cores = [p.bad, p.warn, p.primary, p.ok];
    const rotulos = ['Errei', 'Difícil', 'Bom', 'Fácil'];
    final pendentes = filaRevisao(cartoes).length;
    final prox = minutosAteProximo(cartoes);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          Icon(Icons.check_circle_outline_rounded, size: 44, color: p.ok),
          const SizedBox(height: 10),
          Text(
            'Sessão concluída',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: kSerif, fontSize: 28, color: p.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '$total ${total == 1 ? 'avaliação' : 'avaliações'} nesta rodada',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.inkSoft),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var r = 0; r < 4; r++) ...[
                if (r > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: p.soft(cores[r]), borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      children: [
                        Text(
                          '${contagem[r]}',
                          style: TextStyle(fontFamily: kSerif, fontSize: 26, color: cores[r], height: 1.1),
                        ),
                        Text(
                          rotulos[r],
                          style: TextStyle(fontSize: 12.5, color: p.inkSoft, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Text(
            pendentes > 0
                ? '$pendentes ${pendentes == 1 ? 'cartão está' : 'cartões estão'} para revisar agora neste baralho.'
                : prox != null
                ? 'Nada vencido agora. O próximo cartão volta em ${fmtMin(prox)} — dá para adiantar, se quiser.'
                : 'Nada vencido agora neste baralho.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.inkSoft, height: 1.4, fontSize: 14),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onContinuar,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Continuar revisando'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        ],
      ),
    );
  }
}
