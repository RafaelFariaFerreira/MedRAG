import 'package:material_ui/material_ui.dart';

import 'app_keys.dart';
import 'data/app_state.dart';
import 'data/db.dart';
import 'services/copilot.dart';
import 'theme.dart';
import 'ui/copilot/copilot_sheet.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _iniciar();
}

Future<void> _iniciar() async {
  try {
    await Db.open();
    await AppState.I.init();
    await Copiloto.I.carregar();
    runApp(const AnatopatoApp());
  } catch (e, st) {
    debugPrint('Falha ao iniciar: $e\n$st');
    runApp(_TelaErroInicio(erro: '$e'));
  }
}

final _temaClaro = buildTheme(Pal.light);
final _temaEscuro = buildTheme(Pal.darkPal);

/// App raiz. Não faz I/O: assume que `Db`, `AppState` e `Copiloto` já foram iniciados.
class AnatopatoApp extends StatelessWidget {
  const AnatopatoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) => MaterialApp(
        title: 'MedRAG',
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        theme: _temaClaro,
        darkTheme: _temaEscuro,
        themeMode: switch (AppState.I.tema) {
          'claro' => ThemeMode.light,
          'escuro' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: const Shell(),
        // Reserva a faixa dos botões do Android para nenhuma tela desenhar por baixo dela.
        builder: (context, child) => Stack(children: [
          ColoredBox(
            color: context.pal.bg,
            child: SafeArea(top: false, child: child ?? const SizedBox.shrink()),
          ),
          const Positioned.fill(child: BalaoCopiloto()),
        ]),
      ),
    );
  }
}

/// Mostrada quando a inicialização falha — nunca deixar a tela em branco.
class _TelaErroInicio extends StatelessWidget {
  final String erro;
  const _TelaErroInicio({required this.erro});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Pal.light),
      darkTheme: buildTheme(Pal.darkPal),
      home: Builder(builder: (context) {
        final p = context.pal;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              children: [
                Icon(Icons.error_outline_rounded, size: 40, color: p.bad),
                const SizedBox(height: 16),
                Text('Não consegui abrir o app',
                    style: TextStyle(fontFamily: kSerif, fontSize: 28, height: 1.15, color: p.ink)),
                const SizedBox(height: 10),
                Text(
                  'Algo deu errado ao carregar o conteúdo ou o banco de dados do aparelho. '
                  'Feche e abra de novo. Se continuar, reinstale o app (seu progresso fica salvo no aparelho, '
                  'a menos que você apague os dados).',
                  style: TextStyle(fontSize: 15, height: 1.5, color: p.inkSoft),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _iniciar,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar de novo'),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                  child: SelectableText('Detalhe técnico: $erro',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: p.inkSoft)),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
