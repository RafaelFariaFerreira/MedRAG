import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/app_state.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'claude.dart';
import 'rag.dart';

/// O que está na tela agora — cada tela registra o seu ao abrir.
class TelaCtx {
  /// Rótulo curto mostrado no chip do copiloto (ex.: "Tireoide › Bócios").
  final String rotulo;

  /// Texto do que ela está vendo (calculado só quando o copiloto precisa).
  final String Function() texto;

  /// Sugestões de pergunta para este contexto.
  final List<String> sugestoes;

  const TelaCtx(this.rotulo, this.texto, {this.sugestoes = const []});

  static TelaCtx vazio = TelaCtx('Início', () => '', sugestoes: const [
        'Por onde eu começo com 12h?',
        'Me faça 5 perguntas rápidas de linfomas',
        'Quais são as pegadinhas clássicas do professor?',
      ]);
}

class Copiloto extends ChangeNotifier {
  static final Copiloto I = Copiloto._();
  Copiloto._();

  final List<TelaCtx> _pilha = [];
  TelaCtx get tela => _pilha.isEmpty ? TelaCtx.vazio : _pilha.last;

  void entrar(TelaCtx c) {
    _pilha.add(c);
    scheduleMicrotask(notifyListeners);
  }

  void sair(TelaCtx c) {
    _pilha.remove(c);
    scheduleMicrotask(notifyListeners);
  }

  void trocar(TelaCtx antigo, TelaCtx novo) {
    final i = _pilha.indexOf(antigo);
    if (i >= 0) {
      _pilha[i] = novo;
    } else {
      _pilha.add(novo);
    }
    scheduleMicrotask(notifyListeners);
  }

  final List<ChatMsg> msgs = [];
  bool ocupado = false;
  bool aberto = false;
  String rascunho = ''; // texto pré-preenchido por outra tela (ex.: "corrigir minha resposta")
  StreamSubscription<String>? _sub;
  Rag? _rag;

  Rag get rag => _rag ??= Rag(AppState.I.chunks);

  Future<void> carregar() async {
    msgs.clear();
    for (final r in await Db.db.query('chat', orderBy: 'id')) {
      msgs.add(ChatMsg(
        r['role'] as String,
        r['texto'] as String,
        id: r['id'] as int,
        contexto: (r['contexto'] as String?) ?? '',
        fontes: r['fontes'] == null ? const [] : List<String>.from(jsonDecode(r['fontes'] as String)),
      ));
    }
    notifyListeners();
  }

  Future<void> limpar() async {
    await _sub?.cancel();
    ocupado = false;
    msgs.clear();
    await Db.db.delete('chat');
    notifyListeners();
  }

  void parar() {
    _sub?.cancel();
    _sub = null;
    if (msgs.isNotEmpty && msgs.last.streaming) {
      msgs.last.streaming = false;
      if (msgs.last.texto.isEmpty) msgs.removeLast();
    }
    ocupado = false;
    notifyListeners();
  }

  static const system = '''
Você é o copiloto de estudos de uma estudante de medicina do 5º período que fará a prova P2 de Anatomia Patológica II: Tireoide, Linfadenopatias reacionais e Linfomas. Ela tem poucas horas, já estudou, e o conteúdo está embaralhado na cabeça. Seu trabalho é ajudá-la a organizar, separar e fixar — não a despejar mais informação.

Como responder:
- Português do Brasil. Ela lê no celular: vá direto ao ponto, parágrafos curtos, e use listas ou uma tabela pequena quando houver comparação. Negrito só no termo que ela precisa gravar.
- Baseie-se nos TRECHOS RECUPERADOS (resumo das aulas e provas antigas com gabarito) e no CONTEXTO DA TELA que acompanham cada pergunta. A visão do professor é a que vale na prova. Quando usar um trecho, cite a fonte entre colchetes, por exemplo [Resumo · Linfomas] ou [Prova 150]. Se a resposta não estiver nos trechos, diga isso em uma frase e então responda com conhecimento médico consolidado, marcando como "Complemento".
- Se os trechos trouxerem gabarito "do chat" ou "do NotebookLM", trate-o com cautela: ele pode estar errado; prefira o gabarito oficial e o resumo.
- Quando duas entidades se confundem, mostre a diferença pelo mesmo conjunto de critérios (clínica, morfologia, imuno-histoquímica com + e −, evolução), lado a lado.
- Regras do professor que ela não pode esquecer: diagnóstico COMPLETO ("Linfoma de Hodgkin clássico, tipo esclerose nodular"; "Linfoma não Hodgkin, tipo de Burkitt") — incompleto perde ponto; não existe diagnóstico de linfoma sem imuno-histoquímica; citar pelo menos dois marcadores dizendo se são positivos ou negativos; Ki-67 é índice de proliferação, não marcador; "linfonodos reacionais" no enunciado significa livres de neoplasia.
- Se ela pedir para ser testada, faça uma pergunta por vez, espere a resposta e corrija com precisão, dizendo o que faltou.
- Se ela pedir correção de uma resposta discursiva, compare com a resposta-modelo fornecida: diga o que está certo, o que faltou e o que está errado, e termine com uma versão enxuta que tiraria nota máxima.
- Se ela parecer ansiosa ou perdida, seja breve e prático: diga o próximo passo.
- Você é apoio de estudo para uma prova; não oriente conduta para pacientes reais.''';

  Future<void> enviar(String texto, {bool usarContexto = true}) async {
    final pergunta = texto.trim();
    if (pergunta.isEmpty || ocupado) return;
    final ctx = tela;
    final textoTela = usarContexto ? ctx.texto() : '';

    final recuperados = rag.buscar(pergunta, reforco: usarContexto ? '${ctx.rotulo} ${_cabeca(textoTela, 400)}' : '');
    final fontes = <String>{for (final c in recuperados) c.fonte}.toList();

    final user = ChatMsg('user', pergunta, contexto: usarContexto ? ctx.rotulo : '');
    msgs.add(user);
    await Db.db.insert('chat', {'role': 'user', 'texto': pergunta, 'contexto': user.contexto, 'ts': Db.now});

    final resp = ChatMsg('assistant', '', streaming: true, fontes: fontes);
    msgs.add(resp);
    ocupado = true;
    notifyListeners();

    // Histórico: só o texto das últimas trocas; contexto e trechos vão apenas no turno atual.
    final anteriores = msgs.sublist(0, msgs.length - 2).where((m) => !m.erro && m.texto.isNotEmpty).toList();
    final historico = anteriores.length > 12 ? anteriores.sublist(anteriores.length - 12) : anteriores;
    final messages = <Map<String, dynamic>>[];
    for (final m in historico) {
      if (messages.isNotEmpty && messages.last['role'] == m.role) {
        messages.last['content'] = '${messages.last['content']}\n\n${m.texto}';
      } else {
        messages.add({'role': m.role, 'content': m.texto});
      }
    }
    while (messages.isNotEmpty && messages.first['role'] != 'user') {
      messages.removeAt(0);
    }
    if (messages.isNotEmpty && messages.last['role'] == 'user') messages.removeLast();

    final b = StringBuffer();
    if (usarContexto && ctx.rotulo.isNotEmpty) {
      b.writeln('<contexto_da_tela onde="${ctx.rotulo}">');
      b.writeln(_cabeca(textoTela, 7000));
      b.writeln('</contexto_da_tela>\n');
    }
    b.writeln('<trechos_recuperados>');
    if (recuperados.isEmpty) b.writeln('(nenhum trecho relevante encontrado nos arquivos)');
    for (final c in recuperados) {
      b.writeln('[${c.fonte}${c.secao.isEmpty ? '' : ' — ${c.secao}'}]');
      b.writeln(c.texto);
      b.writeln('---');
    }
    b.writeln('</trechos_recuperados>\n');
    b.writeln('<pergunta>');
    b.writeln(pergunta);
    b.writeln('</pergunta>');
    messages.add({'role': 'user', 'content': b.toString()});

    final feito = Completer<void>();
    _sub = Claude.conversar(system: system, messages: messages).listen(
      (pedaco) {
        resp.texto += pedaco;
        notifyListeners();
      },
      onError: (Object e) {
        resp.streaming = false;
        resp.erro = true;
        resp.texto = e is ClaudeErro ? e.mensagem : 'Não consegui falar com o copiloto agora. ($e)';
        ocupado = false;
        notifyListeners();
        if (!feito.isCompleted) feito.complete();
      },
      onDone: () async {
        resp.streaming = false;
        ocupado = false;
        if (resp.texto.trim().isEmpty) {
          resp.erro = true;
          resp.texto = 'A resposta veio vazia. Tente de novo.';
        } else {
          await Db.db.insert('chat',
              {'role': 'assistant', 'texto': resp.texto, 'fontes': jsonEncode(fontes), 'ts': Db.now});
        }
        notifyListeners();
        if (!feito.isCompleted) feito.complete();
      },
      cancelOnError: true,
    );
    return feito.future;
  }

  static String _cabeca(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
}
