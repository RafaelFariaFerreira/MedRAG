import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/copilot.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import 'question_widgets.dart';

class SessaoQuestoes extends StatefulWidget {
  const SessaoQuestoes({super.key, required this.titulo, required this.questoes, this.simulado = false});
  final String titulo;
  final List<Question> questoes;
  final bool simulado;

  @override
  State<SessaoQuestoes> createState() => _SessaoQuestoesState();
}

class _SessaoQuestoesState extends State<SessaoQuestoes> {
  late final List<QuestaoCtrl> _ctrls = [for (final q in widget.questoes) QuestaoCtrl(q)];
  final _pg = PageController();
  final _sw = Stopwatch();
  int _pagina = 0;
  late TelaCtx _ctx;

  int get _n => _ctrls.length;
  bool get _naFinal => _pagina >= _n;

  static const _sugestoes = [
    'Me dê uma dica sem entregar a resposta',
    'Por que as outras alternativas estão erradas?',
    'Explique o conceito por trás desta questão',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.simulado) _sw.start();
    _ctx = _ctxPara(0);
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    _pg.dispose();
    super.dispose();
  }

  TelaCtx _ctxPara(int i) {
    if (i >= _n) {
      return TelaCtx(
        'Resultado · ${widget.titulo}',
        _resumoTexto,
        sugestoes: const ['O que eu devo revisar primeiro?', 'Explique os conceitos das questões que errei'],
      );
    }
    final c = _ctrls[i];
    return TelaCtx('Questão ${c.q.numero} · ${tituloProva(c.q)}', c.contexto, sugestoes: _sugestoes);
  }

  void _irPara(int i) {
    FocusManager.instance.primaryFocus?.unfocus();
    if ((i - _pagina).abs() > 1) {
      _pg.jumpToPage(i);
    } else {
      _pg.animateToPage(i, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    }
  }

  void _mudouPagina(int i) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _pagina = i;
      _ctx = _ctxPara(i);
    });
    if (widget.simulado) _naFinal ? _sw.stop() : _sw.start();
  }

  // ------------------------------------------------------------------ resultado (dados)

  ({List<int> feitas, List<int> erradas, List<int> semResposta, double? media}) get _placar {
    final feitas = <int>[], erradas = <int>[], sem = <int>[];
    var soma = 0.0;
    for (var i = 0; i < _n; i++) {
      final c = _ctrls[i];
      if (c.respondida) {
        feitas.add(i);
        soma += c.nota!;
        if (c.nota! < .7) erradas.add(i);
      } else {
        sem.add(i);
      }
    }
    return (feitas: feitas, erradas: erradas, semResposta: sem, media: feitas.isEmpty ? null : soma / feitas.length);
  }

  List<({String topico, double media, int n})> _porTopico(List<int> feitas) {
    final m = <String, List<double>>{};
    for (final i in feitas) {
      for (final t in _ctrls[i].q.topicos) {
        m.putIfAbsent(t, () => []).add(_ctrls[i].nota!);
      }
    }
    final out = [
      for (final e in m.entries)
        (topico: e.key, media: e.value.reduce((a, b) => a + b) / e.value.length, n: e.value.length),
    ]..sort((a, b) => a.media.compareTo(b.media));
    return out;
  }

  String _resumoTexto() {
    final r = _placar;
    final b = StringBuffer('Resultado da sessão "${widget.titulo}": ');
    b.writeln(
      r.media == null
          ? 'nenhuma questão respondida ainda.'
          : '${pct(r.media!)} de aproveitamento em ${r.feitas.length} de $_n questões.',
    );
    for (final t in _porTopico(r.feitas)) {
      b.writeln('- ${topicoNome(t.topico)}: ${pct(t.media)} (${t.n} questões)');
    }
    if (r.erradas.isNotEmpty) {
      b.writeln('Questões que ela errou:');
      for (final i in r.erradas) {
        final q = _ctrls[i].q;
        b.writeln('- ${tituloProva(q)} Q${q.numero} (${pct(_ctrls[i].nota!)}): ${_resumo(q.enunciado, 160)}');
      }
    }
    return b.toString();
  }

  static String _resumo(String s, int n) {
    final t = s.replaceAll(RegExp(r'\*+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= n ? t : '${t.substring(0, n)}…';
  }

  void _refazerErradas(List<int> erradas) {
    final qs = [for (final i in erradas) _ctrls[i].q];
    // lacunas recomeçam em branco (as anotações continuam)
    for (final q in qs.where((q) => q.tipo == 'lacunas')) {
      for (var i = 0; i < q.lacunas.length; i++) {
        AppState.I.salvarResposta(q.id, '$i', '');
      }
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessaoQuestoes(titulo: 'Refazer erradas', questoes: qs),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (_n == 0) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.titulo)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 40, color: p.inkFaint),
                const SizedBox(height: 12),
                Text(
                  'Nenhuma questão neste filtro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: p.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'Escolha outro tema ou formato na aba Questões.',
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
    final teclado = MediaQuery.viewInsetsOf(context).bottom > 0;
    return CtxCopiloto(
      ctx: _ctx,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.titulo, overflow: TextOverflow.ellipsis),
          actions: [
            if (widget.simulado)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _Cronometro(sw: _sw),
              ),
          ],
        ),
        body: Column(
          children: [
            _topo(context),
            Expanded(
              child: PageView.builder(
                controller: _pg,
                itemCount: _n + 1,
                onPageChanged: _mudouPagina,
                itemBuilder: (_, i) => i == _n
                    ? _resultado(context)
                    : QuestaoCard(key: ValueKey('q$i-${_ctrls[i].q.id}'), ctrl: _ctrls[i]),
              ),
            ),
            if (!teclado && !_naFinal) _navegacao(context),
          ],
        ),
      ),
    );
  }

  Widget _topo(BuildContext context) {
    final p = context.pal;
    final atual = _naFinal ? _n : _pagina + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 8, 6),
      child: Row(
        children: [
          Expanded(child: Barra(atual / _n, cor: p.primary, altura: 5)),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _mapa,
            style: TextButton.styleFrom(
              foregroundColor: p.inkSoft,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(44, 40),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _naFinal ? 'Resultado' : '$atual de $_n',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mapa das questões da sessão (pular direto para uma delas).
  void _mapa() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final p = ctx.pal;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Rotulo('Ir para a questão'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _n; i++)
                      Builder(
                        builder: (_) {
                          final c = _ctrls[i];
                          final cor = !c.respondida ? p.inkSoft : (c.nota! >= .7 ? p.ok : p.bad);
                          final atual = i == _pagina;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _irPara(i);
                            },
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.respondida ? p.soft(cor) : p.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: atual ? p.primary : p.line, width: atual ? 2 : 1),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(fontWeight: FontWeight.w700, color: cor),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _irPara(_n);
                    },
                    child: const Text('Ver resultado'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _navegacao(BuildContext context) {
    final p = context.pal;
    final ultima = _pagina == _n - 1;
    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pagina == 0 ? null : () => _irPara(_pagina - 1),
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                label: const Text('Anterior'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.fromLTRB(10, 12, 16, 12)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _irPara(_pagina + 1),
                style: FilledButton.styleFrom(padding: const EdgeInsets.fromLTRB(18, 12, 10, 12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ultima ? 'Ver resultado' : 'Próxima'),
                    const SizedBox(width: 2),
                    Icon(ultima ? Icons.flag_outlined : Icons.chevron_right_rounded, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultado(BuildContext context) {
    final p = context.pal;
    final r = _placar;
    final topicos = _porTopico(r.feitas);
    final media = r.media;
    final corMedia = media == null ? p.inkSoft : (media >= .7 ? p.ok : (media >= .5 ? p.warn : p.bad));
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        Text(
          'Resultado',
          style: TextStyle(fontFamily: kSerif, fontSize: 28, color: p.ink),
        ),
        const SizedBox(height: 12),
        Painel(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Text(
                media == null ? '—' : pct(media),
                style: TextStyle(fontFamily: kSerif, fontSize: 46, height: 1, color: corMedia),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'aproveitamento',
                      style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
                    ),
                    const SizedBox(height: 3),
                    Text('${r.feitas.length} de $_n respondidas', style: TextStyle(color: p.inkSoft, fontSize: 13.5)),
                    if (widget.simulado)
                      Text('Tempo: ${fmtDuracao(_sw.elapsed)}', style: TextStyle(color: p.inkSoft, fontSize: 13.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (r.feitas.isEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Você ainda não respondeu nenhuma questão desta sessão.',
            style: TextStyle(color: p.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => _irPara(0), child: const Text('Começar pela primeira')),
          ),
        ],
        if (topicos.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Rotulo('Por tópico'),
          const SizedBox(height: 10),
          Painel(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              children: [
                for (final t in topicos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                topicoNome(t.topico),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, color: p.ink),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${pct(t.media)} · ${t.n}',
                              style: TextStyle(fontSize: 12.5, color: p.inkSoft, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Barra(t.media, cor: p.modulo(moduloDoTopico(t.topico)), altura: 5),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (r.erradas.isNotEmpty) ...[
          const SizedBox(height: 22),
          Rotulo('Para rever (${r.erradas.length})'),
          const SizedBox(height: 10),
          for (final i in r.erradas)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Painel(
                raio: 14,
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                onTap: () => _irPara(i),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tituloProva(_ctrls[i].q)} · Q${_ctrls[i].q.numero}',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.inkSoft),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _resumo(_ctrls[i].q.enunciado, 140),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: p.ink, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      pct(_ctrls[i].nota!),
                      style: TextStyle(fontWeight: FontWeight.w700, color: p.bad),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.inkFaint),
                  ],
                ),
              ),
            ),
        ],
        if (r.semResposta.isNotEmpty && r.feitas.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r.semResposta.length} ${r.semResposta.length == 1 ? 'questão ficou' : 'questões ficaram'} sem resposta.',
                  style: TextStyle(color: p.inkSoft, fontSize: 13.5),
                ),
              ),
              TextButton(onPressed: () => _irPara(r.semResposta.first), child: const Text('Ir para ela')),
            ],
          ),
        ],
        const SizedBox(height: 22),
        if (r.erradas.isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _refazerErradas(r.erradas),
              icon: const Icon(Icons.replay_rounded, size: 19),
              label: Text('Refazer as erradas (${r.erradas.length})'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: () => _irPara(_n - 1), child: const Text('Voltar para as questões')),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Encerrar sessão')),
        ),
      ],
    );
  }
}

String fmtDuracao(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String dois(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${dois(m)}:${dois(s)}' : '${dois(m)}:${dois(s)}';
}

class _Cronometro extends StatefulWidget {
  final Stopwatch sw;
  const _Cronometro({required this.sw});
  @override
  State<_Cronometro> createState() => _CronometroState();
}

class _CronometroState extends State<_Cronometro> {
  late final Timer _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final parado = !widget.sw.isRunning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(parado ? Icons.pause_rounded : Icons.timer_outlined, size: 16, color: p.inkSoft),
          const SizedBox(width: 5),
          Text(
            fmtDuracao(widget.sw.elapsed),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: p.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
