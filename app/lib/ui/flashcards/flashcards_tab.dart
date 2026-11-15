import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import 'sessao_flash.dart';

const _modulos = ['tireoide', 'linfadenopatias', 'linfomas'];

/// Baralho escolhido explicitamente: o que está pendente; se nada estiver, tudo (adiantado).
List<Flashcard> _filaBaralho(List<Flashcard> cs) {
  final f = filaRevisao(cs, maxNovos: null);
  return f.isEmpty ? filaAdiantada(cs) : f;
}

void _estudar(BuildContext context, String titulo, List<Flashcard> cs) =>
    abrir(context, SessaoFlash(titulo: titulo, cartoes: _filaBaralho(cs)));

class FlashcardsTab extends StatelessWidget {
  const FlashcardsTab({super.key});

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
            final todos = st.cartoes;
            final meus = todos.where((c) => c.minha).toList();
            return ListView(
              padding: const EdgeInsets.only(bottom: 110),
              children: [
                const TituloAba('Flashcards', sub: 'Um fato por cartão, revisado na hora certa'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _Topo(cartoes: todos),
                ),
                const _Secao('Baralhos por módulo'),
                for (final m in _modulos)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _BaralhoModulo(modulo: m, cartoes: todos.where((c) => c.modulo == m).toList()),
                  ),
                const _Secao('Meus cartões'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _MeusCartoes(cartoes: meus),
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
  const _Secao(this.titulo);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(20, 26, 20, 10), child: Rotulo(titulo));
}

// ------------------------------------------------------------------ topo

class _Topo extends StatelessWidget {
  final List<Flashcard> cartoes;
  const _Topo({required this.cartoes});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = AppState.I;
    final vencidos = cartoes.where(st.cartaoVencido).length;
    final novos = cartoes.where(st.cartaoNovo).length;
    final dominados = cartoes.where(st.cartaoDominado).length;
    final fila = filaRevisao(cartoes);
    final prox = minutosAteProximo(cartoes);

    Widget numero(String v, String rotulo, Color cor) => Expanded(
      child: Column(
        children: [
          Text(
            v,
            style: TextStyle(fontFamily: kSerif, fontSize: 30, height: 1.1, color: cor),
          ),
          const SizedBox(height: 2),
          Text(
            rotulo,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: p.inkSoft, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );

    return Painel(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              numero('$vencidos', 'para revisar\nagora', vencidos > 0 ? p.primary : p.inkFaint),
              Container(width: 1, height: 44, color: p.line),
              numero('$novos', 'novos', p.ink),
              Container(width: 1, height: 44, color: p.line),
              numero('$dominados', 'dominados', p.ok),
            ],
          ),
          const SizedBox(height: 16),
          if (cartoes.isEmpty)
            Text(
              'Ainda não há flashcards carregados. Crie os seus em “Meus cartões”, logo abaixo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.inkSoft, height: 1.4),
            )
          else if (fila.isNotEmpty)
            FilledButton.icon(
              onPressed: () => abrir(context, SessaoFlash(titulo: 'Revisão', cartoes: fila)),
              icon: const Icon(Icons.play_arrow_rounded, size: 21),
              label: Text('Revisar agora (${fila.length})'),
            )
          else ...[
            Text(
              prox == null ? 'Tudo em dia.' : 'Tudo em dia. O próximo cartão volta em ${fmtMin(prox)}.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => abrir(
                context,
                SessaoFlash(titulo: 'Revisão adiantada', cartoes: filaAdiantada(cartoes).take(20).toList()),
              ),
              icon: const Icon(Icons.fast_forward_rounded, size: 19),
              label: const Text('Adiantar revisão'),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, size: 15, color: p.inkFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Os intervalos são curtos de propósito — pensados para uma maratona de 12h: o que você erra volta em '
                  '1 min; o que acerta, em 10 min, 40 min, 2h30…',
                  style: TextStyle(fontSize: 12.5, color: p.inkSoft, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ baralho de módulo

class _BaralhoModulo extends StatefulWidget {
  final String modulo;
  final List<Flashcard> cartoes;
  const _BaralhoModulo({required this.modulo, required this.cartoes});
  @override
  State<_BaralhoModulo> createState() => _BaralhoModuloState();
}

class _BaralhoModuloState extends State<_BaralhoModulo> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cor = p.modulo(widget.modulo);
    final cs = widget.cartoes;
    final c = _Contagem.de(cs);

    // agrupa por tópico, na ordem da lista fechada de tópicos
    final grupos = <String, List<Flashcard>>{};
    for (final x in cs) {
      final k = x.topico.isNotEmpty ? x.topico : (x.minha ? '__minha' : '__outros');
      grupos.putIfAbsent(k, () => []).add(x);
    }
    final ordem = topicoNomes.keys.toList();
    final chaves = grupos.keys.toList()
      ..sort((a, b) {
        int pos(String k) =>
            k == '__minha' ? 9999 : (k == '__outros' ? 9998 : (ordem.contains(k) ? ordem.indexOf(k) : 9000));
        return pos(a).compareTo(pos(b));
      });
    String nome(String k) => switch (k) {
      '__minha' => 'Meus cartões',
      '__outros' => 'Outros',
      _ => topicoNome(k),
    };

    return Painel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _aberto = !_aberto),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
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
                        Text(c.texto, style: TextStyle(fontSize: 13, color: p.inkSoft, height: 1.3)),
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
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Row(
              children: [
                Expanded(child: Barra(cs.isEmpty ? 0 : c.dominados / cs.length, cor: cor, altura: 5)),
                const SizedBox(width: 10),
                Text(
                  'domínio ${cs.isEmpty ? 0 : (c.dominados * 100 / cs.length).round()}%',
                  style: TextStyle(fontSize: 11.5, color: p.inkSoft, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_aberto
                ? const SizedBox(width: double.infinity, height: 14)
                : Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: cs.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'Ainda não há cartões deste módulo — crie um em “Meus cartões”.',
                              style: TextStyle(color: p.inkSoft),
                            ),
                          )
                        : Column(
                            children: [
                              _LinhaBaralho(
                                titulo: 'Estudar ${moduloNome(widget.modulo)}',
                                cartoes: cs,
                                cor: cor,
                                forte: true,
                              ),
                              for (final k in chaves)
                                _LinhaBaralho(
                                  titulo: nome(k),
                                  cartoes: grupos[k]!,
                                  cor: cor,
                                  tituloSessao: '${moduloNome(widget.modulo)} · ${nome(k)}',
                                ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Contagem {
  final int vencidos, novos, dominados, total;
  _Contagem(this.vencidos, this.novos, this.dominados, this.total);
  factory _Contagem.de(Iterable<Flashcard> cs) {
    final st = AppState.I;
    var v = 0, n = 0, d = 0, t = 0;
    for (final c in cs) {
      t++;
      if (st.cartaoVencido(c)) v++;
      if (st.cartaoNovo(c)) n++;
      if (st.cartaoDominado(c)) d++;
    }
    return _Contagem(v, n, d, t);
  }

  String get texto => [
    '$total ${total == 1 ? 'cartão' : 'cartões'}',
    if (vencidos > 0) '$vencidos para revisar',
    if (novos > 0) '$novos ${novos == 1 ? 'novo' : 'novos'}',
  ].join(' · ');
}

class _LinhaBaralho extends StatelessWidget {
  final String titulo;
  final String? tituloSessao;
  final List<Flashcard> cartoes;
  final Color cor;
  final bool forte;
  const _LinhaBaralho({
    required this.titulo,
    required this.cartoes,
    required this.cor,
    this.tituloSessao,
    this.forte = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = _Contagem.de(cartoes);
    return InkWell(
      onTap: () => _estudar(context, tituloSessao ?? titulo, cartoes),
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
              if (c.vencidos > 0) ...[
                Selo('${c.vencidos}', cor: p.primary, icone: Icons.schedule_rounded),
                const SizedBox(width: 6),
              ],
              Text('${c.dominados}/${c.total}', style: TextStyle(fontSize: 12.5, color: p.inkSoft)),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ meus cartões

class _MeusCartoes extends StatelessWidget {
  final List<Flashcard> cartoes;
  const _MeusCartoes({required this.cartoes});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = _Contagem.de(cartoes);
    return Painel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.soft(p.warn), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.edit_note_rounded, color: p.warn, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meus cartões',
                      style: TextStyle(fontFamily: kSerif, fontSize: 20, color: p.ink, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(cartoes.isEmpty ? 'Nenhum ainda' : c.texto, style: TextStyle(fontSize: 13, color: p.inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (cartoes.isEmpty)
            Text(
              'Crie cartões com o que você mais esquece — eles entram na revisão junto com os outros.',
              style: TextStyle(fontSize: 13.5, color: p.inkSoft, height: 1.4),
            ),
          if (cartoes.isEmpty) const SizedBox(height: 12),
          Row(
            children: [
              if (cartoes.isNotEmpty) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: () => _estudar(context, 'Meus cartões', cartoes),
                    child: const Text('Estudar'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => criarCartaoSheet(context),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Criar cartão'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> criarCartaoSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const _CriarCartao(),
);

class _CriarCartao extends StatefulWidget {
  const _CriarCartao();
  @override
  State<_CriarCartao> createState() => _CriarCartaoState();
}

class _CriarCartaoState extends State<_CriarCartao> {
  final _frente = TextEditingController();
  final _verso = TextEditingController();
  String? _modulo;
  bool _salvando = false;

  @override
  void dispose() {
    _frente.dispose();
    _verso.dispose();
    super.dispose();
  }

  bool get _pronto => _modulo != null && _frente.text.trim().isNotEmpty && _verso.text.trim().isNotEmpty;

  Future<void> _salvar() async {
    if (!_pronto || _salvando) return;
    setState(() => _salvando = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    await AppState.I.criarCartao(_modulo!, _frente.text.trim(), _verso.text.trim());
    nav.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Cartão criado. Ele já entra na próxima revisão.')));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Novo cartão',
              style: TextStyle(fontFamily: kSerif, fontSize: 26, color: p.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Um fato por cartão. Pergunta curta na frente, resposta curta no verso.',
              style: TextStyle(fontSize: 13.5, color: p.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Rotulo('Módulo'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _modulos)
                  ChoiceChip(
                    label: Text(moduloNome(m)),
                    avatar: Icon(moduloIcone(m), size: 16, color: _modulo == m ? p.surface : p.modulo(m)),
                    selected: _modulo == m,
                    showCheckmark: false,
                    selectedColor: p.modulo(m),
                    backgroundColor: p.surface,
                    side: BorderSide(color: _modulo == m ? p.modulo(m) : p.line),
                    labelStyle: TextStyle(
                      color: _modulo == m ? p.surface : p.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    onSelected: (_) => setState(() => _modulo = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Rotulo('Frente (pergunta)'),
            const SizedBox(height: 8),
            TextField(
              controller: _frente,
              onChanged: (_) => setState(() {}),
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Ex.: “Céu estrelado” → qual linfoma?'),
            ),
            const SizedBox(height: 14),
            const Rotulo('Verso (resposta)'),
            const SizedBox(height: 8),
            TextField(
              controller: _verso,
              onChanged: (_) => setState(() {}),
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Use **negrito** para o termo-chave.'),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _pronto && !_salvando ? _salvar : null,
              child: Text(_modulo == null ? 'Escolha o módulo' : 'Salvar cartão'),
            ),
          ],
        ),
      ),
    );
  }
}
