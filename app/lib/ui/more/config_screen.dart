import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../services/claude.dart';
import '../../services/copilot.dart';
import '../../theme.dart';
import '../widgets/common.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late final TextEditingController _nome = TextEditingController(text: AppState.I.nome);
  late final TextEditingController _chave = TextEditingController(text: AppState.I.apiKey);
  late double _escala = AppState.I.escalaTexto.clamp(.85, 1.4);
  bool _mostrarChave = false;
  Timer? _debNome, _debChave;

  bool _testando = false;
  String? _resultado;
  bool _ok = false;

  @override
  void dispose() {
    _debNome?.cancel();
    _debChave?.cancel();
    // garante que o que foi digitado fica salvo
    if (_nome.text.trim() != AppState.I.nome && _nome.text.trim().isNotEmpty) {
      AppState.I.setPref('nome', _nome.text.trim());
    }
    if (_chave.text.trim() != AppState.I.apiKey) AppState.I.setPref('api_key', _chave.text.trim());
    _nome.dispose();
    _chave.dispose();
    super.dispose();
  }

  void _mudouNome(String v) {
    _debNome?.cancel();
    _debNome = Timer(const Duration(milliseconds: 600), () {
      if (v.trim().isNotEmpty) AppState.I.setPref('nome', v.trim());
    });
  }

  void _mudouChave(String v) {
    _debChave?.cancel();
    _debChave = Timer(const Duration(milliseconds: 500), () => AppState.I.setPref('api_key', v.trim()));
    setState(() => _resultado = null);
  }

  Future<void> _testar() async {
    _debChave?.cancel();
    await AppState.I.setPref('api_key', _chave.text.trim());
    setState(() {
      _testando = true;
      _resultado = null;
    });
    try {
      final r = await Claude.conversar(
        system: 'Responda em português, numa frase curta.',
        messages: const [
          {'role': 'user', 'content': 'Teste de conexão: responda apenas "Copiloto pronto."'}
        ],
      ).join().timeout(const Duration(seconds: 60));
      _ok = true;
      _resultado = r.trim().isEmpty ? 'Conectou, mas a resposta veio vazia.' : 'Funcionando: ${r.trim()}';
    } catch (e) {
      _ok = false;
      _resultado = e is ClaudeErro ? e.mensagem : 'Falhou: $e';
    }
    if (mounted) setState(() => _testando = false);
  }

  Future<void> _apagar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        final p = c.pal;
        return AlertDialog(
          title: const Text('Apagar seu progresso?'),
          content: const Text(
              'Apaga anotações, destaques, capítulos lidos, respostas, tentativas, flashcards, plano e a conversa '
              'com o copiloto. O conteúdo de estudo continua. Não dá para desfazer.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.bad, foregroundColor: p.surface),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Apagar tudo'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await AppState.I.apagarTudoDela();
    await Copiloto.I.limpar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Progresso apagado. Recomeço limpo.')));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I;
        final status = Claude.temChave
            ? ('Chave salva só neste aparelho. Ela é enviada apenas para api.anthropic.com.', p.ok, Icons.key_rounded)
            : ('Sem chave: o copiloto não responde até você colar a sua. '
                'Crie uma em console.anthropic.com › API Keys.', p.warn, Icons.key_off_outlined);
        return Scaffold(
          appBar: AppBar(title: const Text('Configurações')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            children: [
              const _Secao('Você e o copiloto'),
              TextField(
                controller: _nome,
                onChanged: _mudouNome,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Como o app te chama', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _chave,
                onChanged: _mudouChave,
                obscureText: !_mostrarChave,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Sua chave da API da Anthropic',
                  hintText: 'sk-ant-…',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip: _mostrarChave ? 'Ocultar' : 'Mostrar',
                    icon: Icon(_mostrarChave ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _mostrarChave = !_mostrarChave),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(status.$3, size: 16, color: status.$2),
                const SizedBox(width: 6),
                Expanded(child: Text(status.$1, style: TextStyle(fontSize: 13, height: 1.4, color: p.inkSoft))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _testando ? null : _testar,
                  icon: _testando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt_outlined),
                  label: Text(_testando ? 'Testando…' : 'Testar copiloto'),
                ),
              ]),
              if (_resultado != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.soft(_ok ? p.ok : p.bad),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_ok ? Icons.check_circle_outline : Icons.error_outline_rounded,
                        size: 18, color: _ok ? p.ok : p.bad),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_resultado!, style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink))),
                  ]),
                ),
              ],
              const _Secao('Aparência'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'sistema', label: Text('Sistema')),
                  ButtonSegment(value: 'claro', label: Text('Claro')),
                  ButtonSegment(value: 'escuro', label: Text('Escuro')),
                ],
                selected: {s.tema},
                showSelectedIcon: false,
                onSelectionChanged: (v) => s.setPref('tema', v.first),
              ),
              const SizedBox(height: 18),
              Painel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('Tamanho do texto do material',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink)),
                    ),
                    Text('${(_escala * 100).round()}%', style: TextStyle(fontSize: 13, color: p.inkSoft)),
                  ]),
                  Slider(
                    value: _escala,
                    min: .85,
                    max: 1.4,
                    divisions: 11,
                    label: '${(_escala * 100).round()}%',
                    onChanged: (v) => setState(() => _escala = v),
                    onChangeEnd: (v) => s.setPref('escala_texto', v.toStringAsFixed(2)),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      'A célula de Reed-Sternberg clássica é binucleada, com nucléolos grandes em "olho de coruja". '
                      'No LH clássico: CD15+ e CD30+, CD20− e CD45−.',
                      style: TextStyle(fontSize: 15 * _escala, height: 1.5, color: p.ink),
                    ),
                  ),
                ]),
              ),
              const _Secao('Dados'),
              Painel(
                onTap: _apagar,
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded, color: p.bad),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Apagar meu progresso',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.bad)),
                      const SizedBox(height: 2),
                      Text('Anotações, respostas, flashcards, plano e conversa',
                          style: TextStyle(fontSize: 13, color: p.inkSoft)),
                    ]),
                  ),
                ]),
              ),
              const _Secao('Sobre e créditos'),
              const _Sobre(),
            ],
          ),
        );
      },
    );
  }
}

class _Secao extends StatelessWidget {
  final String t;
  const _Secao(this.t);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(4, 26, 4, 10), child: Rotulo(t));
}

class _Sobre extends StatelessWidget {
  const _Sobre();

  static String _campo(Map<String, dynamic> f, List<String> chaves) {
    for (final k in chaves) {
      final v = f[k];
      if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = AppState.I;
    final corpo = TextStyle(fontSize: 14, height: 1.5, color: p.ink);
    final fraco = TextStyle(fontSize: 12.5, height: 1.45, color: p.inkSoft);
    final fotos = s.fotos.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Painel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MedRAG', style: TextStyle(fontFamily: kSerif, fontSize: 22, color: p.ink)),
        const SizedBox(height: 6),
        Text(
          'Plataforma de estudo para a P2 de Anatomia Patológica II: tireoide, linfadenopatias reacionais e linfomas.',
          style: corpo,
        ),
        const SizedBox(height: 14),
        Text('De onde vem o conteúdo', style: corpo.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '• Resumo das aulas do professor, reorganizado em capítulos curtos.\n'
          '• Provas antigas (${s.provas.length} conjuntos, ${s.questoes.length} questões), com gabarito oficial quando '
          'existe; quando não, o app indica a origem do gabarito.\n'
          '• Flashcards e quadros comparativos derivados desse material.',
          style: corpo,
        ),
        const SizedBox(height: 14),
        Text('Copiloto', style: corpo.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Modelo ${Claude.modelo} (Anthropic), com busca nos trechos do resumo e das provas feita no próprio aparelho. '
          'É apoio de estudo: confira sempre com o material.',
          style: corpo,
        ),
        const SizedBox(height: 14),
        Text('Micrografias', style: corpo.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (fotos.isEmpty)
          Text('Nenhuma micrografia externa incluída nesta versão.', style: fraco)
        else
          for (final e in fotos)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_campo(e.value, ['titulo', 'legenda', 'descricao']).isEmpty
                    ? e.key
                    : _campo(e.value, ['titulo', 'legenda', 'descricao']),
                    style: corpo.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(
                  [
                    _campo(e.value, ['autor', 'author', 'credito', 'creditos', 'artist']),
                    _campo(e.value, ['licenca', 'license', 'licença']),
                  ].where((x) => x.isNotEmpty).join(' · '),
                  style: fraco,
                ),
                if (_campo(e.value, ['url', 'link', 'fonte', 'source', 'pagina']).isNotEmpty)
                  SelectableText(_campo(e.value, ['url', 'link', 'fonte', 'source', 'pagina']),
                      style: fraco.copyWith(color: p.primary)),
              ]),
            ),
      ]),
    );
  }
}
