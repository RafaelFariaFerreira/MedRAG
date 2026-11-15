import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../flashcards/sessao_flash.dart';
import '../material/chapter_screen.dart';
import '../material/quadros_screen.dart';
import '../questions/sessao_questoes.dart';
import '../widgets/common.dart';

/// Plano de 12 horas (720 min). Princípios: ela dirige (marca o que fez, pode pular),
/// relevância imediata (começa pelo que cai), parte do que já sabe (diagnóstico),
/// prática de recuperação (questões e flashcards em todo módulo) e intercalação
/// (revisão de módulos anteriores nas pausas e no fechamento).

enum TipoTarefa {
  ler, // abrir capítulo
  diagnostico, // 12 objetivas, 4 por módulo
  questoes, // questões por tópicos
  simulado, // prova inteira
  flash, // flashcards de um módulo
  flashVencidos, // revisão do que venceu
  quadros, // quadros comparativos
  erradas, // refazer as que errou
  livre, // sem destino (comer, dormir…)
}

class Tarefa {
  final String id;
  final TipoTarefa tipo;
  final String titulo;
  final String? capitulo;
  final List<String> topicos;
  final List<String> prefixos; // tópicos que começam com…
  final String? prova;
  final String? modulo;
  const Tarefa(
    this.id,
    this.tipo,
    this.titulo, {
    this.capitulo,
    this.topicos = const [],
    this.prefixos = const [],
    this.prova,
    this.modulo,
  });
}

class BlocoPlano {
  final String id;
  final int numero; // -1 = pausa
  final String titulo;
  final String? modulo;
  final int minutos;
  final String objetivo;
  final List<Tarefa> tarefas;
  const BlocoPlano(this.id, this.numero, this.titulo, this.minutos, this.objetivo, this.tarefas, {this.modulo});
  bool get pausa => numero < 0;
}

const _nh = ['lin-folicular', 'lin-dgcb', 'lin-burkitt', 'lin-malt', 'lin-manto', 'lin-micose-fungoide', 'lin-lnh-geral'];

const plano = <BlocoPlano>[
  BlocoPlano('b00', 0, 'Ponto de partida', 20,
      'Descobrir em 15 minutos onde você está firme e onde está fraca — para gastar as horas no lugar certo.', [
    Tarefa('diag', TipoTarefa.diagnostico, 'Diagnóstico: 12 questões objetivas (4 por módulo)'),
    Tarefa('mapa', TipoTarefa.quadros, 'Passar os olhos nos quadros comparativos (o mapa do conteúdo)'),
  ]),
  BlocoPlano('b01', 1, 'Tireoide I', 55, 'Assentar a base: anatomia, fisiologia e o hipertireoidismo de Graves.', [
    Tarefa('c1', TipoTarefa.ler, 'Ler', capitulo: 'tir-01'),
    Tarefa('c2', TipoTarefa.ler, 'Ler', capitulo: 'tir-02'),
    Tarefa('fc', TipoTarefa.flash, 'Flashcards de tireoide (10 min)', modulo: 'tireoide'),
  ], modulo: 'tireoide'),
  BlocoPlano('b02', 2, 'Tireoide II', 55, 'Separar bócios e tireoidites pelos mesmos critérios, lado a lado.', [
    Tarefa('c3', TipoTarefa.ler, 'Ler', capitulo: 'tir-03'),
    Tarefa('c4', TipoTarefa.ler, 'Ler', capitulo: 'tir-04'),
  ], modulo: 'tireoide'),
  BlocoPlano('b03', 3, 'Tireoide III', 60,
      'Dominar nódulo, PAAF e os carcinomas — e fechar o módulo testando com questões reais.', [
    Tarefa('c5', TipoTarefa.ler, 'Ler', capitulo: 'tir-05'),
    Tarefa('c6', TipoTarefa.ler, 'Ler', capitulo: 'tir-06'),
    Tarefa('q', TipoTarefa.questoes, 'Questões de tireoide das provas antigas', prefixos: ['tir-']),
  ], modulo: 'tireoide'),
  BlocoPlano('b04', 4, 'Linfadenopatias I', 55, 'Ler o linfonodo normal e saber de onde vem cada gânglio aumentado.', [
    Tarefa('c1', TipoTarefa.ler, 'Ler', capitulo: 'lfa-01'),
    Tarefa('c2', TipoTarefa.ler, 'Ler', capitulo: 'lfa-02'),
  ], modulo: 'linfadenopatias'),
  BlocoPlano('b05', 5, 'Linfadenopatias II', 60,
      'Reconhecer os padrões reacionais e os granulomas — e não confundir hiperplasia com linfoma.', [
    Tarefa('c3', TipoTarefa.ler, 'Ler', capitulo: 'lfa-03'),
    Tarefa('c4', TipoTarefa.ler, 'Ler', capitulo: 'lfa-04'),
    Tarefa('c5', TipoTarefa.ler, 'Ler', capitulo: 'lfa-05'),
    Tarefa('q', TipoTarefa.questoes, 'Questões de linfadenopatias', prefixos: ['lfa-']),
  ], modulo: 'linfadenopatias'),
  BlocoPlano('pausa', -1, 'Pausa longa', 30,
      'Comer, andar, sair da tela. Na volta, uma revisão curta fixa o que você já viu.', [
    Tarefa('comer', TipoTarefa.livre, 'Comer algo de verdade e caminhar 10 minutos'),
    Tarefa('rev', TipoTarefa.flashVencidos, 'Revisar agora: flashcards que venceram'),
  ]),
  BlocoPlano('b06', 6, 'Linfomas I', 55, 'Montar o mapa geral dos linfomas e entender a célula de Reed-Sternberg.', [
    Tarefa('c1', TipoTarefa.ler, 'Ler', capitulo: 'lin-01'),
    Tarefa('c2', TipoTarefa.ler, 'Ler', capitulo: 'lin-02'),
    Tarefa('c3', TipoTarefa.ler, 'Ler', capitulo: 'lin-03'),
  ], modulo: 'linfomas'),
  BlocoPlano('b07', 7, 'Linfomas II', 55,
      'Fechar Hodgkin: subtipos, imuno-histoquímica e estadiamento — e testar com questões.', [
    Tarefa('c4', TipoTarefa.ler, 'Ler', capitulo: 'lin-04'),
    Tarefa('q', TipoTarefa.questoes, 'Questões de Hodgkin e estadiamento',
        prefixos: ['lin-lh-'], topicos: ['lin-estadiamento']),
  ], modulo: 'linfomas'),
  BlocoPlano('b08', 8, 'Linfomas III', 60, 'Entrar nos não Hodgkin B: quem é indolente, quem é agressivo e por quê.', [
    Tarefa('c5', TipoTarefa.ler, 'Ler', capitulo: 'lin-05'),
    Tarefa('c6', TipoTarefa.ler, 'Ler', capitulo: 'lin-06'),
  ], modulo: 'linfomas'),
  BlocoPlano('b09', 9, 'Linfomas IV', 55, 'Completar os não Hodgkin e treinar o diagnóstico completo que o professor exige.', [
    Tarefa('c7', TipoTarefa.ler, 'Ler', capitulo: 'lin-07'),
    Tarefa('q', TipoTarefa.questoes, 'Questões de linfomas não Hodgkin', topicos: _nh),
  ], modulo: 'linfomas'),
  BlocoPlano('b10', 10, 'Simulado 1', 60,
      'Fazer a prova mais recente como se fosse o dia, e corrigir com a resposta-modelo e o copiloto.', [
    Tarefa('p151', TipoTarefa.simulado, 'Prova 151 (discursiva — o formato mais recente)', prova: 'p151'),
    Tarefa('corr', TipoTarefa.livre, 'Corrigir: comparar com a resposta-modelo e pedir ajuda ao copiloto'),
  ]),
  BlocoPlano('b11', 11, 'Simulado 2', 55, 'Segunda rodada, em formato misto, para treinar troca rápida de assunto.', [
    Tarefa('p150', TipoTarefa.simulado, 'Prova 150 (mista)', prova: 'p150'),
  ]),
  BlocoPlano('b12', 12, 'Fechamento', 45, 'Consertar o que errou, revisar o que venceu e ir dormir — o sono fixa.', [
    Tarefa('err', TipoTarefa.erradas, 'Refazer as questões que você errou'),
    Tarefa('fc', TipoTarefa.flashVencidos, 'Flashcards vencidos'),
    Tarefa('quad', TipoTarefa.quadros, 'Uma última passada nos quadros comparativos'),
    Tarefa('dormir', TipoTarefa.livre, 'Dormir pelo menos 6 horas'),
  ]),
];

int get minutosPlano => plano.fold(0, (a, b) => a + b.minutos);

String chaveTarefa(BlocoPlano b, Tarefa t) => '${b.id}-${t.id}';

/// Minuto (desde o início) em que cada bloco começa.
int inicioDoBloco(BlocoPlano b) {
  var m = 0;
  for (final x in plano) {
    if (identical(x, b) || x.id == b.id) return m;
    m += x.minutos;
  }
  return m;
}

bool tarefaFeita(BlocoPlano b, Tarefa t) {
  final s = AppState.I;
  if (s.planoFeito.contains(chaveTarefa(b, t))) return true;
  return t.tipo == TipoTarefa.ler && t.capitulo != null && (s.capFeito[t.capitulo] ?? false);
}

Future<void> alternarTarefa(BlocoPlano b, Tarefa t, bool feito) async {
  final s = AppState.I;
  await s.marcarPlano(chaveTarefa(b, t), feito);
  if (!feito && t.tipo == TipoTarefa.ler && t.capitulo != null && (s.capFeito[t.capitulo] ?? false)) {
    await s.marcarCapitulo(t.capitulo!, feito: false);
  }
}

bool blocoFeito(BlocoPlano b) => b.tarefas.every((t) => tarefaFeita(b, t));

/// Primeiro bloco com alguma tarefa pendente (null = plano concluído).
BlocoPlano? blocoAtual() {
  for (final b in plano) {
    if (!blocoFeito(b)) return b;
  }
  return null;
}

({int feitas, int total}) progressoPlano() {
  var f = 0, t = 0;
  for (final b in plano) {
    for (final x in b.tarefas) {
      t++;
      if (tarefaFeita(b, x)) f++;
    }
  }
  return (feitas: f, total: t);
}

String tituloTarefa(Tarefa t) {
  if (t.tipo == TipoTarefa.ler) {
    final c = AppState.I.capitulos[t.capitulo];
    return c == null ? 'Ler capítulo ${t.capitulo}' : 'Ler: ${c.titulo}';
  }
  return t.titulo;
}

/// Minutos estimados (só para capítulos, que têm duração própria).
int? minutosTarefa(Tarefa t) => t.tipo == TipoTarefa.ler ? AppState.I.capitulos[t.capitulo]?.minutos : null;

// ------------------------------------------------------------------ montagem das sessões

List<Question> questoesDiagnostico() {
  final s = AppState.I;
  final rnd = math.Random(2026);
  final out = <Question>[];
  for (final m in ['tireoide', 'linfadenopatias', 'linfomas']) {
    final qs = s.questoes.where((q) => q.modulo == m && q.objetiva && q.representante && !q.foraDoEscopo).toList()
      ..shuffle(rnd);
    out.addAll(qs.take(4));
  }
  return out;
}

List<Question> questoesDaTarefa(Tarefa t) {
  final s = AppState.I;
  switch (t.tipo) {
    case TipoTarefa.diagnostico:
      return questoesDiagnostico();
    case TipoTarefa.simulado:
      return s.questoes.where((q) => q.provaId == t.prova).toList();
    case TipoTarefa.erradas:
      return s.questoes.where((q) => s.feita(q.id) && s.errada(q.id)).toList();
    case TipoTarefa.questoes:
      final tops = <String>{...t.topicos};
      if (t.prefixos.isNotEmpty) {
        for (final q in s.questoes) {
          for (final x in q.topicos) {
            if (t.prefixos.any(x.startsWith)) tops.add(x);
          }
        }
      }
      return s.questoesDoTopicos(tops);
    default:
      return const [];
  }
}

List<Flashcard> cartoesDaTarefa(Tarefa t) {
  final s = AppState.I;
  switch (t.tipo) {
    case TipoTarefa.flash:
      return s.cartoes.where((c) => c.modulo == t.modulo).toList();
    case TipoTarefa.flashVencidos:
      final venc = s.cartoes.where(s.cartaoVencido).toList();
      if (venc.isNotEmpty) return venc;
      // nada venceu ainda: revisa os que já viu e não dominou
      return s.cartoes.where((c) => !s.cartaoNovo(c) && !s.cartaoDominado(c)).take(25).toList();
    default:
      return const [];
  }
}

/// A tarefa tem para onde ir? (capítulo inexistente → desabilitada)
bool tarefaDisponivel(Tarefa t) {
  final s = AppState.I;
  return switch (t.tipo) {
    TipoTarefa.ler => s.capitulos.containsKey(t.capitulo),
    TipoTarefa.diagnostico || TipoTarefa.questoes || TipoTarefa.simulado => questoesDaTarefa(t).isNotEmpty,
    TipoTarefa.flash => cartoesDaTarefa(t).isNotEmpty,
    _ => true,
  };
}

bool tarefaTemDestino(Tarefa t) => t.tipo != TipoTarefa.livre;

void abrirTarefa(BuildContext context, Tarefa t) {
  void aviso(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  switch (t.tipo) {
    case TipoTarefa.livre:
      return;
    case TipoTarefa.ler:
      if (!AppState.I.capitulos.containsKey(t.capitulo)) return aviso('Este capítulo ainda não está disponível.');
      abrir(context, ChapterScreen(chapterId: t.capitulo!));
    case TipoTarefa.quadros:
      abrir(context, const QuadrosScreen());
    case TipoTarefa.diagnostico:
    case TipoTarefa.questoes:
    case TipoTarefa.simulado:
    case TipoTarefa.erradas:
      final qs = questoesDaTarefa(t);
      if (qs.isEmpty) {
        return aviso(t.tipo == TipoTarefa.erradas
            ? 'Nenhuma questão errada até agora. Bom sinal.'
            : 'Não há questões para esta tarefa.');
      }
      final titulo = switch (t.tipo) {
        TipoTarefa.diagnostico => 'Diagnóstico rápido',
        TipoTarefa.simulado => AppState.I.provaPorId[t.prova]?.titulo ?? 'Simulado',
        TipoTarefa.erradas => 'Refazer as que errei',
        _ => t.titulo,
      };
      abrir(context, SessaoQuestoes(titulo: titulo, questoes: qs, simulado: t.tipo == TipoTarefa.simulado));
    case TipoTarefa.flash:
    case TipoTarefa.flashVencidos:
      final cs = cartoesDaTarefa(t);
      if (cs.isEmpty) return aviso('Nenhum flashcard para revisar agora. Volte depois de estudar um módulo.');
      abrir(context, SessaoFlash(titulo: t.tipo == TipoTarefa.flash ? t.titulo : 'Revisão', cartoes: cs));
  }
}

/// Resumo do plano para o contexto do copiloto.
String textoPlanoParaCopiloto() {
  final s = AppState.I;
  final b = StringBuffer();
  final pr = progressoPlano();
  b.writeln('Plano de 12h — ${pr.feitas} de ${pr.total} tarefas feitas.');
  if (s.inicioEstudo != null) {
    final dec = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(s.inicioEstudo!)).inMinutes;
    b.writeln('Tempo de estudo decorrido: ${fmtMin(dec.clamp(0, 99999))}.');
  } else {
    b.writeln('Ela ainda não iniciou o relógio da maratona.');
  }
  final atual = blocoAtual();
  for (final x in plano) {
    final marca = blocoFeito(x) ? '[feito]' : identical(x, atual) ? '[AGORA]' : '[ ]';
    b.writeln('$marca ${x.titulo} (${x.minutos} min): ${x.objetivo}');
    if (identical(x, atual)) {
      for (final t in x.tarefas) {
        b.writeln('   - ${tarefaFeita(x, t) ? '✓' : '○'} ${tituloTarefa(t)}');
      }
    }
  }
  return b.toString();
}
