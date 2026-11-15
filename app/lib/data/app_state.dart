import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';

/// Estado global: conteúdo em memória (lido do SQLite) + dados da estudante.
class AppState extends ChangeNotifier {
  static final AppState I = AppState._();
  AppState._();

  bool pronto = false;

  // ---- conteúdo
  List<Modulo> modulos = [];
  Map<String, Chapter> capitulos = {};
  List<Exam> provas = [];
  Map<String, Exam> provaPorId = {};
  List<Question> questoes = [];
  Map<String, Question> questaoPorId = {};
  List<Flashcard> cartoes = [];
  List<RagChunk> chunks = [];
  Map<String, Json> fotos = {};

  // ---- dados dela
  final Map<String, String> notas = {}; // "kind|ref" -> texto
  final Set<String> destaques = {};
  final Map<String, bool> capFeito = {};
  final Map<String, double> capPos = {};
  final Map<String, String> respostas = {}; // "qid|sub" -> texto
  final Map<String, List<Attempt>> tentativas = {};
  final Map<String, FlashState> flash = {};
  final Set<String> planoFeito = {};

  // ---- preferências
  String nome = '';
  String tema = 'sistema'; // sistema | claro | escuro
  double escalaTexto = 1.0;
  String apiKey = '';
  int? inicioEstudo; // timestamp do início da maratona de 12h

  Future<void> init() async {
    await _seedConteudo();
    await _carregarConteudo();
    await _carregarUsuario();
    pronto = true;
    notifyListeners();
  }

  // ------------------------------------------------------------------ conteúdo

  Future<Json> _asset(String nome) async =>
      jsonDecode(await rootBundle.loadString('assets/content/$nome')) as Json;

  Future<void> _seedConteudo() async {
    final versao = '${(await _asset('version.json'))['version']}';
    if (await Db.meta('content_version') == versao) return;

    final material = await _asset('material.json');
    final questoes = await _asset('questoes.json');
    final flash = await _asset('flashcards.json');
    final rag = await _asset('rag.json');

    await Db.db.transaction((tx) async {
      final b = tx.batch();
      for (final t in ['chapters', 'exams', 'questions', 'flashcards', 'rag_chunks']) {
        b.delete(t);
      }
      for (final c in material['capitulos'] as List) {
        b.insert('chapters', {'id': c['id'], 'modulo': c['modulo'], 'ordem': c['ordem'], 'json': jsonEncode(c)});
      }
      var i = 0;
      for (final p in questoes['provas'] as List) {
        b.insert('exams', {'id': p['id'], 'ordem': i++, 'json': jsonEncode(p)});
      }
      i = 0;
      for (final q in questoes['questoes'] as List) {
        b.insert('questions', {
          'id': q['id'],
          'prova_id': q['prova_id'],
          'tipo': q['tipo'],
          'modulo': q['modulo'],
          'ordem': i++,
          'json': jsonEncode(q),
        });
      }
      i = 0;
      for (final c in flash['cartoes'] as List) {
        b.insert('flashcards',
            {'id': c['id'], 'modulo': c['modulo'], 'topico': c['topico'], 'ordem': i++, 'json': jsonEncode(c)});
      }
      i = 0;
      for (final c in rag['chunks'] as List) {
        b.insert('rag_chunks', {'id': i++, 'fonte': c['fonte'], 'secao': c['secao'], 'texto': c['texto']});
      }
      b.insert('meta', {'key': 'content_version', 'value': versao}, conflictAlgorithm: ConflictAlgorithm.replace);
      b.insert('meta', {'key': 'modulos', 'value': jsonEncode(material['modulos'])},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await b.commit(noResult: true);
    });
  }

  Future<void> _carregarConteudo() async {
    final db = Db.db;
    final caps = [
      for (final r in await db.query('chapters', orderBy: 'ordem')) Chapter(jsonDecode(r['json'] as String))
    ];
    capitulos = {for (final c in caps) c.id: c};
    final mods = jsonDecode(await Db.meta('modulos') ?? '[]') as List;
    modulos = [
      for (final m in mods)
        Modulo(m['id'], m['titulo'], m['subtitulo'] ?? '',
            caps.where((c) => c.modulo == m['id']).toList()..sort((a, b) => a.ordem.compareTo(b.ordem)))
    ];
    provas = [for (final r in await db.query('exams', orderBy: 'ordem')) Exam(jsonDecode(r['json'] as String))];
    provaPorId = {for (final p in provas) p.id: p};
    questoes = [
      for (final r in await db.query('questions', orderBy: 'ordem')) Question(jsonDecode(r['json'] as String))
    ];
    questaoPorId = {for (final q in questoes) q.id: q};
    cartoes = [
      for (final r in await db.query('flashcards', orderBy: 'ordem')) Flashcard(jsonDecode(r['json'] as String))
    ];
    for (final r in await db.query('my_cards', orderBy: 'id')) {
      cartoes.add(_minhaCarta(r));
    }
    chunks = [
      for (final r in await db.query('rag_chunks', orderBy: 'id'))
        RagChunk(r['id'] as int, r['fonte'] as String, r['secao'] as String, r['texto'] as String)
    ];
    try {
      final f = jsonDecode(await rootBundle.loadString('assets/content/fotos.json')) as List;
      fotos = {for (final x in f) x['ref'] as String: Map<String, dynamic>.from(x)};
    } catch (_) {
      fotos = {};
    }
  }

  Flashcard _minhaCarta(Map<String, Object?> r) => Flashcard({
        'id': 'minha-${r['id']}',
        'modulo': r['modulo'],
        'topico': '',
        'frente': r['frente'],
        'verso': r['verso'],
        'minha': true,
      });

  // ------------------------------------------------------------------ usuário

  Future<void> _carregarUsuario() async {
    final db = Db.db;
    for (final r in await db.query('notes')) {
      notas['${r['kind']}|${r['ref']}'] = r['texto'] as String;
    }
    for (final r in await db.query('highlights')) {
      destaques.add(r['ref'] as String);
    }
    for (final r in await db.query('chapter_progress')) {
      capFeito[r['chapter_id'] as String] = r['done'] == 1;
      capPos[r['chapter_id'] as String] = (r['pos'] as num?)?.toDouble() ?? 0;
    }
    for (final r in await db.query('answers')) {
      respostas['${r['question_id']}|${r['sub']}'] = r['texto'] as String;
    }
    for (final r in await db.query('attempts', orderBy: 'ts')) {
      final a = Attempt(r['question_id'] as String, r['ts'] as int, (r['score'] as num).toDouble());
      tentativas.putIfAbsent(a.questionId, () => []).add(a);
    }
    for (final r in await db.query('flash_state')) {
      flash[r['card_id'] as String] = FlashState(
        box: r['box'] as int,
        due: r['due'] as int,
        reps: r['reps'] as int,
        lapses: r['lapses'] as int,
        lastRating: r['last_rating'] as int,
      );
    }
    for (final r in await db.query('plan_checks', where: 'done = 1')) {
      planoFeito.add(r['task_id'] as String);
    }
    nome = await Db.meta('nome') ?? '';
    tema = await Db.meta('tema') ?? 'sistema';
    escalaTexto = double.tryParse(await Db.meta('escala_texto') ?? '') ?? 1.0;
    apiKey = await Db.meta('api_key') ?? '';
    inicioEstudo = int.tryParse(await Db.meta('inicio_estudo') ?? '');
  }

  Future<void> setPref(String chave, String valor) async {
    switch (chave) {
      case 'nome':
        nome = valor;
      case 'tema':
        tema = valor;
      case 'escala_texto':
        escalaTexto = double.tryParse(valor) ?? 1.0;
      case 'api_key':
        apiKey = valor;
      case 'inicio_estudo':
        inicioEstudo = int.tryParse(valor);
    }
    await Db.setMeta(chave, valor.isEmpty ? null : valor);
    notifyListeners();
  }

  // ---- anotações
  String nota(String kind, String ref) => notas['$kind|$ref'] ?? '';

  Future<void> salvarNota(String kind, String ref, String texto) async {
    final k = '$kind|$ref';
    final t = texto.trim();
    if (t.isEmpty) {
      notas.remove(k);
      await Db.db.delete('notes', where: 'kind = ? AND ref = ?', whereArgs: [kind, ref]);
    } else {
      notas[k] = t;
      await Db.db.insert('notes', {'kind': kind, 'ref': ref, 'texto': t, 'updated_at': Db.now},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    notifyListeners();
  }

  Future<void> alternarDestaque(String ref) async {
    if (destaques.remove(ref)) {
      await Db.db.delete('highlights', where: 'ref = ?', whereArgs: [ref]);
    } else {
      destaques.add(ref);
      await Db.db.insert('highlights', {'ref': ref}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    notifyListeners();
  }

  // ---- progresso de leitura
  Future<void> marcarCapitulo(String id, {bool? feito, double? pos}) async {
    if (feito != null) capFeito[id] = feito;
    if (pos != null) capPos[id] = pos;
    await Db.db.insert(
      'chapter_progress',
      {'chapter_id': id, 'done': (capFeito[id] ?? false) ? 1 : 0, 'pos': capPos[id] ?? 0, 'updated_at': Db.now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (feito != null) notifyListeners();
  }

  // ---- respostas escritas
  String resposta(String qid, [String sub = '']) => respostas['$qid|$sub'] ?? '';

  Future<void> salvarResposta(String qid, String sub, String texto) async {
    respostas['$qid|$sub'] = texto;
    await Db.db.insert('answers', {'question_id': qid, 'sub': sub, 'texto': texto, 'updated_at': Db.now},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- tentativas
  Future<void> registrarTentativa(String qid, double score, [Json? detalhe]) async {
    final a = Attempt(qid, Db.now, score);
    tentativas.putIfAbsent(qid, () => []).add(a);
    await Db.db.insert('attempts',
        {'question_id': qid, 'ts': a.ts, 'score': score, 'detail': detalhe == null ? null : jsonEncode(detalhe)});
    notifyListeners();
  }

  double? ultimaNota(String qid) => tentativas[qid]?.last.score;
  bool feita(String qid) => tentativas.containsKey(qid);
  bool errada(String qid) => (ultimaNota(qid) ?? 1) < 0.7;

  /// Média da última nota por questão, para um conjunto de questões.
  ({int feitas, int total, double? media}) desempenho(Iterable<Question> qs) {
    var feitas = 0, total = 0;
    var soma = 0.0;
    for (final q in qs) {
      total++;
      final n = ultimaNota(q.id);
      if (n != null) {
        feitas++;
        soma += n;
      }
    }
    return (feitas: feitas, total: total, media: feitas == 0 ? null : soma / feitas);
  }

  // ---- flashcards (repetição espaçada comprimida para uma maratona de 12h)
  static const _intervalosMin = [1, 10, 40, 150, 480, 1440];

  Future<void> avaliarCartao(String id, int rating) async {
    // rating: 0 errei · 1 difícil · 2 bom · 3 fácil
    final s = flash[id] ?? FlashState();
    s.reps++;
    if (rating == 0) {
      s.lapses++;
      s.box = 0;
    } else if (rating == 1) {
      s.box = s.box.clamp(1, 5);
    } else {
      s.box = (s.box + (rating == 3 ? 2 : 1)).clamp(1, 5);
    }
    s.lastRating = rating;
    s.due = Db.now + _intervalosMin[s.box] * 60000;
    flash[id] = s;
    await Db.db.insert(
      'flash_state',
      {
        'card_id': id,
        'box': s.box,
        'due': s.due,
        'reps': s.reps,
        'lapses': s.lapses,
        'last_rating': rating,
        'updated_at': Db.now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  bool cartaoNovo(Flashcard c) => !flash.containsKey(c.id);
  bool cartaoVencido(Flashcard c) => flash.containsKey(c.id) && flash[c.id]!.due <= Db.now;
  bool cartaoDominado(Flashcard c) => (flash[c.id]?.box ?? 0) >= 4;

  Future<void> criarCartao(String modulo, String frente, String verso) async {
    final id = await Db.db.insert('my_cards', {'modulo': modulo, 'frente': frente, 'verso': verso, 'ts': Db.now});
    cartoes.add(_minhaCarta({'id': id, 'modulo': modulo, 'frente': frente, 'verso': verso}));
    notifyListeners();
  }

  // ---- plano
  Future<void> marcarPlano(String id, bool feito) async {
    feito ? planoFeito.add(id) : planoFeito.remove(id);
    await Db.db.insert('plan_checks', {'task_id': id, 'done': feito ? 1 : 0, 'ts': Db.now},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  // ---- utilidades de conteúdo
  List<Question> questoesDoTopicos(Iterable<String> topicos, {bool soRepresentantes = true}) {
    final t = topicos.toSet();
    return questoes
        .where((q) => !q.foraDoEscopo && (!soRepresentantes || q.representante) && q.topicos.any(t.contains))
        .toList();
  }

  Future<void> apagarTudoDela() async {
    for (final t in [
      'notes', 'highlights', 'chapter_progress', 'answers', 'attempts', 'flash_state', 'chat', 'plan_checks'
    ]) {
      await Db.db.delete(t);
    }
    notas.clear();
    destaques.clear();
    capFeito.clear();
    capPos.clear();
    respostas.clear();
    tentativas.clear();
    flash.clear();
    planoFeito.clear();
    await setPref('inicio_estudo', '');
  }
}
