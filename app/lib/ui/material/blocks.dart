import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../copilot/copilot_sheet.dart';
import '../widgets/common.dart';
import '../widgets/md.dart';
import 'figure_viewer.dart';

// ============================================================================
// Utilidades de dados
// ============================================================================

/// Bloco selecionado agora (ref "capId#blocoId"). Só um por vez no app inteiro.
final ValueNotifier<String?> blocoSelecionado = ValueNotifier<String?>(null);

String _s(dynamic v) => v == null ? '' : '$v';
List<String> _strs(dynamic v) => v is List ? [for (final x in v) '$x'] : const [];
List<Json> _maps(dynamic v) => v is List
    ? [
        for (final x in v)
          if (x is Map) Map<String, dynamic>.from(x),
      ]
    : const [];

/// Remove a marcação leve (**negrito**, *itálico*, `código`).
String limparMd(String s) => s
    .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*', dotAll: true), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'\*(.+?)\*', dotAll: true), (m) => m[1]!)
    .replaceAll('`', '');

String _cabeca(String s, int n) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= n ? t : '${t.substring(0, n).trimRight()}…';
}

/// Todos os ids de blocos dentro de um bloco (inclusive ele mesmo).
bool blocoContem(Json b, String id) {
  if (_s(b['id']) == id) return true;
  if (b['tipo'] == 'expansivel') {
    for (final x in _maps(b['blocos'])) {
      if (blocoContem(x, id)) return true;
    }
  }
  return false;
}

/// Rótulo, ícone e cor de cada estilo de `destaque`.
({String rotulo, IconData icone}) infoDestaque(String estilo) => switch (estilo) {
  'prova' => (rotulo: 'Cai na prova', icone: Icons.assignment_late_outlined),
  'professor' => (rotulo: 'O professor disse', icone: Icons.record_voice_over_outlined),
  'atencao' => (rotulo: 'Atenção', icone: Icons.warning_amber_rounded),
  'dica' => (rotulo: 'Dica', icone: Icons.lightbulb_outline_rounded),
  'mnemonico' => (rotulo: 'Mnemônico', icone: Icons.psychology_outlined),
  'definicao' => (rotulo: 'Definição', icone: Icons.menu_book_outlined),
  'frase' => (rotulo: 'Frase pronta para a discursiva', icone: Icons.format_quote_rounded),
  _ => (rotulo: 'Destaque', icone: Icons.info_outline_rounded),
};

Color corDestaque(Pal p, String estilo, Color cor) => switch (estilo) {
  'prova' => p.bad,
  'professor' => p.dark ? const Color(0xFFA9B8D8) : const Color(0xFF475A80),
  'atencao' => p.warn,
  'dica' => p.dark ? const Color(0xFF8CC3EE) : const Color(0xFF2B6FA8),
  'mnemonico' => p.dark ? const Color(0xFFE59AC6) : const Color(0xFFA63C7B),
  'frase' => p.primary,
  _ => cor,
};

/// Serializa qualquer bloco em texto legível (para o copiloto, flashcards etc.).
String textoPlano(Json b) {
  final tipo = _s(b['tipo']);
  switch (tipo) {
    case 'titulo':
      return '## ${limparMd(_s(b['texto']))}';
    case 'subtitulo':
      return '### ${limparMd(_s(b['texto']))}';
    case 'texto':
      return limparMd(_s(b['md']));
    case 'lista':
      final ord = b['ordenada'] == true;
      final it = _strs(b['itens']);
      return [for (var i = 0; i < it.length; i++) '${ord ? '${i + 1}.' : '-'} ${limparMd(it[i])}'].join('\n');
    case 'destaque':
      final info = infoDestaque(_s(b['estilo']));
      final t = _s(b['titulo']);
      return '[${info.rotulo}]${t.isEmpty ? '' : ' ${limparMd(t)}:'} ${limparMd(_s(b['md']))}';
    case 'tabela':
      final cols = _strs(b['colunas']).map(limparMd).toList();
      final linhas = [for (final l in (b['linhas'] as List? ?? const [])) _strs(l).map(limparMd).toList()];
      final out = StringBuffer('Tabela: ${limparMd(_s(b['titulo']))}\n');
      if (b['comparacao'] == true && cols.length > 1) {
        out.writeln('(comparação: ${cols.skip(1).join(' × ')})');
        for (final l in linhas) {
          final partes = [for (var j = 1; j < cols.length; j++) '${cols[j]}: ${j < l.length ? l[j] : ''}'];
          out.writeln('- ${l.isEmpty ? '' : l[0]} → ${partes.join(' | ')}');
        }
      } else {
        out.writeln(cols.join(' | '));
        for (final l in linhas) {
          out.writeln(l.join(' | '));
        }
      }
      return out.toString().trimRight();
    case 'fluxo':
      final ps = _maps(b['passos']);
      return [
        'Fluxo: ${limparMd(_s(b['titulo']))}',
        for (var i = 0; i < ps.length; i++)
          '${i + 1}. ${limparMd(_s(ps[i]['titulo']))} — ${limparMd(_s(ps[i]['texto']))}',
      ].join('\n');
    case 'cartoes':
      return [
        limparMd(_s(b['titulo'])),
        for (final c in _maps(b['itens'])) '- ${limparMd(_s(c['titulo']))}: ${limparMd(_s(c['texto']))}',
      ].where((x) => x.isNotEmpty).join('\n');
    case 'figura':
      return '[Figura: ${limparMd(_s(b['legenda']))}]';
    case 'foto':
      final f = AppState.I.fotos[_s(b['ref'])];
      final d = f == null ? '' : ' O que observar: ${limparMd(_s(f['descricao']))}';
      return '[Foto de microscopia: ${limparMd(_s(b['legenda']))}.$d]';
    case 'expansivel':
      return [
        '[Aprofundar] ${limparMd(_s(b['titulo']))}',
        for (final x in _maps(b['blocos'])) textoPlano(x),
      ].join('\n');
    case 'quiz':
      final op = _strs(b['opcoes']);
      final c = (b['correta'] as num?)?.toInt() ?? -1;
      final letras = 'ABCDEFGH';
      return [
        'Teste rápido: ${limparMd(_s(b['pergunta']))}',
        for (var i = 0; i < op.length; i++) '${letras[i % letras.length]}) ${limparMd(op[i])}',
        if (c >= 0 && c < op.length) 'Resposta: ${letras[c % letras.length]}) ${limparMd(op[c])}',
        if (_s(b['explicacao']).isNotEmpty) 'Explicação: ${limparMd(_s(b['explicacao']))}',
      ].join('\n');
    case 'revelar':
      return 'Pergunta: ${limparMd(_s(b['pergunta']))}\nResposta: ${limparMd(_s(b['resposta']))}';
    case 'resumo':
      return ['Para levar:', for (final i in _strs(b['itens'])) '- ${limparMd(i)}'].join('\n');
  }
  return '';
}

// ---- existência de assets (o arquivo pode não ter sido gerado)
Future<Set<String>>? _manifesto;
Future<Set<String>> _assets() =>
    _manifesto ??= AssetManifest.loadFromAssetBundle(rootBundle)
        .then((m) => m.listAssets().toSet())
        .catchError((Object _) => <String>{});

class _SeExiste extends StatelessWidget {
  final String asset;
  final Widget child;
  const _SeExiste({required this.asset, required this.child});
  @override
  Widget build(BuildContext context) => FutureBuilder<Set<String>>(
    future: _assets(),
    builder: (context, snap) {
      final s = snap.data;
      if (s == null) return const SizedBox.shrink();
      if (s.isNotEmpty && !s.contains(asset)) return const SizedBox.shrink();
      return child;
    },
  );
}

// ============================================================================
// BlockView
// ============================================================================

class BlockView extends StatefulWidget {
  final Json bloco;
  final String capId;
  final Color cor;

  /// Bloco que deve ficar visível ao abrir (abre o `expansivel` que o contém).
  final String? alvo;
  const BlockView({super.key, required this.bloco, required this.capId, required this.cor, this.alvo});

  @override
  State<BlockView> createState() => _BlockViewState();
}

class _BlockViewState extends State<BlockView> {
  late final Listenable _ouvir = Listenable.merge([AppState.I, blocoSelecionado]);
  bool _anotando = false;

  static const _interativos = {'quiz', 'revelar', 'expansivel', 'figura', 'foto'};
  static const _conhecidos = {
    'titulo', 'subtitulo', 'texto', 'lista', 'destaque', 'tabela', 'fluxo', 'cartoes', //
    'figura', 'foto', 'expansivel', 'quiz', 'revelar', 'resumo',
  };

  Json get b => widget.bloco;
  String get _tipo => _s(b['tipo']);
  String get _ref => '${widget.capId}#${_s(b['id'])}';

  void _alternar() => blocoSelecionado.value = blocoSelecionado.value == _ref ? null : _ref;

  @override
  Widget build(BuildContext context) {
    if (!_conhecidos.contains(_tipo)) return const SizedBox.shrink();
    if (_tipo == 'foto' && !AppState.I.fotos.containsKey(_s(b['ref']))) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _ouvir,
      builder: (context, _) {
        final p = context.pal;
        final st = AppState.I;
        final e = st.escalaTexto;
        final sel = blocoSelecionado.value == _ref;
        final dest = st.destaques.contains(_ref);
        final temNota = st.nota('bloco', _ref).isNotEmpty;
        if (temNota) _anotando = true;
        final interativo = _interativos.contains(_tipo);
        final mais = interativo ? _BotaoMais(ativo: sel, cor: widget.cor, onTap: _alternar) : null;

        final corpo = _corpo(context, p, e, mais);
        final caixa = AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: dest ? p.marca : (sel ? p.soft(widget.cor, .06) : widget.cor.withValues(alpha: 0)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sel ? widget.cor.withValues(alpha: .45) : widget.cor.withValues(alpha: 0),
              width: 1.2,
            ),
          ),
          child: corpo,
        );

        return Padding(
          padding: EdgeInsets.only(
            top: switch (_tipo) {
              'titulo' => 22,
              'subtitulo' => 6,
              _ => 0,
            },
            bottom: 6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (interativo)
                caixa
              else
                GestureDetector(behavior: HitTestBehavior.opaque, onTap: _alternar, child: caixa),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topCenter,
                child: sel
                    ? _BarraAcoes(
                        cor: widget.cor,
                        destacado: dest,
                        anotando: _anotando && !temNota,
                        onAnotar: () {
                          setState(() => _anotando = !(_anotando && !temNota));
                          blocoSelecionado.value = null;
                        },
                        onDestacar: () {
                          AppState.I.alternarDestaque(_ref);
                          blocoSelecionado.value = null;
                        },
                        onPerguntar: () {
                          blocoSelecionado.value = null;
                          abrirCopiloto(rascunho: 'Sobre este trecho: "${_cabeca(textoPlano(b), 220)}"\n\n');
                        },
                        onFlashcard: () => _criarFlashcard(context),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              if (_anotando)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: CampoNota(kind: 'bloco', ref: _ref, dica: 'Sua anotação sobre este trecho…'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _corpo(BuildContext context, Pal p, double e, Widget? mais) {
    final cor = widget.cor;
    switch (_tipo) {
      case 'titulo':
        return _Titulo(texto: _s(b['texto']), cor: cor, e: e);
      case 'subtitulo':
        return Text.rich(
          TextSpan(children: mdSpans(_s(b['texto']), const TextStyle())),
          style: TextStyle(fontSize: 17 * e, fontWeight: FontWeight.w700, height: 1.3, color: p.ink),
        );
      case 'texto':
        return MdText(_s(b['md']), style: TextStyle(fontSize: 15.5 * e, height: 1.55));
      case 'lista':
        return _Lista(itens: _strs(b['itens']), ordenada: b['ordenada'] == true, cor: cor, e: e);
      case 'destaque':
        return _Destaque(bloco: b, cor: cor, e: e);
      case 'tabela':
        return TabelaView(bloco: b, cor: cor);
      case 'fluxo':
        return _Fluxo(bloco: b, cor: cor, e: e);
      case 'cartoes':
        return _Cartoes(bloco: b, cor: cor, e: e);
      case 'figura':
        return _Figura(bloco: b, cor: cor, e: e, mais: mais);
      case 'foto':
        return _Foto(bloco: b, cor: cor, e: e, mais: mais);
      case 'expansivel':
        return _Expansivel(bloco: b, capId: widget.capId, cor: cor, e: e, alvo: widget.alvo, mais: mais);
      case 'quiz':
        return _Quiz(bloco: b, cor: cor, e: e, mais: mais);
      case 'revelar':
        return _Revelar(bloco: b, cor: cor, e: e, mais: mais);
      case 'resumo':
        return _Resumo(itens: _strs(b['itens']), cor: cor, e: e);
    }
    return const SizedBox.shrink();
  }

  // ---- flashcard a partir do trecho
  ({String frente, String verso}) _sugestaoCartao() {
    String primeiraNegrito(String md) => RegExp(r'\*\*(.+?)\*\*').firstMatch(md)?.group(1) ?? '';
    switch (_tipo) {
      case 'quiz':
        final op = _strs(b['opcoes']);
        final c = (b['correta'] as num?)?.toInt() ?? -1;
        final certa = c >= 0 && c < op.length ? op[c] : '';
        return (
          frente: limparMd(_s(b['pergunta'])),
          verso: [certa, _s(b['explicacao'])].where((x) => x.isNotEmpty).join('\n\n'),
        );
      case 'revelar':
        return (frente: limparMd(_s(b['pergunta'])), verso: _s(b['resposta']));
      case 'destaque':
        final t = _s(b['titulo']);
        return (frente: limparMd(t.isEmpty ? infoDestaque(_s(b['estilo'])).rotulo : t), verso: _s(b['md']));
      case 'titulo' || 'subtitulo':
        return (frente: limparMd(_s(b['texto'])), verso: '');
      case 'texto':
        final n = limparMd(primeiraNegrito(_s(b['md'])));
        return (frente: n.isEmpty ? '' : '$n: o que você precisa saber?', verso: _s(b['md']));
      case 'lista':
        return (frente: '', verso: _strs(b['itens']).map((x) => '• $x').join('\n'));
      case 'tabela' || 'fluxo' || 'cartoes':
        final t = limparMd(_s(b['titulo']));
        final corpo = textoPlano(b).split('\n').skip(1).join('\n');
        return (frente: t, verso: corpo);
      case 'resumo':
        return (frente: 'Para levar deste capítulo', verso: _strs(b['itens']).map((x) => '• $x').join('\n'));
      case 'figura' || 'foto':
        return (frente: 'O que esta imagem mostra?', verso: _s(b['legenda']));
      case 'expansivel':
        return (frente: limparMd(_s(b['titulo'])), verso: '');
    }
    return (frente: '', verso: '');
  }

  Future<void> _criarFlashcard(BuildContext context) async {
    blocoSelecionado.value = null;
    final sug = _sugestaoCartao();
    final frente = TextEditingController(text: sug.frente);
    final verso = TextEditingController(text: sug.verso);
    final modulo = AppState.I.capitulos[widget.capId]?.modulo ?? 'outros';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = ctx.pal;
        return AlertDialog(
          title: Text(
            'Novo flashcard',
            style: TextStyle(fontFamily: kSerif, fontSize: 22, color: p.ink),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Frente (pergunta)',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.inkSoft),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: frente,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Uma pergunta curta e específica'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Verso (resposta)',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.inkSoft),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: verso,
                    minLines: 3,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Resposta curta (1 fato por cartão)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
          ],
        );
      },
    );
    final f = frente.text.trim(), v = verso.text.trim();
    frente.dispose();
    verso.dispose();
    if (ok != true) return;
    if (f.isEmpty || v.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Preencha a frente e o verso para criar o cartão.')));
      }
      return;
    }
    await AppState.I.criarCartao(modulo, f, v);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Flashcard criado em ${moduloNome(modulo)}.')));
    }
  }
}

// ---- barra de ações do bloco selecionado
class _BarraAcoes extends StatelessWidget {
  final Color cor;
  final bool destacado, anotando;
  final VoidCallback onAnotar, onDestacar, onPerguntar, onFlashcard;
  const _BarraAcoes({
    required this.cor,
    required this.destacado,
    required this.anotando,
    required this.onAnotar,
    required this.onDestacar,
    required this.onPerguntar,
    required this.onFlashcard,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Row(
        children: [
          _Acao(
            icone: Icons.edit_note_rounded,
            rotulo: anotando ? 'Fechar nota' : 'Anotar',
            cor: p.warn,
            onTap: onAnotar,
          ),
          _Acao(
            icone: destacado ? Icons.format_color_reset_outlined : Icons.border_color_outlined,
            rotulo: destacado ? 'Remover destaque' : 'Destacar',
            cor: p.dark ? const Color(0xFFE5C84A) : const Color(0xFF9A7B00),
            onTap: onDestacar,
          ),
          _Acao(
            icone: Icons.auto_awesome_outlined,
            rotulo: 'Perguntar ao copiloto',
            cor: p.primary,
            onTap: onPerguntar,
          ),
          _Acao(icone: Icons.style_outlined, rotulo: 'Virar flashcard', cor: cor, onTap: onFlashcard),
        ],
      ),
    );
  }
}

class _Acao extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final Color cor;
  final VoidCallback onTap;
  const _Acao({required this.icone, required this.rotulo, required this.cor, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 20, color: cor),
              const SizedBox(height: 3),
              Text(
                rotulo,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, height: 1.15, fontWeight: FontWeight.w600, color: context.pal.inkSoft),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BotaoMais extends StatelessWidget {
  final bool ativo;
  final Color cor;
  final VoidCallback onTap;
  final bool sobreBranco;
  const _BotaoMais({required this.ativo, required this.cor, required this.onTap}) : sobreBranco = false;
  const _BotaoMais._branco({required this.ativo, required this.cor, required this.onTap}) : sobreBranco = true;

  _BotaoMais branco() => _BotaoMais._branco(ativo: ativo, cor: cor, onTap: onTap);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fg = sobreBranco ? const Color(0xFF5F5B55) : (ativo ? cor : p.inkSoft);
    return Tooltip(
      message: 'Anotar, destacar, perguntar…',
      child: Material(
        color: sobreBranco ? const Color(0xE6FFFFFF) : (ativo ? p.soft(cor, .14) : Colors.transparent),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(Icons.more_horiz_rounded, size: 21, color: fg)),
        ),
      ),
    );
  }
}

// ============================================================================
// Blocos simples
// ============================================================================

class _Titulo extends StatelessWidget {
  final String texto;
  final Color cor;
  final double e;
  const _Titulo({required this.texto, required this.cor, required this.e});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = RegExp(r'^(\d+[.)])\s*(.*)$', dotAll: true).firstMatch(texto);
    final base = TextStyle(fontFamily: kSerif, fontSize: 23 * e, height: 1.2, color: p.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 3,
          decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: base,
            children: [
              if (m != null)
                TextSpan(
                  text: '${m.group(1)} ',
                  style: TextStyle(color: cor),
                ),
              ...mdSpans(m != null ? m.group(2)! : texto, base),
            ],
          ),
        ),
      ],
    );
  }
}

class _Lista extends StatelessWidget {
  final List<String> itens;
  final bool ordenada;
  final Color cor;
  final double e;
  const _Lista({required this.itens, required this.ordenada, required this.cor, required this.e});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fs = 15.5 * e;
    final linha = fs * 1.55;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < itens.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == itens.length - 1 ? 0 : 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ordenada)
                  Container(
                    margin: EdgeInsets.only(top: math.max(0, (linha - 22) / 2), right: 10),
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.soft(cor, .15), shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cor),
                    ),
                  )
                else
                  Container(
                    margin: EdgeInsets.only(top: (linha - 7) / 2, left: 4, right: 12),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                  ),
                Expanded(
                  child: MdText(itens[i], style: TextStyle(fontSize: fs, height: 1.55)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Destaque extends StatelessWidget {
  final Json bloco;
  final Color cor;
  final double e;
  const _Destaque({required this.bloco, required this.cor, required this.e});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final estilo = _s(bloco['estilo']);
    final info = infoDestaque(estilo);
    final c = corDestaque(p, estilo, cor);
    final titulo = _s(bloco['titulo']);
    final md = _s(bloco['md']);
    final frase = estilo == 'frase';
    final mostrarTitulo = titulo.isNotEmpty && titulo.toLowerCase() != info.rotulo.toLowerCase();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: p.soft(c, .09),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: c),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, frase ? 4 : 11, frase ? 4 : 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(info.icone, size: 17, color: c),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              info.rotulo.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .9,
                                color: c,
                              ),
                            ),
                          ),
                          if (frase)
                            IconButton(
                              tooltip: 'Copiar frase',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.copy_rounded, size: 18, color: c),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: limparMd(md)));
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Frase copiada.')));
                              },
                            ),
                        ],
                      ),
                      if (mostrarTitulo) ...[
                        SizedBox(height: frase ? 0 : 7),
                        Text.rich(
                          TextSpan(children: mdSpans(titulo, const TextStyle())),
                          style: TextStyle(fontSize: 15.5 * e, fontWeight: FontWeight.w700, height: 1.3, color: p.ink),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Padding(
                        padding: EdgeInsets.only(right: frase ? 10 : 0),
                        child: MdText(
                          md,
                          style: frase
                              ? TextStyle(fontSize: 15.5 * e, height: 1.55, fontStyle: FontStyle.italic)
                              : TextStyle(fontSize: 15 * e, height: 1.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Tabela
// ============================================================================

/// Tabela do material. Com `comparacao`, a 1ª coluna (critério) fica fixa e as
/// entidades rolam lado a lado quando não cabem.
class TabelaView extends StatefulWidget {
  final Json bloco;
  final Color cor;
  final bool mostrarTitulo;
  const TabelaView({super.key, required this.bloco, required this.cor, this.mostrarTitulo = true});
  @override
  State<TabelaView> createState() => _TabelaViewState();
}

class _TabelaViewState extends State<TabelaView> {
  final List<ScrollController> _ctls = [];
  bool _sincronizando = false;

  ScrollController _ctl(int i) {
    while (_ctls.length <= i) {
      final c = ScrollController();
      c.addListener(() => _sincronizar(c));
      _ctls.add(c);
    }
    return _ctls[i];
  }

  void _sincronizar(ScrollController origem) {
    if (_sincronizando || !origem.hasClients) return;
    _sincronizando = true;
    final o = origem.offset;
    for (final c in _ctls) {
      if (!identical(c, origem) && c.hasClients && c.offset != o) {
        c.jumpTo(o.clamp(c.position.minScrollExtent, c.position.maxScrollExtent));
      }
    }
    _sincronizando = false;
  }

  @override
  void dispose() {
    for (final c in _ctls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final e = AppState.I.escalaTexto;
    final b = widget.bloco;
    final cor = widget.cor;
    final cols = _strs(b['colunas']);
    final linhas = [for (final l in (b['linhas'] as List? ?? const [])) _strs(l)];
    final n = math.max(cols.length, linhas.fold<int>(0, (a, l) => math.max(a, l.length)));
    if (n == 0) return const SizedBox.shrink();
    final comparacao = b['comparacao'] == true && n >= 2;
    final titulo = _s(b['titulo']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.mostrarTitulo && titulo.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  comparacao ? Icons.compare_arrows_rounded : Icons.table_chart_outlined,
                  size: 19,
                  color: cor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: mdSpans(titulo, const TextStyle())),
                  style: TextStyle(fontSize: 15.5 * e, fontWeight: FontWeight.w700, height: 1.3, color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        LayoutBuilder(
          builder: (context, cons) {
            final w = cons.maxWidth;
            final escala = e.clamp(1.0, 1.4);
            if (comparacao) {
              final w0 = (w * .29).clamp(92.0, 136.0) * (1 + (escala - 1) * .5);
              final ent = n - 1;
              final minCw = (ent <= 2 ? 118.0 : 130.0) * escala;
              final resto = w - w0 - 2;
              final cw = math.max(minCw, resto / ent);
              final rola = cw * ent > resto + .5;
              return _comparacao(p, e, cor, cols, linhas, n, w0, cw, rola);
            }
            final minCw = (n <= 2 ? 120.0 : 130.0) * escala;
            final cw = math.max(minCw, (w - 2) / n);
            final rola = cw * n > w - 2 + .5;
            return _simples(p, e, cols, linhas, n, cw, rola);
          },
        ),
      ],
    );
  }

  Widget _dicaRolar(Pal p) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 2),
    child: Row(
      children: [
        Icon(Icons.swipe_left_outlined, size: 15, color: p.inkFaint),
        const SizedBox(width: 5),
        Text(
          'Deslize a tabela para o lado para ver todas as colunas',
          style: TextStyle(fontSize: 11.5, color: p.inkFaint),
        ),
      ],
    ),
  );

  Widget _comparacao(
    Pal p,
    double e,
    Color cor,
    List<String> cols,
    List<List<String>> linhas,
    int n,
    double w0,
    double cw,
    bool rola,
  ) {
    final fs = 13.5 * e;
    final total = linhas.length + 1;
    final zebra = p.soft(p.ink, p.dark ? .0 : .025);
    Widget cel(String t, {required bool ult, required bool primeiraCol, Color? bg, TextStyle? st, double? largura}) =>
        Container(
          width: largura,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              right: BorderSide(color: primeiraCol ? p.soft(cor, .35) : p.line, width: primeiraCol ? 1.4 : 1),
              bottom: ult ? BorderSide.none : BorderSide(color: p.line),
            ),
          ),
          child: MdText(t, style: TextStyle(fontSize: fs, height: 1.4).merge(st)),
        );

    final rows = <Widget>[];
    for (var r = 0; r < total; r++) {
      final cab = r == 0;
      final l = cab ? cols : linhas[r - 1];
      final ult = r == total - 1;
      String v(int j) => j < l.length ? l[j] : '';
      final bgLinha = !cab && r.isEven ? zebra : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cel(
                v(0),
                ult: ult,
                primeiraCol: true,
                largura: w0,
                bg: cab ? p.surfaceAlt : p.soft(cor, .06),
                st: cab
                    ? TextStyle(fontSize: 12 * e, fontWeight: FontWeight.w700, color: p.inkSoft, letterSpacing: .3)
                    : TextStyle(fontSize: 13 * e, fontWeight: FontWeight.w600, color: p.ink),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _ctl(r),
                  scrollDirection: Axis.horizontal,
                  physics: rola ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = 1; j < n; j++)
                        cel(
                          v(j),
                          ult: ult,
                          primeiraCol: false,
                          largura: cw,
                          bg: cab ? p.soft(cor, .15) : bgLinha,
                          st: cab ? TextStyle(fontSize: 13.5 * e, fontWeight: FontWeight.w700, color: cor) : null,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
        if (rola) _dicaRolar(p),
      ],
    );
  }

  Widget _simples(Pal p, double e, List<String> cols, List<List<String>> linhas, int n, double cw, bool rola) {
    final fs = 13.5 * e;
    final zebra = p.soft(p.ink, p.dark ? .0 : .025);
    TableRow linha(List<String> l, {required bool cab, Color? bg}) => TableRow(
      decoration: BoxDecoration(color: bg),
      children: [
        for (var j = 0; j < n; j++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: MdText(
              j < l.length ? l[j] : '',
              style: cab
                  ? TextStyle(fontSize: 12.5 * e, fontWeight: FontWeight.w700, height: 1.35, color: p.inkSoft)
                  : TextStyle(fontSize: fs, height: 1.4, fontWeight: j == 0 ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
      ],
    );
    final tabela = Table(
      defaultColumnWidth: FixedColumnWidth(cw),
      border: TableBorder(
        horizontalInside: BorderSide(color: p.line),
        verticalInside: BorderSide(color: p.line),
      ),
      children: [
        if (cols.isNotEmpty) linha(cols, cab: true, bg: p.surfaceAlt),
        for (var i = 0; i < linhas.length; i++) linha(linhas[i], cab: false, bg: i.isOdd ? zebra : null),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: rola ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
            child: tabela,
          ),
        ),
        if (rola) _dicaRolar(p),
      ],
    );
  }
}

// ============================================================================
// Fluxo e cartões
// ============================================================================

class _Fluxo extends StatelessWidget {
  final Json bloco;
  final Color cor;
  final double e;
  const _Fluxo({required this.bloco, required this.cor, required this.e});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final passos = _maps(bloco['passos']);
    final titulo = _s(bloco['titulo']);
    final fgNum = p.dark ? p.bg : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titulo.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.route_outlined, size: 19, color: cor),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: mdSpans(titulo, const TextStyle())),
                  style: TextStyle(fontSize: 15.5 * e, fontWeight: FontWeight.w700, height: 1.3, color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < passos.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fgNum),
                        ),
                      ),
                      if (i < passos.length - 1) ...[
                        Expanded(child: Container(width: 2, color: p.soft(cor, .45))),
                        Icon(Icons.arrow_drop_down_rounded, size: 20, color: p.soft(cor, .8)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < passos.length - 1 ? 12 : 0),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_s(passos[i]['titulo']).isNotEmpty)
                            Text.rich(
                              TextSpan(children: mdSpans(_s(passos[i]['titulo']), const TextStyle())),
                              style: TextStyle(
                                fontSize: 14.5 * e,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                                color: p.ink,
                              ),
                            ),
                          if (_s(passos[i]['texto']).isNotEmpty) ...[
                            const SizedBox(height: 3),
                            MdText(
                              _s(passos[i]['texto']),
                              style: TextStyle(fontSize: 14 * e, height: 1.45, color: p.inkSoft),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Cartoes extends StatelessWidget {
  final Json bloco;
  final Color cor;
  final double e;
  const _Cartoes({required this.bloco, required this.cor, required this.e});

  Widget _cartao(Pal p, Json c) => Container(
    padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: p.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_s(c['emoji']).isNotEmpty) ...[
              Container(
                width: 34 * e.clamp(1.0, 1.3),
                height: 34 * e.clamp(1.0, 1.3),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.soft(cor, .12), borderRadius: BorderRadius.circular(10)),
                child: Text(_s(c['emoji']), style: TextStyle(fontSize: 18 * e.clamp(1.0, 1.3))),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text.rich(
                  TextSpan(children: mdSpans(_s(c['titulo']), const TextStyle())),
                  style: TextStyle(fontSize: 14.5 * e, fontWeight: FontWeight.w700, height: 1.3, color: p.ink),
                ),
              ),
            ),
          ],
        ),
        if (_s(c['texto']).isNotEmpty) ...[
          const SizedBox(height: 8),
          MdText(
            _s(c['texto']),
            style: TextStyle(fontSize: 13.8 * e, height: 1.45, color: p.inkSoft),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final itens = _maps(bloco['itens']);
    final titulo = _s(bloco['titulo']);
    final longo = itens.any((c) => _s(c['texto']).length > 120);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titulo.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.dashboard_outlined, size: 19, color: cor),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: mdSpans(titulo, const TextStyle())),
                  style: TextStyle(fontSize: 15.5 * e, fontWeight: FontWeight.w700, height: 1.3, color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        LayoutBuilder(
          builder: (context, cons) {
            final umaColuna = longo || cons.maxWidth < 320 * e.clamp(1.0, 1.4);
            if (umaColuna) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < itens.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == itens.length - 1 ? 0 : 10),
                      child: _cartao(p, itens[i]),
                    ),
                ],
              );
            }
            final linhas = <Widget>[];
            for (var i = 0; i < itens.length; i += 2) {
              final ultimo = i == itens.length - 1;
              linhas.add(
                Padding(
                  padding: EdgeInsets.only(bottom: i + 2 >= itens.length ? 0 : 10),
                  child: ultimo
                      ? _cartao(p, itens[i])
                      : IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _cartao(p, itens[i])),
                              const SizedBox(width: 10),
                              Expanded(child: _cartao(p, itens[i + 1])),
                            ],
                          ),
                        ),
                ),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: linhas);
          },
        ),
      ],
    );
  }
}

// ============================================================================
// Figuras e fotos
// ============================================================================

const _branco = Color(0xFFFFFFFF);

class _Figura extends StatelessWidget {
  final Json bloco;
  final Color cor;
  final double e;
  final Widget? mais;
  const _Figura({required this.bloco, required this.cor, required this.e, this.mais});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ref = _s(bloco['ref']);
    if (ref.isEmpty) return const SizedBox.shrink();
    final asset = 'assets/figuras/$ref.png';
    final legenda = _s(bloco['legenda']);
    final m = mais is _BotaoMais ? (mais as _BotaoMais).branco() : mais;
    return _SeExiste(
      asset: asset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _branco,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Material(
                  color: _branco,
                  child: InkWell(
                    onTap: () => abrir(context, FigureViewer(asset: asset, legenda: legenda, fundoBranco: true)),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        asset,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                if (m != null) Positioned(top: 6, right: 6, child: m),
                const Positioned(
                  right: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xCCFFFFFF), shape: BoxShape.circle),
                      child: Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(Icons.zoom_out_map_rounded, size: 16, color: Color(0xFF5F5B55)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (legenda.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.draw_outlined, size: 15, color: cor),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: MdText(
                      legenda,
                      style: TextStyle(fontSize: 13.5 * e, height: 1.45, color: p.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Foto extends StatelessWidget {
  final Json bloco;
  final Color cor;
  final double e;
  final Widget? mais;
  const _Foto({required this.bloco, required this.cor, required this.e, this.mais});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = AppState.I.fotos[_s(bloco['ref'])];
    if (f == null || _s(f['arquivo']).isEmpty) return const SizedBox.shrink();
    final asset = 'assets/fotos/${_s(f['arquivo'])}';
    final legenda = _s(bloco['legenda']);
    final desc = _s(f['descricao']);
    final col = _s(f['coloracao']);
    final credito = [_s(f['autor']), _s(f['licenca'])].where((x) => x.isNotEmpty).join(' · ');
    final tituloFoto = _s(f['titulo']);
    return _SeExiste(
      asset: asset,
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Material(
                  color: const Color(0xFF101010),
                  child: InkWell(
                    onTap: () => abrir(
                      context,
                      FigureViewer(
                        asset: asset,
                        titulo: tituloFoto.isEmpty ? null : tituloFoto,
                        legenda: legenda,
                        credito: credito.isEmpty ? null : credito,
                      ),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340, minWidth: double.infinity),
                      child: Center(
                        child: Image.asset(
                          asset,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox(height: 0),
                        ),
                      ),
                    ),
                  ),
                ),
                if (mais != null)
                  Positioned(top: 6, right: 6, child: (mais is _BotaoMais) ? (mais as _BotaoMais).branco() : mais!),
                const Positioned(
                  right: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                      child: Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(Icons.zoom_out_map_rounded, size: 16, color: Color(0xFFFFFFFF)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Selo('Microscopia real', cor: cor, icone: Icons.biotech_outlined),
                      if (col.isNotEmpty) Selo(col, cor: p.inkSoft),
                    ],
                  ),
                  if (legenda.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    MdText(
                      legenda,
                      style: TextStyle(fontSize: 14.5 * e, height: 1.45, fontWeight: FontWeight.w500),
                    ),
                  ],
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Rotulo('O que observar', cor: cor),
                    const SizedBox(height: 4),
                    MdText(
                      desc,
                      style: TextStyle(fontSize: 14 * e, height: 1.5, color: p.inkSoft),
                    ),
                  ],
                  if (credito.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Imagem: $credito', style: TextStyle(fontSize: 11, height: 1.3, color: p.inkFaint)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Blocos interativos
// ============================================================================

class _Expansivel extends StatefulWidget {
  final Json bloco;
  final String capId;
  final Color cor;
  final double e;
  final String? alvo;
  final Widget? mais;
  const _Expansivel({
    required this.bloco,
    required this.capId,
    required this.cor,
    required this.e,
    this.alvo,
    this.mais,
  });
  @override
  State<_Expansivel> createState() => _ExpansivelState();
}

class _ExpansivelState extends State<_Expansivel> {
  late bool _aberto = widget.alvo != null && _maps(widget.bloco['blocos']).any((x) => blocoContem(x, widget.alvo!));

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cor = widget.cor;
    final internos = _maps(widget.bloco['blocos']);
    return Container(
      decoration: BoxDecoration(
        color: p.surfaceAlt.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _aberto = !_aberto),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: p.soft(cor, .12), borderRadius: BorderRadius.circular(9)),
                      child: Icon(Icons.layers_outlined, size: 18, color: cor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(children: mdSpans(_s(widget.bloco['titulo']), const TextStyle())),
                            style: TextStyle(
                              fontSize: 14.5 * widget.e,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: p.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _aberto ? 'Toque para recolher' : 'Opcional · toque para abrir',
                            style: TextStyle(fontSize: 11.5, color: p.inkFaint),
                          ),
                        ],
                      ),
                    ),
                    ?widget.mais,
                    AnimatedRotation(
                      turns: _aberto ? .5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.expand_more_rounded, color: p.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _aberto
                  ? Container(
                      color: p.bg,
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final x in internos)
                            BlockView(bloco: x, capId: widget.capId, cor: cor, alvo: widget.alvo),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _Quiz extends StatefulWidget {
  final Json bloco;
  final Color cor;
  final double e;
  final Widget? mais;
  const _Quiz({required this.bloco, required this.cor, required this.e, this.mais});
  @override
  State<_Quiz> createState() => _QuizState();
}

class _QuizState extends State<_Quiz> {
  int? _esc;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final e = widget.e;
    final cor = widget.cor;
    final op = _strs(widget.bloco['opcoes']);
    final correta = (widget.bloco['correta'] as num?)?.toInt() ?? -1;
    final acertou = _esc != null && _esc == correta;
    const letras = 'ABCDEFGH';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.soft(cor, .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, size: 17, color: cor),
              const SizedBox(width: 7),
              Expanded(child: Rotulo('Teste rápido', cor: cor)),
              ?widget.mais,
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MdText(
                  _s(widget.bloco['pergunta']),
                  style: TextStyle(fontSize: 15.5 * e, height: 1.45, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < op.length; i++) ...[
                  _opcao(p, e, letras[i % letras.length], op[i], i, correta),
                  const SizedBox(height: 8),
                ],
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: _esc == null
                      ? const SizedBox(width: double.infinity)
                      : Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
                          decoration: BoxDecoration(
                            color: p.soft(acertou ? p.ok : p.bad, .08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    acertou ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                    size: 18,
                                    color: acertou ? p.ok : p.bad,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      acertou ? 'Isso! Resposta certa.' : 'Não é essa. A certa está marcada em verde.',
                                      style: TextStyle(
                                        fontSize: 14 * e,
                                        fontWeight: FontWeight.w700,
                                        color: acertou ? p.ok : p.bad,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_s(widget.bloco['explicacao']).isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: MdText(
                                    _s(widget.bloco['explicacao']),
                                    style: TextStyle(fontSize: 14.5 * e, height: 1.5),
                                  ),
                                ),
                              ],
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => setState(() => _esc = null),
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text('Tentar de novo'),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _opcao(Pal p, double e, String letra, String texto, int i, int correta) {
    final respondido = _esc != null;
    final certa = respondido && i == correta;
    final errada = respondido && i == _esc && i != correta;
    final c = certa ? p.ok : (errada ? p.bad : null);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: c == null ? p.bg : p.soft(c, .1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c ?? p.line, width: c == null ? 1 : 1.5),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: respondido ? null : () => setState(() => _esc = i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c ?? p.surfaceAlt, shape: BoxShape.circle),
                    child: c == null
                        ? Text(
                            letra,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.inkSoft),
                          )
                        : Icon(certa ? Icons.check_rounded : Icons.close_rounded, size: 15, color: p.surface),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: MdText(texto, style: TextStyle(fontSize: 14.5 * e, height: 1.4)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Revelar extends StatefulWidget {
  final Json bloco;
  final Color cor;
  final double e;
  final Widget? mais;
  const _Revelar({required this.bloco, required this.cor, required this.e, this.mais});
  @override
  State<_Revelar> createState() => _RevelarState();
}

class _RevelarState extends State<_Revelar> {
  bool _vis = false;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final e = widget.e;
    final cor = widget.cor;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.soft(cor, .45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _vis ? null : () => setState(() => _vis = true),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology_alt_outlined, size: 17, color: cor),
                    const SizedBox(width: 7),
                    Expanded(child: Rotulo('Tente lembrar antes de tocar', cor: cor)),
                    if (widget.mais != null) widget.mais! else const SizedBox(height: 40),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: MdText(
                    _s(widget.bloco['pergunta']),
                    style: TextStyle(fontSize: 15.5 * e, height: 1.45, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 240),
                    sizeCurve: Curves.easeOutCubic,
                    crossFadeState: _vis ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    firstChild: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(color: p.soft(cor, .08), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.visibility_outlined, size: 18, color: cor),
                          const SizedBox(width: 8),
                          Text(
                            'Toque para revelar',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cor),
                          ),
                        ],
                      ),
                    ),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                          decoration: BoxDecoration(color: p.soft(cor, .07), borderRadius: BorderRadius.circular(12)),
                          child: MdText(_s(widget.bloco['resposta']), style: TextStyle(fontSize: 15 * e, height: 1.55)),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() => _vis = false),
                            icon: const Icon(Icons.visibility_off_outlined, size: 18),
                            label: const Text('Esconder'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  final List<String> itens;
  final Color cor;
  final double e;
  const _Resumo({required this.itens, required this.cor, required this.e});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fs = 15 * e;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: p.soft(cor, .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.soft(cor, .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.task_alt_rounded, size: 21, color: cor),
              const SizedBox(width: 8),
              Text(
                'Para levar',
                style: TextStyle(fontFamily: kSerif, fontSize: 22 * e, color: p.ink),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < itens.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == itens.length - 1 ? 0 : 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: math.max(0, (fs * 1.5 - 18) / 2)),
                    child: Icon(Icons.check_circle_rounded, size: 18, color: cor),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: MdText(itens[i], style: TextStyle(fontSize: fs, height: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
