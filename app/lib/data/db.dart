import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Banco SQLite do app: conteúdo (semeado a partir dos assets) + tudo que é dela
/// (anotações, respostas, tentativas, estado dos flashcards, plano, conversa).
class Db {
  static late Database db;

  static Future<void> open({DatabaseFactory? factory, String? path}) async {
    if (factory != null) {
      databaseFactory = factory;
    } else if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
    db = await openDatabase(
      path ?? 'anatopato_p2.db',
      version: 1,
      onCreate: (d, v) async {
        final b = d.batch();
        for (final sql in _schema) {
          b.execute(sql);
        }
        await b.commit(noResult: true);
      },
    );
  }

  static const _schema = [
    'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)',
    // ---- conteúdo (regravado quando a versão dos assets muda)
    'CREATE TABLE chapters(id TEXT PRIMARY KEY, modulo TEXT, ordem INTEGER, json TEXT)',
    'CREATE TABLE exams(id TEXT PRIMARY KEY, ordem INTEGER, json TEXT)',
    'CREATE TABLE questions(id TEXT PRIMARY KEY, prova_id TEXT, tipo TEXT, modulo TEXT, ordem INTEGER, json TEXT)',
    'CREATE TABLE flashcards(id TEXT PRIMARY KEY, modulo TEXT, topico TEXT, ordem INTEGER, json TEXT)',
    'CREATE TABLE rag_chunks(id INTEGER PRIMARY KEY, fonte TEXT, secao TEXT, texto TEXT)',
    // ---- dados da estudante
    'CREATE TABLE notes(kind TEXT, ref TEXT, texto TEXT, updated_at INTEGER, PRIMARY KEY(kind, ref))',
    'CREATE TABLE highlights(ref TEXT PRIMARY KEY)',
    'CREATE TABLE chapter_progress(chapter_id TEXT PRIMARY KEY, done INTEGER, pos REAL, updated_at INTEGER)',
    'CREATE TABLE answers(question_id TEXT, sub TEXT, texto TEXT, updated_at INTEGER, PRIMARY KEY(question_id, sub))',
    'CREATE TABLE attempts(id INTEGER PRIMARY KEY AUTOINCREMENT, question_id TEXT, ts INTEGER, score REAL, detail TEXT)',
    'CREATE INDEX idx_attempts_q ON attempts(question_id)',
    'CREATE TABLE flash_state(card_id TEXT PRIMARY KEY, box INTEGER, due INTEGER, reps INTEGER, lapses INTEGER, last_rating INTEGER, updated_at INTEGER)',
    'CREATE TABLE my_cards(id INTEGER PRIMARY KEY AUTOINCREMENT, modulo TEXT, frente TEXT, verso TEXT, ts INTEGER)',
    'CREATE TABLE chat(id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT, texto TEXT, contexto TEXT, fontes TEXT, ts INTEGER)',
    'CREATE TABLE plan_checks(task_id TEXT PRIMARY KEY, done INTEGER, ts INTEGER)',
  ];

  static int get now => DateTime.now().millisecondsSinceEpoch;

  static Future<String?> meta(String key) async {
    final r = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  static Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await db.delete('meta', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('meta', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
