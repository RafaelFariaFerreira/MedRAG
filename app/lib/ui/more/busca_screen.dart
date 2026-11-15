import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/rag.dart';
import '../../theme.dart';
import '../flashcards/sessao_flash.dart';
import '../material/chapter_screen.dart';
import '../questions/sessao_questoes.dart';
import '../widgets/common.dart';

const _camposIgnorados = {'id', 'tipo', 'estilo', 'ref', 'emoji', 'correta', 'comparacao', 'ordenada', 'blocos'};

/// Todo o texto legível de um bloco do material (sem entrar nos blocos internos de `expansivel`).
String textoDoBloco(Json b) {
  final out = <String>[];
  void walk(dynamic v) {
    if (v is String) {
      if (v.trim().isNotEmpty) out.add(v);
    } else if (v is List) {
      v.forEach(walk);
    } else if (v is Map) {
      v.forEach((k, x) {
        if (!_camposIgnorados.contains(k)) walk(x);
      });
    }
  }

  walk(b);
  return limparMd(out.join(' · '));
}

/// Busca um bloco pelo id em qualquer nível do capítulo.
Json? blocoPorId(Chapter c, String id) {
  for (final b in c.todosBlocos) {
    if (b['id'] == id) return b;
  }
  return null;
}

String limparMd(String s) =>
    s.replaceAll(RegExp(r'\*\*|__|`|^#+\s*', multiLine: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();

String textoQuestao(Question q) => limparMd([
      q.enunciado,
      for (final a in q.alternativas) '${a['texto'] ?? ''}',
      for (final i in q.itens) '${i['texto'] ?? ''}',
      for (final s in q.subitens) '${s['pergunta'] ?? ''}',
      q.respostaModelo,
      q.explicacao,
    ].where((x) => x.isNotEmpty).join(' · '));

/// Trecho de [texto] ao redor da primeira ocorrência de [termo] (sem acento), com o termo marcado.
TextSpan trechoMarcado(String texto, String termo, TextStyle base, Color marca, {int raio = 70}) {
  final norm = Rag.semAcento(texto);
  final t = Rag.semAcento(termo.trim());
  final i = t.isEmpty || norm.length != texto.length ? -1 : norm.indexOf(t);
  if (i < 0) {
    final corte = texto.length > raio * 2 ? '${texto.substring(0, raio * 2)}…' : texto;
    return TextSpan(text: corte, style: base);
  }
  final ini = (i - raio).clamp(0, texto.length);
  final fim = (i + t.length + raio).clamp(0, texto.length);
  return TextSpan(style: base, children: [
    if (ini > 0) const TextSpan(text: '…'),
    TextSpan(text: texto.substring(ini, i)),
    TextSpan(
        text: texto.substring(i, i + t.length),
        style: TextStyle(fontWeight: FontWeight.w700, backgroundColor: marca)),
    TextSpan(text: texto.substring(i + t.length, fim)),
    if (fim < texto.length) const TextSpan(text: '…'),
  ]);
}

class _ResCap {
  final Chapter cap;
  final String blocoId, texto;
  _ResCap(this.cap, this.blocoId, this.texto);
}

class BuscaScreen extends StatefulWidget {
  const BuscaScreen({super.key});
  @override
  State<BuscaScreen> createState() => _BuscaScreenState();
}

class _BuscaScreenState extends State<BuscaScreen> {
  static const _limite = 30;
  final _c = TextEditingController();
  Timer? _deb;
  String _termo = '';
  List<_ResCap> _caps = [];
  List<Question> _qs = [];
  List<Flashcard> _fcs = [];

  // índice normalizado, montado uma vez
  late final List<(_ResCap, String)> _idxCaps;
  late final List<(Question, String, String)> _idxQs;
  late final List<(Flashcard, String)> _idxFcs;

  @override
  void initState() {
    super.initState();
    final s = AppState.I;
    _idxCaps = [
      for (final m in s.modulos)
        for (final c in m.capitulos)
          for (final b in c.todosBlocos)
            if (b['tipo'] != 'expansivel' && b['id'] != null)
              () {
                final t = textoDoBloco(b);
                return (_ResCap(c, '${b['id']}', t), Rag.semAcento(t));
              }(),
    ];
    _idxQs = [
      for (final q in s.questoes)
        if (q.representante)
          () {
            final t = textoQuestao(q);
            return (q, t, Rag.semAcento(t));
          }(),
    ];
    _idxFcs = [for (final f in s.cartoes) (f, Rag.semAcento('${f.frente} ${f.verso} ${f.dica}'))];
  }

  @override
  void dispose() {
    _deb?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _mudou(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 250), () => _buscar(v));
  }

  void _buscar(String v) {
    final t = Rag.semAcento(v.trim());
    if (!mounted) return;
    setState(() {
      _termo = v.trim();
      if (t.length < 2) {
        _caps = [];
        _qs = [];
        _fcs = [];
        return;
      }
      _caps = [for (final e in _idxCaps) if (e.$2.contains(t)) e.$1];
      _qs = [for (final e in _idxQs) if (e.$3.contains(t)) e.$1];
      _fcs = [for (final e in _idxFcs) if (e.$2.contains(t)) e.$1];
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final total = _caps.length + _qs.length + _fcs.length;
    final base = TextStyle(fontSize: 13.5, height: 1.45, color: p.inkSoft);
    return Scaffold(
      appBar: AppBar(title: const Text('Busca')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _c,
            autofocus: true,
            onChanged: _mudou,
            onSubmitted: _buscar,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Ex.: Reed-Sternberg, psamoma, CD30…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _c.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _c.clear();
                        _buscar('');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: _termo.length < 2
              ? _dica(p, 'Digite pelo menos 2 letras. A busca ignora acentos e maiúsculas e procura no material, '
                  'nas questões das provas e nos flashcards.')
              : total == 0
                  ? _dica(p, 'Nada encontrado para "$_termo". Tente uma palavra só, ou o nome do marcador (ex.: CD15).')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                      children: [
                        if (_caps.isNotEmpty) ...[
                          _cab('Material', _caps.length),
                          for (final r in _caps.take(_limite))
                            _Item(
                              cor: p.modulo(r.cap.modulo),
                              titulo: r.cap.titulo,
                              trecho: trechoMarcado(r.texto, _termo, base, p.marca),
                              onTap: () => abrir(context, ChapterScreen(chapterId: r.cap.id, blocoInicial: r.blocoId)),
                            ),
                        ],
                        if (_qs.isNotEmpty) ...[
                          _cab('Questões', _qs.length),
                          for (final q in _qs.take(_limite))
                            _Item(
                              cor: p.modulo(q.modulo),
                              titulo:
                                  '${AppState.I.provaPorId[q.provaId]?.titulo ?? q.provaId} · questão ${q.numero}',
                              trecho: trechoMarcado(textoQuestao(q), _termo, base, p.marca),
                              onTap: () => abrir(context, SessaoQuestoes(titulo: 'Questão ${q.numero}', questoes: [q])),
                            ),
                        ],
                        if (_fcs.isNotEmpty) ...[
                          _cab('Flashcards', _fcs.length),
                          for (final f in _fcs.take(_limite))
                            _Item(
                              cor: p.modulo(f.modulo),
                              titulo: limparMd(f.frente),
                              trecho: trechoMarcado(limparMd(f.verso), _termo, base, p.marca),
                              onTap: () => abrir(context, SessaoFlash(titulo: 'Da busca', cartoes: [f])),
                            ),
                        ],
                      ],
                    ),
        ),
      ]),
    );
  }

  Widget _dica(Pal p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.5, color: p.inkSoft)),
        ),
      );

  Widget _cab(String t, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Rotulo(n > _limite ? '$t · mostrando $_limite de $n' : '$t · $n'),
      );
}

class _Item extends StatelessWidget {
  final Color cor;
  final String titulo;
  final InlineSpan trecho;
  final VoidCallback onTap;
  const _Item({required this.cor, required this.titulo, required this.trecho, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Painel(
        onTap: onTap,
        raio: 14,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 4,
            height: 36,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(99)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink, height: 1.3)),
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [trecho]), maxLines: 4, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}
