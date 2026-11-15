import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../services/copilot.dart';
import 'flashcards/flashcards_tab.dart';
import 'home/home_tab.dart';
import 'home/plano.dart';
import 'material/material_tab.dart';
import 'more/mais_tab.dart';
import 'questions/questoes_tab.dart';
import 'widgets/common.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _aba = 0;
  Timer? _tick;

  static final _ctxs = <TelaCtx>[
    TelaCtx('Início · plano de 12h', textoPlanoParaCopiloto, sugestoes: const [
      'Por onde eu começo com 12h?',
      'Estou atrasada no plano. O que eu corto?',
      'Me faça 5 perguntas rápidas de tireoide',
    ]),
    TelaCtx('Material', _textoMaterial, sugestoes: const [
      'Qual capítulo mais cai na prova?',
      'Me dê um mapa mental dos linfomas',
      'Compare Graves e Hashimoto lado a lado',
    ]),
    TelaCtx('Questões', _textoQuestoes, sugestoes: const [
      'Quais assuntos mais caem nas provas antigas?',
      'Como o professor corrige a discursiva?',
      'Quais são as pegadinhas clássicas do professor?',
    ]),
    TelaCtx('Flashcards', _textoFlash, sugestoes: const [
      'Me teste com 5 perguntas de imuno-histoquímica',
      'Crie um mnemônico para os subtipos de Hodgkin',
      'Quais marcadores eu preciso decorar?',
    ]),
    TelaCtx('Mais', () => '', sugestoes: const [
      'O que mais pesa na prova?',
      'Quais questões se repetem entre provas?',
      'Como montar um diagnóstico completo de linfoma?',
    ]),
  ];

  static String _textoMaterial() {
    final s = AppState.I;
    final b = StringBuffer('Lista de capítulos do material (✓ = lido):\n');
    for (final m in s.modulos) {
      b.writeln('${m.titulo}:');
      for (final c in m.capitulos) {
        b.writeln('  ${(s.capFeito[c.id] ?? false) ? '✓' : '○'} ${c.titulo} (${c.minutos} min, prioridade ${c.prioridade})');
      }
    }
    return b.toString();
  }

  static String _textoQuestoes() {
    final s = AppState.I;
    final b = StringBuffer('Banco de questões das provas antigas:\n');
    for (final p in s.provas) {
      final d = s.desempenho(s.questoes.where((q) => q.provaId == p.id));
      b.writeln('${p.titulo} (${p.temas}): ${d.feitas}/${d.total} feitas'
          '${d.media == null ? '' : ', aproveitamento ${(d.media! * 100).round()}%'}');
    }
    return b.toString();
  }

  static String _textoFlash() {
    final s = AppState.I;
    final venc = s.cartoes.where(s.cartaoVencido).length;
    final dom = s.cartoes.where(s.cartaoDominado).length;
    final novos = s.cartoes.where(s.cartaoNovo).length;
    return 'Flashcards: ${s.cartoes.length} no total, $novos novos, $venc vencidos para revisar, $dom dominados.';
  }

  @override
  void initState() {
    super.initState();
    // os flashcards vencem com o tempo: atualiza o selo de vez em quando
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _perguntarNome());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _perguntarNome() async {
    if (!mounted || AppState.I.nome.trim().isNotEmpty) return;
    final c = TextEditingController();
    final k = TextEditingController(text: AppState.I.apiKey);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Vamos começar'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Como posso te chamar?', hintText: 'Seu nome'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: k,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Chave da API da Anthropic',
              hintText: 'sk-ant-…',
              helperText: 'Opcional agora; dá para colar depois em Mais › Configurações.',
              helperMaxLines: 2,
            ),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pronto'))],
      ),
    );
    final n = c.text.trim();
    final chave = k.text.trim();
    c.dispose();
    k.dispose();
    if (ok != true) return;
    await AppState.I.setPref('nome', n.isEmpty ? 'Estudante' : n);
    if (chave.isNotEmpty) await AppState.I.setPref('api_key', chave);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _aba == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _aba = 0);
      },
      child: CtxCopiloto(
        ctx: _ctxs[_aba],
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _aba,
              children: const [HomeTab(), MaterialTab(), QuestoesTab(), FlashcardsTab(), MaisTab()],
            ),
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: AppState.I,
            builder: (context, _) {
              final s = AppState.I;
              final venc = s.cartoes.where(s.cartaoVencido).length;
              return NavigationBar(
                selectedIndex: _aba,
                onDestinationSelected: (i) => setState(() => _aba = i),
                destinations: [
                  const NavigationDestination(
                      icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Início'),
                  const NavigationDestination(
                      icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Material'),
                  const NavigationDestination(
                      icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Questões'),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: venc > 0,
                      label: Text(venc > 99 ? '99+' : '$venc'),
                      child: const Icon(Icons.style_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: venc > 0,
                      label: Text(venc > 99 ? '99+' : '$venc'),
                      child: const Icon(Icons.style),
                    ),
                    label: 'Flashcards',
                  ),
                  const NavigationDestination(
                      icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_horiz_rounded), label: 'Mais'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
