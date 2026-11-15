import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../services/copilot.dart';
import '../../theme.dart';

/// Cartão base do app.
class Painel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borda;
  final VoidCallback? onTap;
  final double raio;
  const Painel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borda,
    this.onTap,
    this.raio = 18,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = BorderRadius.circular(raio);
    return Material(
      color: color ?? p.surface,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: borda ?? p.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class Selo extends StatelessWidget {
  final String texto;
  final Color cor;
  final IconData? icone;
  final bool cheio;
  const Selo(this.texto, {super.key, required this.cor, this.icone, this.cheio = false});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(color: cheio ? cor : p.soft(cor), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icone != null) ...[
          Icon(icone, size: 12.5, color: cheio ? p.surface : cor),
          const SizedBox(width: 4),
        ],
        Text(texto,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: cheio ? p.surface : cor, letterSpacing: .1)),
      ]),
    );
  }
}

class Rotulo extends StatelessWidget {
  final String texto;
  final Color? cor;
  const Rotulo(this.texto, {super.key, this.cor});
  @override
  Widget build(BuildContext context) => Text(texto.toUpperCase(),
      style: TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: cor ?? context.pal.inkSoft));
}

class Barra extends StatelessWidget {
  final double valor;
  final Color cor;
  final double altura;
  const Barra(this.valor, {super.key, required this.cor, this.altura = 6});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: valor.clamp(0, 1).toDouble(),
          minHeight: altura,
          backgroundColor: context.pal.soft(cor, .14),
          valueColor: AlwaysStoppedAnimation(cor),
        ),
      );
}

Color corPrioridade(Pal p, String pr) => switch (pr) { 'alta' => p.bad, 'media' => p.warn, _ => p.inkSoft };
String nomePrioridade(String pr) =>
    switch (pr) { 'alta' => 'Cai muito', 'media' => 'Cai às vezes', _ => 'Cai pouco' };

String fonteGabarito(String f) => switch (f) {
      'oficial' => 'Gabarito oficial',
      'foto' => 'Gabarito conferido na foto',
      'aluno' => 'Gabarito de aluno',
      'chat' => 'Gabarito de IA (conferir)',
      'notebooklm' => 'Gabarito de IA (conferir)',
      'misto' => 'Gabarito misto',
      _ => 'Gabarito deduzido do resumo',
    };

/// Registra no copiloto o que esta tela está mostrando enquanto ela estiver aberta.
class CtxCopiloto extends StatefulWidget {
  final TelaCtx ctx;
  final Widget child;
  const CtxCopiloto({super.key, required this.ctx, required this.child});
  @override
  State<CtxCopiloto> createState() => _CtxCopilotoState();
}

class _CtxCopilotoState extends State<CtxCopiloto> {
  late TelaCtx _atual;
  @override
  void initState() {
    super.initState();
    _atual = widget.ctx;
    Copiloto.I.entrar(_atual);
  }

  @override
  void didUpdateWidget(CtxCopiloto old) {
    super.didUpdateWidget(old);
    if (!identical(widget.ctx, _atual)) {
      Copiloto.I.trocar(_atual, widget.ctx);
      _atual = widget.ctx;
    }
  }

  @override
  void dispose() {
    Copiloto.I.sair(_atual);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Campo de anotação que salva sozinho (com atraso) na tabela `notes`.
class CampoNota extends StatefulWidget {
  final String kind, ref;
  final String dica;
  final int minLinhas;
  final String? rotulo;
  const CampoNota({
    super.key,
    required this.kind,
    required this.ref,
    this.dica = 'Escreva sua anotação…',
    this.minLinhas = 2,
    this.rotulo,
  });
  @override
  State<CampoNota> createState() => _CampoNotaState();
}

class _CampoNotaState extends State<CampoNota> {
  late final TextEditingController _c;
  bool _salvo = true;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: AppState.I.nota(widget.kind, widget.ref));
  }

  @override
  void dispose() {
    if (!_salvo) AppState.I.salvarNota(widget.kind, widget.ref, _c.text);
    _c.dispose();
    super.dispose();
  }

  int _seq = 0;
  void _mudou(String v) {
    _salvo = false;
    final s = ++_seq;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || s != _seq) return;
      AppState.I.salvarNota(widget.kind, widget.ref, v);
      _salvo = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: p.nota,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.soft(p.warn, .35)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.edit_note_rounded, size: 17, color: p.warn),
          const SizedBox(width: 5),
          Text(widget.rotulo ?? 'Minha anotação',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.warn)),
        ]),
        TextField(
          controller: _c,
          onChanged: _mudou,
          minLines: widget.minLinhas,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(fontSize: 14.5, height: 1.45, color: p.ink),
          decoration: InputDecoration(
            hintText: widget.dica,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ]),
    );
  }
}

/// Cabeçalho grande de aba.
class TituloAba extends StatelessWidget {
  final String titulo;
  final String? sub;
  final Widget? acao;
  const TituloAba(this.titulo, {super.key, this.sub, this.acao});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: TextStyle(fontFamily: kSerif, fontSize: 30, height: 1.1, color: p.ink)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!, style: TextStyle(fontSize: 14, color: p.inkSoft, height: 1.35)),
            ],
          ]),
        ),
        ?acao,
      ]),
    );
  }
}

void abrir(BuildContext context, Widget tela) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => tela));

String fmtMin(int m) => m < 60 ? '$m min' : '${m ~/ 60}h${m % 60 == 0 ? '' : (m % 60).toString().padLeft(2, '0')}';
