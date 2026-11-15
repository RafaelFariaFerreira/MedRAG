# Especificação de conteúdo — app de estudo "Anatomia Patológica II · P2"

Público: estudante de medicina (5º período), prova P2 da disciplina:
**Tireoide · Linfadenopatias reacionais · Linfomas**. Ela já estudou 3 dias, o conteúdo está
"embaralhado"; tem ~12h. O app precisa **organizar, segmentar e compartimentalizar**.

Fontes (única base factual — a visão do professor é a que vale na prova):
- `conteudo/md/resumo_raw.md` — resumo das aulas (Tireoide: linhas 1–597; Linfadenopatias: 599–963; Linfomas: 964–1408)
- `conteudo/md/notes_raw.md` — compilado de provas antigas com gabaritos
- `conteudo/imagens/notes/img-PPP-NNN.png` — imagens originais extraídas (PPP = página do PDF)
- `conteudo/imagens/notes_paginas/pag-PPP.png` — página inteira renderizada (inclui anotações manuscritas da aluna)

Todo texto em **português do Brasil**. JSON sempre UTF-8 válido, sem comentários, sem vírgula sobrando.
Texto "md" = texto corrido que aceita apenas `**negrito**` e `*itálico*` (sem títulos, sem links, sem listas, sem tabelas).

Regras de fidelidade:
- Não invente fatos. Se acrescentar algo de conhecimento geral consolidado que NÃO está nas fontes, marque com o prefixo "Complemento:".
- Se as fontes se contradizem, ou parecem conter erro, NÃO corrija em silêncio: registre (campo `observacao` nas questões; bloco `destaque` estilo `atencao` no material).
- Preserve as ênfases do professor ("vai cair", "não cai", "pode zerar a questão") — são ouro.

---------------------------------------------------------------------------------------------------
## 1. Tags de tópico (lista fechada)

tireoide: `tir-fisiologia` `tir-graves` `tir-bocio-nodular` `tir-hashimoto` `tir-tireoidites-outras`
`tir-nodulo-paaf-bethesda` `tir-papilifero` `tir-folicular` `tir-medular` `tir-anaplasico` `tir-geral`

linfadenopatias: `lfa-linfonodo-histologia` `lfa-drenagem-clinica` `lfa-padrao-folicular`
`lfa-hiperplasia-vs-linfoma-folicular` `lfa-padrao-paracortical` `lfa-padrao-sinusal`
`lfa-necrosantes` `lfa-granulomatosas` `lfa-geral`

linfomas: `lin-geral` `lin-estadiamento` `lin-lh-geral` `lin-lh-esclerose-nodular` `lin-lh-celularidade-mista`
`lin-lh-rico-linfocitos` `lin-lh-deplecao` `lin-lh-pln` `lin-lnh-geral` `lin-folicular` `lin-dgcb`
`lin-burkitt` `lin-malt` `lin-manto` `lin-llc` `lin-micose-fungoide` `lin-t-outros` `lin-outros`

fora do escopo da P2 (mama, endométrio, SNC etc.): `fora-escopo`

Módulos: `tireoide` | `linfadenopatias` | `linfomas` | `outros`

---------------------------------------------------------------------------------------------------
## 2. Questões — `conteudo/questoes/<id-da-prova>.json`

```json
{
  "prova": {
    "id": "p150",
    "titulo": "Prova 150 (25.1)",
    "temas": "Linfomas e Tireoide",
    "periodo": "2025.1",
    "gabarito_fonte": "oficial",
    "paginas": [13, 23]
  },
  "questoes": [ ... ]
}
```
`gabarito_fonte` (prova e questão): `oficial` | `aluno` | `chat` | `notebooklm` | `foto` (resposta marcada/corrigida visível na foto) | `inferido` (você deduziu das fontes).
`periodo`: "2025.1" etc., ou "desconhecido".

Cada questão:
```json
{
  "id": "p150-q04",
  "numero": "4",
  "tipo": "vf",
  "modulo": "tireoide",
  "topicos": ["tir-hashimoto", "tir-papilifero"],
  "enunciado": "texto md, fiel ao original (corrija só erros óbvios de OCR/digitação)",
  "pontos": 0.8,

  "alternativas": [{"letra": "A", "texto": "..."}],
  "correta": "B",
  "pede": "correta",

  "itens": [{"texto": "...", "resposta": false, "justificativa": "por que é F (ou reforço do V)"}],

  "resposta_modelo": "md — resposta que tiraria nota máxima, no estilo que o professor cobra",
  "checklist": ["ponto-chave que precisa aparecer na resposta", "..."],
  "subitens": [{"letra": "a", "pergunta": "...", "resposta_modelo": "...", "checklist": ["..."]}],

  "lacunas": [{"dica": "Variante da célula neoplásica na esclerose nodular", "resposta": "LACUNAR"}],

  "explicacao": "md — comentário didático curto: por que essa é a resposta e por que as outras não. 2–6 frases.",
  "gabarito_fonte": "oficial",
  "confianca": "alta",
  "observacao": "opcional — divergência entre gabaritos, questão anulada, item desconsiderado, etc.",
  "fora_do_escopo": false
}
```
Tipos e campos obrigatórios:
- `multipla`: `alternativas`, `correta` (letra), `pede` (`correta` | `incorreta`/exceto).
- `vf`: `itens` (cada um com `resposta` boolean e `justificativa`; justificativa obrigatória nos falsos).
- `discursiva`: `resposta_modelo` + `checklist` (3–8 pontos-chave objetivos). Se a questão tem letras a), b), c)…, use `subitens` (cada um com sua `resposta_modelo` e `checklist` de 1–4 pontos) e deixe `resposta_modelo` da questão vazia ("").
- `lacunas` (palavras cruzadas / completar): `lacunas`.
Omitir os campos que não se aplicam ao tipo. `pontos` só se constar na prova. `confianca`: `alta` | `media` | `baixa`.
`id`: `<id-prova>-qNN` (NN com 2 dígitos). Ordem original.

Regras:
- Inclua TODAS as questões de cada prova, inclusive repetidas entre provas (a repetição será usada para medir frequência).
- Questões de assunto fora da P2 (endométrio, mama, SNC): incluir com `"fora_do_escopo": true`, `modulo: "outros"`, `topicos: ["fora-escopo"]`.
- O gabarito "do chat"/NotebookLM contém ERROS. Fontes de verdade, em ordem: gabarito oficial > resposta marcada na foto/formulário (bolinha preenchida, correção do professor) > gabarito de aluno > chat. Quando houver foto da prova, OLHE a foto. Se divergir, use a mais confiável, e explique em `observacao`.
- Se nenhuma fonte dá o gabarito, deduza a partir de `resumo_raw.md` e marque `gabarito_fonte: "inferido"` com a `confianca` adequada.
- `explicacao` e `justificativa` devem ensinar (ligar ao conceito), não só repetir a resposta.

---------------------------------------------------------------------------------------------------
## 3. OCR / descrição de imagens — `conteudo/ocr/notes/pag-PPP.md` (um arquivo por página com imagem)

```
## Página PPP — <tipo: foto de prova | foto de gabarito | captura de formulário | anotações manuscritas | ilustração>
**Descrição:** 1–3 frases do que a imagem mostra (qual prova, estado da folha, o que está marcado).
**Transcrição (OCR):**
<texto impresso transcrito fielmente; para fotos de prova inteira, transcreva tudo que for legível; marque [ilegível]>
**Anotações manuscritas:**
<transcreva o que está escrito à mão: alternativas circuladas, V/F marcados, notas à margem, correções; "nenhuma" se não houver>
```
Se o texto impresso estiver ilegível na imagem, recorte/amplie com Python + PIL antes de desistir.

---------------------------------------------------------------------------------------------------
## 4. Material escrito — UM ARQUIVO POR CAPÍTULO: `conteudo/material/<id-do-capitulo>.json`

```json
{
  "id": "tir-01",
  "modulo": "tireoide",
  "ordem": 1,
  "titulo": "…",
  "minutos": 12,
  "prioridade": "alta",
  "topicos": ["tir-fisiologia"],
  "resumo": "1 frase: o que ela vai dominar aqui",
  "objetivos": ["Diferenciar…", "Reconhecer…"],
  "blocos": [ ... ]
}
```
`prioridade`: `alta` | `media` | `baixa` — pelo peso nas provas antigas + ênfase do professor.
Cada bloco tem `"id"` único no capítulo (`b01`, `b02`, …; blocos dentro de `expansivel` também) e `"tipo"`:

| tipo | campos | uso |
|---|---|---|
| `titulo` | `texto` | abre uma seção (1 conceito por seção) |
| `subtitulo` | `texto` | subdivisão |
| `texto` | `md` | parágrafo curto (máx. ~60 palavras) |
| `lista` | `itens` (array de md), `ordenada` (bool, opcional) | máx. 5 itens |
| `destaque` | `estilo`, `titulo`, `md` | caixas de ênfase (ver estilos) |
| `tabela` | `titulo`, `colunas` (array), `linhas` (array de arrays de md), `comparacao` (bool) | `comparacao: true` = 1ª coluna é o critério e as demais são entidades comparadas lado a lado |
| `fluxo` | `titulo`, `passos` [{`titulo`, `texto`}] | cadeia causal / fisiopatologia / algoritmo linear |
| `cartoes` | `titulo`, `itens` [{`titulo`, `texto`, `emoji`}] | grade de 2–6 cartões (ex.: "os 5 elementos do Hashimoto") |
| `figura` | `ref`, `legenda` | ilustração do catálogo (seção 6) |
| `foto` | `ref`, `legenda` | micrografia real do catálogo (seção 7) |
| `expansivel` | `titulo`, `blocos` | detalhe de baixo rendimento, escondido por padrão ("Aprofundar: …") |
| `quiz` | `pergunta`, `opcoes` (array), `correta` (índice 0-based), `explicacao` | checagem rápida de recuperação |
| `revelar` | `pergunta`, `resposta` (md) | recordação ativa: ela tenta lembrar e toca para ver |
| `resumo` | `itens` (array de md) | "Para levar" — último bloco do capítulo, 3–6 itens |

Estilos de `destaque`: `prova` (como isso cai / já caiu), `professor` (fala do professor),
`atencao` (pegadinha, confusão comum, inconsistência das fontes), `dica` (macete de raciocínio),
`mnemonico`, `definicao`, `frase` (frase-modelo pronta para escrever na discursiva).

Princípios (andragogia) — obrigatórios:
1. **Relevância imediata**: todo capítulo abre com um `destaque` estilo `prova` dizendo como o tema é cobrado (use as provas antigas reais).
2. **Um conceito por seção**, frases curtas, nada de parágrafo-muro. Segmentar > resumir.
3. **Compartimentalizar**: sempre que duas entidades se confundem, uma `tabela` com `comparacao: true` (mesmos critérios, mesma ordem).
4. **Recordação ativa**: 1 `quiz` ou `revelar` a cada 2–3 seções; baseie-os em como as provas perguntam.
5. **Divulgação progressiva**: o essencial fica visível; o "só por desencargo" vai em `expansivel`.
6. Ancorar em caso/problema quando possível (o professor cobra casos: "discutir diagnóstico, morfologia, perfil imuno-histoquímico, evolução e diferenciais").
7. Tom: direto, adulto, acolhedor; sem infantilizar; sem enrolação. Segunda pessoa ("você").
8. Capítulo fecha com `resumo`.
Tamanho: 25–45 blocos por capítulo (contando os internos de `expansivel`).

---------------------------------------------------------------------------------------------------
## 5. Flashcards — `conteudo/flashcards/<nome>.json` (nome livre, ex.: `tireoide.json`, `linfomas-lh.json`)

```json
{ "modulo": "tireoide",
  "cartoes": [
    {"id": "fc-tir-001", "topico": "tir-graves", "capitulo": "tir-02",
     "frente": "pergunta curta e específica (1 fato por cartão)",
     "verso": "md — resposta curta (≤ 40 palavras)",
     "dica": "opcional — pista de 2–5 palavras"}
  ] }
```
Princípio do mínimo de informação: 1 fato por cartão; listas viram vários cartões ou "cite 3…".
Prefira cartões de **discriminação** ("o que diferencia X de Y?"), de **IHQ** (marcador ↔ doença, com + e −),
de **palavra-gatilho** ("céu estrelado" → ?), e de **frase-modelo**. 45–70 cartões por módulo. Prefixos de id: `fc-tir-`, `fc-lfa-`, `fc-lin-`.

---------------------------------------------------------------------------------------------------
## 6. Catálogo de figuras (ilustrações) — `ref` válidos para o bloco `figura`

Tireoide: `fig_tireoide_anatomia` (vista anterior: hioide, cartilagens, lobos, istmo, lobo piramidal, traqueia; trajeto embriológico do ducto tireoglosso) ·
`fig_eixo_tireoide` (hipotálamo–hipófise–tireoide com retroalimentação; padrões de TSH/T4 em hipo e hiper) ·
`fig_foliculos_comparados` (folículo normal × Graves × bócio coloide/nodular atóxico) ·
`fig_hashimoto_micro` (os 5 elementos: infiltrado linfoplasmocitário, folículo linfoide, fibrose, atrofia, célula de Hürthle) ·
`fig_papilifero_nucleo` (papila com eixo fibrovascular + núcleo: cromatina clara, fenda, pseudoinclusão; corpo psamomatoso) ·
`fig_disseminacao_tireoide` (papilífero → linfática → linfonodos cervicais; folicular → hematogênica → osso, pulmão, fígado, cérebro)

Linfadenopatias: `fig_linfonodo` (cápsula, seio subcapsular/marginal, córtex com folículos = zona B, paracórtex = zona T, medula/seios, aferentes e eferente) ·
`fig_padroes_reacionais` (três linfonodos: padrão folicular, paracortical, sinusal) ·
`fig_hiperplasia_vs_linfoma_folicular` (lado a lado) ·
`fig_granulomas` (tuberculose: necrose caseosa + Langhans + halo linfocitário; sarcoidose: sem necrose; arranhadura do gato: microabscesso + paliçada) ·
`fig_drenagem_linfonodos` (silhueta: supraclavicular E/Virchow → estômago; supraclavicular D → tórax; axilar → mama; inguinal → canal anal; mediastinal → TB)

Linfomas: `fig_reed_sternberg` (variantes: clássica/diagnóstica "olho de coruja", lacunar, mononuclear, pipoca/LP) ·
`fig_ann_arbor` (silhueta com diafragma: estádios I–IV) ·
`fig_ceu_estrelado` (Burkitt: células médias monótonas + macrófagos de corpos tingíveis) ·
`fig_micose_fungoide` (epiderme com microabscesso de Pautrier, epidermotropismo, célula cerebriforme) ·
`fig_mapa_linfomas` (árvore: LH clássico/não clássico e LNH indolente/agressivo/altamente agressivo/T)

## 7. Catálogo de fotos (micrografias reais) — `ref` válidos para o bloco `foto`

`foto_tireoide_normal` `foto_graves` `foto_bocio_coloide` `foto_hashimoto` `foto_hurthle` `foto_papilifero`
`foto_psamoma` `foto_folicular_invasao` `foto_medular_amiloide` `foto_anaplasico`
`foto_linfonodo_normal` `foto_hiperplasia_folicular` `foto_granuloma_tb` `foto_sarcoidose` `foto_rosai_dorfman`
`foto_cmv_olho_coruja` `foto_reed_sternberg` `foto_esclerose_nodular` `foto_celula_lacunar` `foto_celula_pipoca`
`foto_linfoma_folicular` `foto_dgcb` `foto_burkitt` `foto_micose_fungoide` `foto_malt_lesao_linfoepitelial`
(Algumas podem não ser encontradas; o app ignora `ref` ausente. Use com moderação: 1–3 por capítulo.)

---------------------------------------------------------------------------------------------------
## 8. Validação

Rode `python3 tools/validar.py` (na raiz do projeto) — valida todos os JSON de `conteudo/questoes`, `conteudo/material`
e `conteudo/flashcards`. Só termine quando os SEUS arquivos passarem sem erro.
