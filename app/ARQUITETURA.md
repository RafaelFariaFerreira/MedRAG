# Anatopato P2 — guia para quem escreve código neste app

App Flutter (mobile-first, Android + web) de estudo para a prova P2 de Anatomia Patológica II
(Tireoide · Linfadenopatias reacionais · Linfomas). Usuária: estudante de medicina, ~12h para estudar,
conteúdo "embaralhado" — o app precisa organizar, segmentar e compartimentalizar. Todo texto de interface
em **português do Brasil**.

## Ambiente
- Flutter 3.50 / Dart 3.14: `export PATH="$HOME/development/flutter/bin:$PATH"`; rodar comandos em `app/`.
- **Importe `package:material_ui/material_ui.dart`** (Material saiu do SDK). NUNCA `package:flutter/material.dart`
  (obsoleto; são implementações separadas e não se misturam). `material_ui` já reexporta `flutter/widgets.dart`.
- APIs atuais: `color.withValues(alpha: x)` (não `withOpacity`), `WidgetStateProperty` (não `MaterialStateProperty`),
  `PopScope` (não `WillPopScope`), `DialogThemeData`. Dart 3.14 aceita dot-shorthand (`.center`) e `?widget` em listas.
- Não adicione pacotes. Dependências: `sqflite`, `sqflite_common_ffi_web`, `http`, `path`.
- Valide SEUS arquivos: `flutter analyze lib/<seus arquivos>` até zerar erros e warnings (erros de símbolo ausente
  em arquivos de OUTRO autor que ainda não existem são esperados — não crie stubs deles, não edite arquivos alheios).

## Fundação já escrita (leia antes de codar; não altere sem necessidade real)
- `lib/theme.dart` — `Pal` (paleta clara/escura via `context.pal`), `pal.modulo(id)` (cor de cada módulo:
  tireoide = terracota, linfadenopatias = teal, linfomas = violeta), `pal.soft(cor)`, `kSerif` (fonte de título
  'DMSerif'; corpo 'Inter'), `moduloNome`, `moduloIcone`, `buildTheme`.
- `lib/data/models.dart` — `Chapter`, `Modulo`, `Exam`, `Question`, `Flashcard`, `FlashState`, `ChatMsg`, `Attempt`,
  `topicoNome()`, `moduloDoTopico()`. Blocos do material são `Map<String,dynamic>` (esquema em `../conteudo/ESPECIFICACAO.md` §4).
- `lib/data/app_state.dart` — `AppState.I` (ChangeNotifier singleton): conteúdo em memória + dados dela.
  Use `ListenableBuilder(listenable: AppState.I, ...)` para reagir. Métodos: `nota/salvarNota(kind, ref, texto)`,
  `alternarDestaque(ref)`, `marcarCapitulo`, `resposta/salvarResposta`, `registrarTentativa`, `ultimaNota`, `feita`,
  `errada`, `desempenho`, `avaliarCartao`, `cartaoNovo/Vencido/Dominado`, `criarCartao`, `marcarPlano`,
  `questoesDoTopicos`, `setPref`, `apagarTudoDela`.
- `lib/data/db.dart` — SQLite (`Db.db`); tabelas de conteúdo e de usuário. Persistência sempre via `AppState`.
- `lib/services/copilot.dart` — `Copiloto.I` (mensagens, `enviar`, `parar`, `limpar`, `rascunho`, `tela`) e `TelaCtx`.
- `lib/services/claude.dart`, `lib/services/rag.dart` — API com streaming e BM25.
- `lib/ui/widgets/common.dart` — `Painel`, `Selo`, `Rotulo`, `Barra`, `CampoNota` (anotação com autosave),
  `CtxCopiloto` (registra o contexto da tela para o copiloto), `TituloAba`, `abrir(context, tela)`, `fmtMin`,
  `corPrioridade`, `nomePrioridade`, `fonteGabarito`.
- `lib/ui/widgets/md.dart` — `MdText` (inline: **negrito**, *itálico*), `mdSpans`, `MdView` (markdown em blocos).
- `lib/app_keys.dart` — `navKey` (Navigator raiz).

## Convenções de anotações (tabela `notes`, via `AppState.I.salvarNota(kind, ref, texto)`)
| kind | ref | onde |
|---|---|---|
| `bloco` | `<capId>#<blocoId>` | anotação presa a um trecho do material |
| `capitulo` | `<capId>` | anotação geral do capítulo |
| `questao` | `<questaoId>` | anotação geral da questão (todas as questões têm) |
| `vf` | `<questaoId>#<índice>` | anotação/justificativa dela por item de V ou F |
Destaques (marca-texto): `AppState.I.alternarDestaque('<capId>#<blocoId>')`, consulta em `AppState.I.destaques`.
Respostas escritas: `salvarResposta(qid, sub, texto)` — `sub` = '' (discursiva simples), letra do subitem, ou índice da lacuna.

## Pontos de entrada entre telas (assinaturas FIXAS — cada autor implementa as suas)
```dart
// lib/ui/shell.dart
class Shell extends StatefulWidget { const Shell({super.key}); }            // 5 abas + balão do copiloto
// lib/ui/home/home_tab.dart
class HomeTab extends StatelessWidget { const HomeTab({super.key}); }
// lib/ui/material/material_tab.dart
class MaterialTab extends StatelessWidget { const MaterialTab({super.key}); }
// lib/ui/material/chapter_screen.dart
class ChapterScreen extends StatefulWidget { const ChapterScreen({super.key, required this.chapterId, this.blocoInicial}); final String chapterId; final String? blocoInicial; }
// lib/ui/material/quadros_screen.dart   — todos os quadros comparativos do material, num lugar só
class QuadrosScreen extends StatelessWidget { const QuadrosScreen({super.key}); }
// lib/ui/questions/questoes_tab.dart
class QuestoesTab extends StatelessWidget { const QuestoesTab({super.key}); }
// lib/ui/questions/sessao_questoes.dart
class SessaoQuestoes extends StatefulWidget { const SessaoQuestoes({super.key, required this.titulo, required this.questoes, this.simulado = false}); final String titulo; final List<Question> questoes; final bool simulado; }
// lib/ui/flashcards/flashcards_tab.dart
class FlashcardsTab extends StatelessWidget { const FlashcardsTab({super.key}); }
// lib/ui/flashcards/sessao_flash.dart
class SessaoFlash extends StatefulWidget { const SessaoFlash({super.key, required this.titulo, required this.cartoes}); final String titulo; final List<Flashcard> cartoes; }
// lib/ui/more/mais_tab.dart
class MaisTab extends StatelessWidget { const MaisTab({super.key}); }
// lib/ui/copilot/copilot_sheet.dart — abre o copiloto por cima da tela atual (usa navKey)
Future<void> abrirCopiloto({String? rascunho, bool enviarJa = false});
```

## Direção visual
Limpo, editorial, calmo — "revista científica bem diagramada", não dashboard genérico. Fundo papel (`pal.bg`),
cartões brancos com borda fina (`Painel`), sem sombras pesadas, cantos 14–18, respiro generoso (margens laterais 16–20).
Títulos de tela em `kSerif` 26–30; corpo Inter 15/1.5. Cor só com função: cor do módulo identifica a "gaveta";
verde/vermelho só para certo/errado; âmbar para anotações dela. Ícones outline. Alvos de toque ≥ 44 px.
Tudo deve funcionar em 360–430 px de largura, claro e escuro, e respeitar `AppState.I.escalaTexto` no material.
Animações curtas (150–250 ms) e discretas. Estados vazios sempre com uma frase útil e uma ação.
