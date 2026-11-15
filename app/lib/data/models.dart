typedef Json = Map<String, dynamic>;

List<String> _strs(dynamic v) => v == null ? const [] : List<String>.from((v as List).map((e) => '$e'));

class Chapter {
  final Json j;
  Chapter(this.j);
  String get id => j['id'];
  String get modulo => j['modulo'];
  int get ordem => (j['ordem'] as num).toInt();
  String get titulo => j['titulo'];
  int get minutos => (j['minutos'] as num?)?.toInt() ?? 10;
  String get prioridade => j['prioridade'] ?? 'media';
  String get resumo => j['resumo'] ?? '';
  List<String> get objetivos => _strs(j['objetivos']);
  List<String> get topicos => _strs(j['topicos']);
  List<Json> get blocos => List<Json>.from(j['blocos'] ?? const []);

  /// Todos os blocos, inclusive os de dentro de "expansivel".
  Iterable<Json> get todosBlocos sync* {
    Iterable<Json> walk(List<Json> bs) sync* {
      for (final b in bs) {
        yield b;
        if (b['tipo'] == 'expansivel') yield* walk(List<Json>.from(b['blocos'] ?? const []));
      }
    }

    yield* walk(blocos);
  }

  List<String> get secoes =>
      [for (final b in blocos) if (b['tipo'] == 'titulo') '${b['texto']}'];
}

class Modulo {
  final String id, titulo, subtitulo;
  final List<Chapter> capitulos;
  Modulo(this.id, this.titulo, this.subtitulo, this.capitulos);
  int get minutos => capitulos.fold(0, (a, c) => a + c.minutos);
}

class Exam {
  final Json j;
  Exam(this.j);
  String get id => j['id'];
  String get titulo => j['titulo'];
  String get temas => j['temas'] ?? '';
  String get periodo => j['periodo'] ?? 'desconhecido';
  String get gabaritoFonte => j['gabarito_fonte'] ?? 'inferido';
}

class Question {
  final Json j;
  Question(this.j);
  String get id => j['id'];
  String get provaId => j['prova_id'];
  String get numero => '${j['numero']}';
  String get tipo => j['tipo'];
  String get modulo => j['modulo'];
  List<String> get topicos => _strs(j['topicos']);
  String get enunciado => j['enunciado'] ?? '';
  num? get pontos => j['pontos'];
  List<Json> get alternativas => List<Json>.from(j['alternativas'] ?? const []);
  String? get correta => j['correta'];
  bool get pedeIncorreta => j['pede'] == 'incorreta';
  List<Json> get itens => List<Json>.from(j['itens'] ?? const []);
  String get respostaModelo => j['resposta_modelo'] ?? '';
  List<String> get checklist => _strs(j['checklist']);
  List<Json> get subitens => List<Json>.from(j['subitens'] ?? const []);
  List<Json> get lacunas => List<Json>.from(j['lacunas'] ?? const []);
  String get explicacao => j['explicacao'] ?? '';
  String get gabaritoFonte => j['gabarito_fonte'] ?? 'inferido';
  String get confianca => j['confianca'] ?? 'media';
  String get observacao => j['observacao'] ?? '';
  bool get foraDoEscopo => j['fora_do_escopo'] == true;

  /// Quantas provas trouxeram esta mesma questão (calculado no build do conteúdo).
  int get freq => (j['freq'] as num?)?.toInt() ?? 1;
  String get grupo => j['grupo'] ?? id;
  bool get representante => j['representante'] != false;
  List<String> get provasDoGrupo => _strs(j['provas_do_grupo']);

  bool get objetiva => tipo == 'multipla' || tipo == 'vf';
}

class Flashcard {
  final Json j;
  Flashcard(this.j);
  String get id => j['id'];
  String get modulo => j['modulo'];
  String get topico => j['topico'] ?? '';
  String get capitulo => j['capitulo'] ?? '';
  String get frente => j['frente'];
  String get verso => j['verso'];
  String get dica => j['dica'] ?? '';
  bool get minha => j['minha'] == true;
}

class FlashState {
  int box, due, reps, lapses, lastRating;
  FlashState({this.box = 0, this.due = 0, this.reps = 0, this.lapses = 0, this.lastRating = 0});
}

class RagChunk {
  final int id;
  final String fonte, secao, texto;
  RagChunk(this.id, this.fonte, this.secao, this.texto);
}

class Attempt {
  final String questionId;
  final int ts;
  final double score;
  Attempt(this.questionId, this.ts, this.score);
}

class ChatMsg {
  final int? id;
  final String role;
  String texto;
  final String contexto;
  List<String> fontes;
  bool streaming;
  bool erro;
  ChatMsg(this.role, this.texto,
      {this.id, this.contexto = '', this.fontes = const [], this.streaming = false, this.erro = false});
}

const topicoNomes = <String, String>{
  'tir-fisiologia': 'Fisiologia e laboratório',
  'tir-graves': 'Graves (bócio difuso tóxico)',
  'tir-bocio-nodular': 'Bócio nodular atóxico',
  'tir-hashimoto': 'Hashimoto',
  'tir-tireoidites-outras': 'Outras tireoidites',
  'tir-nodulo-paaf-bethesda': 'Nódulo, PAAF e Bethesda',
  'tir-papilifero': 'Carcinoma papilífero',
  'tir-folicular': 'Carcinoma folicular',
  'tir-medular': 'Carcinoma medular',
  'tir-anaplasico': 'Carcinoma anaplásico',
  'tir-geral': 'Tireoide — geral',
  'lfa-linfonodo-histologia': 'Histologia do linfonodo',
  'lfa-drenagem-clinica': 'Drenagem e clínica',
  'lfa-padrao-folicular': 'Padrão folicular (zona B)',
  'lfa-hiperplasia-vs-linfoma-folicular': 'Hiperplasia × linfoma folicular',
  'lfa-padrao-paracortical': 'Padrão paracortical (zona T)',
  'lfa-padrao-sinusal': 'Padrão sinusal',
  'lfa-necrosantes': 'Necrosantes',
  'lfa-granulomatosas': 'Granulomatosas',
  'lfa-geral': 'Linfadenopatias — geral',
  'lin-geral': 'Linfomas — visão geral',
  'lin-estadiamento': 'Estadiamento (Ann Arbor)',
  'lin-lh-geral': 'Hodgkin — geral',
  'lin-lh-esclerose-nodular': 'LH esclerose nodular',
  'lin-lh-celularidade-mista': 'LH celularidade mista',
  'lin-lh-rico-linfocitos': 'LH rico em linfócitos',
  'lin-lh-deplecao': 'LH depleção linfocitária',
  'lin-lh-pln': 'LH predominância linfocítica nodular',
  'lin-lnh-geral': 'Não Hodgkin — geral',
  'lin-folicular': 'Linfoma folicular',
  'lin-dgcb': 'Difuso de grandes células B',
  'lin-burkitt': 'Burkitt',
  'lin-malt': 'MALT',
  'lin-manto': 'Células do manto',
  'lin-llc': 'LLC / linfocítico',
  'lin-micose-fungoide': 'Micose fungoide / Sézary',
  'lin-t-outros': 'Outros linfomas T',
  'lin-outros': 'Outros linfomas',
  'fora-escopo': 'Fora do escopo da P2',
};

String topicoNome(String t) => topicoNomes[t] ?? t;

String moduloDoTopico(String t) => t.startsWith('tir-')
    ? 'tireoide'
    : t.startsWith('lfa-')
        ? 'linfadenopatias'
        : t.startsWith('lin-')
            ? 'linfomas'
            : 'outros';
