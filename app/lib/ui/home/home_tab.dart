import 'dart:async';

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import 'plano.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) => const _Home();
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  Timer? _relogio;
  final Set<String> _abertos = {};

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && AppState.I.inicioEstudo != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  String _saudacao() {
    final h = DateTime.now().hour;
    final s = h < 5 ? 'Boa madrugada' : h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite';
    final n = AppState.I.nome.trim();
    return n.isEmpty ? s : '$s, $n';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final atual = blocoAtual();
        return ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            TituloAba(_saudacao(), sub: 'P2 de Anatomia Patológica II · Tireoide, linfadenopatias e linfomas'),
            const Padding(padding: EdgeInsets.fromLTRB(16, 6, 16, 0), child: _CartaoHeroi()),
            const Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 0), child: _ComoEstudar()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: atual == null ? const _PlanoConcluido() : _CartaoAgora(bloco: atual),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(20, 26, 20, 8), child: Rotulo('O plano inteiro')),
            for (final b in plano)
              if (!identical(b, atual))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _BlocoRecolhido(
                    bloco: b,
                    aberto: _abertos.contains(b.id),
                    onToggle: () => setState(() => _abertos.contains(b.id) ? _abertos.remove(b.id) : _abertos.add(b.id)),
                  ),
                ),
            const Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, 8), child: Rotulo('Seu progresso')),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: _PainelProgresso()),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ herói

class _CartaoHeroi extends StatelessWidget {
  const _CartaoHeroi();

  Future<void> _reiniciar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reiniciar o relógio?'),
        content: const Text('O tempo volta a zero. As tarefas que você marcou continuam marcadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reiniciar')),
        ],
      ),
    );
    if (ok == true) await AppState.I.setPref('inicio_estudo', '${DateTime.now().millisecondsSinceEpoch}');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = AppState.I;
    final pr = progressoPlano();
    final inicio = s.inicioEstudo;

    if (inicio == null) {
      return Painel(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sua maratona de 12h', style: TextStyle(fontFamily: kSerif, fontSize: 24, height: 1.15, color: p.ink)),
          const SizedBox(height: 8),
          Text(
            '${plano.length} blocos curtos, um módulo por vez, com questões das provas antigas no meio e dois '
            'simulados no fim. Você decide o ritmo: o plano só organiza o caminho.',
            style: TextStyle(fontSize: 14.5, height: 1.5, color: p.inkSoft),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in ['tireoide', 'linfadenopatias', 'linfomas'])
              Selo(moduloNome(m), cor: p.modulo(m), icone: moduloIcone(m)),
            Selo('2 simulados', cor: p.primary, icone: Icons.assignment_outlined),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => s.setPref('inicio_estudo', '${DateTime.now().millisecondsSinceEpoch}'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Começar agora'),
            ),
          ),
        ]),
      );
    }

    final decorrido = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(inicio)).inMinutes.clamp(0, 1 << 30);
    final restante = (minutosPlano - decorrido).clamp(0, minutosPlano);
    final atual = blocoAtual();
    final fimAtual = atual == null ? 0 : inicioDoBloco(atual) + atual.minutos;
    final atraso = atual == null ? 0 : decorrido - fimAtual;

    return Painel(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Sua maratona de 12h',
                style: TextStyle(fontFamily: kSerif, fontSize: 22, height: 1.15, color: p.ink)),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: p.inkSoft),
            tooltip: 'Opções',
            onSelected: (_) => _reiniciar(context),
            itemBuilder: (_) => const [PopupMenuItem(value: 'r', child: Text('Reiniciar o relógio'))],
          ),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _Numero(fmtMin(decorrido), 'estudando')),
              Expanded(
                child: _Numero(
                    restante == 0 ? '12h completas' : fmtMin(restante), restante == 0 ? 'missão cumprida' : 'para fechar 12h'),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Barra(pr.total == 0 ? 0 : pr.feitas / pr.total, cor: p.primary, altura: 7)),
              const SizedBox(width: 10),
              Text('${pr.feitas}/${pr.total} tarefas',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.inkSoft)),
            ]),
            if (atraso > 15) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(color: p.soft(p.warn), borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.schedule_rounded, size: 18, color: p.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Você está uns ${fmtMin(atraso)} atrás do plano. Normal. Para recuperar, fique no essencial '
                      'de cada capítulo (deixe os "Aprofundar" fechados) e não pule as questões.',
                      style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Numero extends StatelessWidget {
  final String valor, rotulo;
  const _Numero(this.valor, this.rotulo);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.ink, height: 1.2)),
      Text(rotulo, style: TextStyle(fontSize: 12.5, color: p.inkSoft)),
    ]);
  }
}

class _ComoEstudar extends StatelessWidget {
  const _ComoEstudar();
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(Icons.psychology_alt_outlined, size: 18, color: p.inkSoft),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Ritmo que funciona: ', style: TextStyle(fontWeight: FontWeight.w700, color: p.ink)),
            const TextSpan(
                text: 'leia uma seção → feche → diga em voz alta o que lembra → faça a questão. '
                    'O que não voltou é o que você relê.'),
          ]),
          style: TextStyle(fontSize: 13.5, height: 1.45, color: p.inkSoft),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ bloco atual

class _CartaoAgora extends StatelessWidget {
  final BlocoPlano bloco;
  const _CartaoAgora({required this.bloco});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cor = bloco.modulo == null ? p.primary : p.modulo(bloco.modulo!);
    final inicio = AppState.I.inicioEstudo;
    return Painel(
      borda: p.soft(cor, .45),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Rotulo('Agora', cor: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                bloco.pausa ? 'Pausa' : 'Bloco ${bloco.numero}',
                fmtMin(bloco.minutos),
                if (inicio != null) _horario(inicio, bloco),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.inkSoft),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(bloco.titulo, style: TextStyle(fontFamily: kSerif, fontSize: 24, height: 1.15, color: p.ink)),
        const SizedBox(height: 6),
        Text(bloco.objetivo, style: TextStyle(fontSize: 14.5, height: 1.45, color: p.inkSoft)),
        const SizedBox(height: 8),
        for (final t in bloco.tarefas) _LinhaTarefa(bloco: bloco, tarefa: t, cor: cor),
        const SizedBox(height: 8),
        const _Cronometro(),
      ]),
    );
  }
}

String _horario(int inicio, BlocoPlano b) {
  final ini = DateTime.fromMillisecondsSinceEpoch(inicio).add(Duration(minutes: inicioDoBloco(b)));
  final fim = ini.add(Duration(minutes: b.minutos));
  String f(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '${f(ini)}–${f(fim)}';
}

class _PlanoConcluido extends StatelessWidget {
  const _PlanoConcluido();
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Painel(
      child: Row(children: [
        Icon(Icons.nightlight_outlined, color: p.ok, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Plano concluído. Agora durma: é no sono que a memória consolida. Amanhã, só uma passada leve nos quadros.',
            style: TextStyle(fontSize: 14.5, height: 1.45, color: p.ink),
          ),
        ),
      ]),
    );
  }
}

class _LinhaTarefa extends StatelessWidget {
  final BlocoPlano bloco;
  final Tarefa tarefa;
  final Color cor;
  const _LinhaTarefa({required this.bloco, required this.tarefa, required this.cor});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final feito = tarefaFeita(bloco, tarefa);
    final disp = tarefaDisponivel(tarefa);
    final destino = tarefaTemDestino(tarefa) && disp;
    final min = minutosTarefa(tarefa);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: destino ? () => abrirTarefa(context, tarefa) : () => alternarTarefa(bloco, tarefa, !feito),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: feito,
              activeColor: cor,
              side: BorderSide(color: p.inkFaint, width: 1.5),
              onChanged: (v) => alternarTarefa(bloco, tarefa, v ?? false),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  tituloTarefa(tarefa),
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.35,
                    color: !disp ? p.inkFaint : feito ? p.inkSoft : p.ink,
                    decoration: feito ? TextDecoration.lineThrough : null,
                    decorationColor: p.inkFaint,
                  ),
                ),
                if (!disp)
                  Text('Ainda não disponível', style: TextStyle(fontSize: 12, color: p.inkFaint))
                else if (min != null)
                  Text('~$min min', style: TextStyle(fontSize: 12, color: p.inkFaint)),
              ]),
            ),
          ),
          if (destino) Icon(Icons.chevron_right_rounded, color: p.inkFaint),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ cronômetro de foco

class _Cronometro extends StatefulWidget {
  const _Cronometro();
  @override
  State<_Cronometro> createState() => _CronometroState();
}

class _CronometroState extends State<_Cronometro> {
  static const _foco = 50 * 60, _pausa = 10 * 60;
  bool _emFoco = true;
  int _restante = _foco; // segundos (quando parado)
  DateTime? _fim; // quando rodando
  Timer? _t;

  int get _total => _emFoco ? _foco : _pausa;
  int get _agora => _fim == null ? _restante : _fim!.difference(DateTime.now()).inSeconds.clamp(0, _total);

  void _iniciar() {
    _fim = DateTime.now().add(Duration(seconds: _restante));
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    setState(() {});
  }

  void _pausar() {
    _restante = _agora;
    _fim = null;
    _t?.cancel();
    setState(() {});
  }

  void _zerar() {
    _t?.cancel();
    _fim = null;
    _emFoco = true;
    _restante = _foco;
    setState(() {});
  }

  void _tick() {
    if (!mounted) return;
    if (_agora <= 0) {
      _t?.cancel();
      _fim = null;
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 180), HapticFeedback.lightImpact);
      _emFoco = !_emFoco;
      _restante = _total;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = _agora;
    final rodando = _fim != null;
    final cor = _emFoco ? p.primary : p.ok;
    final mm = (s ~/ 60).toString().padLeft(2, '0'), ss = (s % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            value: 1 - s / _total,
            strokeWidth: 3.5,
            backgroundColor: p.soft(cor, .18),
            valueColor: AlwaysStoppedAnimation(cor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$mm:$ss',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: p.ink, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(_emFoco ? 'Foco · 50 min' : 'Pausa · 10 min, levante', style: TextStyle(fontSize: 12, color: p.inkSoft)),
          ]),
        ),
        IconButton(
          tooltip: rodando ? 'Pausar' : 'Iniciar',
          onPressed: rodando ? _pausar : _iniciar,
          icon: Icon(rodando ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cor),
        ),
        IconButton(
          tooltip: 'Zerar',
          onPressed: _zerar,
          icon: Icon(Icons.restart_alt_rounded, color: p.inkSoft),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ demais blocos

class _BlocoRecolhido extends StatelessWidget {
  final BlocoPlano bloco;
  final bool aberto;
  final VoidCallback onToggle;
  const _BlocoRecolhido({required this.bloco, required this.aberto, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final feito = blocoFeito(bloco);
    final cor = bloco.modulo == null ? p.primary : p.modulo(bloco.modulo!);
    final n = bloco.tarefas.where((t) => tarefaFeita(bloco, t)).length;
    final inicio = AppState.I.inicioEstudo;
    return Opacity(
      opacity: feito && !aberto ? .6 : 1,
      child: Painel(
        padding: EdgeInsets.zero,
        raio: 14,
        child: Column(children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: feito ? p.soft(p.ok, .16) : p.soft(cor), shape: BoxShape.circle),
                  child: feito
                      ? Icon(Icons.check_rounded, size: 18, color: p.ok)
                      : bloco.pausa
                          ? Icon(Icons.local_cafe_outlined, size: 16, color: cor)
                          : Text('${bloco.numero}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cor)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(bloco.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink)),
                    Text(
                      [fmtMin(bloco.minutos), '$n/${bloco.tarefas.length}', if (inicio != null) _horario(inicio, bloco)]
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                    ),
                  ]),
                ),
                AnimatedRotation(
                  turns: aberto ? .5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded, color: p.inkFaint),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !aberto
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Divider(height: 1, color: p.line),
                      const SizedBox(height: 10),
                      Text(bloco.objetivo, style: TextStyle(fontSize: 13.5, height: 1.45, color: p.inkSoft)),
                      const SizedBox(height: 4),
                      for (final t in bloco.tarefas) _LinhaTarefa(bloco: bloco, tarefa: t, cor: cor),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ progresso

class _PainelProgresso extends StatelessWidget {
  const _PainelProgresso();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = AppState.I;
    final dominados = s.cartoes.where(s.cartaoDominado).length;
    return Painel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final m in s.modulos) ...[
          _LinhaModulo(modulo: m.id, titulo: m.titulo),
          const SizedBox(height: 14),
        ],
        if (s.modulos.isEmpty) ...[
          Text('O conteúdo ainda está carregando.', style: TextStyle(color: p.inkSoft)),
          const SizedBox(height: 14),
        ],
        Row(children: [
          Icon(Icons.style_outlined, size: 18, color: p.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Flashcards dominados', style: TextStyle(fontSize: 14, color: p.ink)),
          ),
          Text('$dominados de ${s.cartoes.length}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink)),
        ]),
      ]),
    );
  }
}

class _LinhaModulo extends StatelessWidget {
  final String modulo, titulo;
  const _LinhaModulo({required this.modulo, required this.titulo});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = AppState.I;
    final cor = p.modulo(modulo);
    final caps = s.capitulos.values.where((c) => c.modulo == modulo).toList();
    final lidos = caps.where((c) => s.capFeito[c.id] ?? false).length;
    final d = s.desempenho(s.questoes.where((q) => q.modulo == modulo && q.representante && !q.foraDoEscopo));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(moduloIcone(modulo), size: 17, color: cor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(titulo,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink)),
        ),
        if (d.media != null)
          Text('${(d.media! * 100).round()}% de acerto',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cor)),
      ]),
      const SizedBox(height: 6),
      Barra(caps.isEmpty ? 0 : lidos / caps.length, cor: cor),
      const SizedBox(height: 5),
      Text('$lidos/${caps.length} capítulos lidos · ${d.feitas}/${d.total} questões feitas',
          style: TextStyle(fontSize: 12.5, color: p.inkSoft)),
    ]);
  }
}
