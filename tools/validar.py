#!/usr/bin/env python3
"""Valida os JSON de conteúdo. Uso: python3 tools/validar.py [arquivos...]"""
import json, sys, glob, os, re
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'conteudo')
TOPICOS = set('''tir-fisiologia tir-graves tir-bocio-nodular tir-hashimoto tir-tireoidites-outras tir-nodulo-paaf-bethesda
tir-papilifero tir-folicular tir-medular tir-anaplasico tir-geral lfa-linfonodo-histologia lfa-drenagem-clinica
lfa-padrao-folicular lfa-hiperplasia-vs-linfoma-folicular lfa-padrao-paracortical lfa-padrao-sinusal lfa-necrosantes
lfa-granulomatosas lfa-geral lin-geral lin-estadiamento lin-lh-geral lin-lh-esclerose-nodular lin-lh-celularidade-mista
lin-lh-rico-linfocitos lin-lh-deplecao lin-lh-pln lin-lnh-geral lin-folicular lin-dgcb lin-burkitt lin-malt lin-manto
lin-llc lin-micose-fungoide lin-t-outros lin-outros fora-escopo'''.split())
MODULOS = {'tireoide', 'linfadenopatias', 'linfomas', 'outros'}
FIGS = set('''fig_tireoide_anatomia fig_eixo_tireoide fig_foliculos_comparados fig_hashimoto_micro fig_papilifero_nucleo
fig_disseminacao_tireoide fig_linfonodo fig_padroes_reacionais fig_hiperplasia_vs_linfoma_folicular fig_granulomas
fig_drenagem_linfonodos fig_reed_sternberg fig_ann_arbor fig_ceu_estrelado fig_micose_fungoide fig_mapa_linfomas'''.split())
FOTOS = set('''foto_tireoide_normal foto_graves foto_bocio_coloide foto_hashimoto foto_hurthle foto_papilifero foto_psamoma
foto_folicular_invasao foto_medular_amiloide foto_anaplasico foto_linfonodo_normal foto_hiperplasia_folicular
foto_granuloma_tb foto_sarcoidose foto_rosai_dorfman foto_cmv_olho_coruja foto_reed_sternberg foto_esclerose_nodular
foto_celula_lacunar foto_celula_pipoca foto_linfoma_folicular foto_dgcb foto_burkitt foto_micose_fungoide
foto_malt_lesao_linfoepitelial'''.split())
FONTES = {'oficial', 'aluno', 'chat', 'notebooklm', 'foto', 'inferido', 'misto'}
ESTILOS = {'prova', 'professor', 'atencao', 'dica', 'mnemonico', 'definicao', 'frase'}
erros = []

def err(f, msg): erros.append(f'{os.path.relpath(f)}: {msg}')
def need(f, o, ks, ctx):
    for k in ks:
        if k not in o or o[k] in (None, '', []): err(f, f'{ctx}: falta "{k}"')
def tops(f, ts, ctx):
    for t in ts or []:
        if t not in TOPICOS: err(f, f'{ctx}: tópico inválido "{t}"')

def v_questoes(f, d):
    need(f, d, ['prova', 'questoes'], 'raiz')
    pr = d.get('prova', {}); need(f, pr, ['id', 'titulo', 'temas', 'periodo', 'gabarito_fonte'], 'prova')
    if pr.get('gabarito_fonte') not in FONTES: err(f, 'prova.gabarito_fonte inválido')
    ids = set()
    for q in d.get('questoes', []):
        c = q.get('id', '?')
        if c in ids: err(f, f'id repetido {c}')
        ids.add(c)
        need(f, q, ['id', 'numero', 'tipo', 'modulo', 'topicos', 'enunciado', 'explicacao', 'gabarito_fonte', 'confianca'], c)
        if q.get('modulo') not in MODULOS: err(f, f'{c}: módulo inválido')
        if q.get('gabarito_fonte') not in FONTES: err(f, f'{c}: gabarito_fonte inválido')
        if q.get('confianca') not in {'alta', 'media', 'baixa'}: err(f, f'{c}: confianca inválida')
        tops(f, q.get('topicos'), c)
        t = q.get('tipo')
        if t == 'multipla':
            need(f, q, ['alternativas', 'correta', 'pede'], c)
            letras = [a.get('letra') for a in q.get('alternativas', [])]
            if q.get('correta') not in letras: err(f, f'{c}: correta "{q.get("correta")}" não está nas alternativas {letras}')
            if q.get('pede') not in {'correta', 'incorreta'}: err(f, f'{c}: pede inválido')
        elif t == 'vf':
            need(f, q, ['itens'], c)
            for i, it in enumerate(q.get('itens', [])):
                if not isinstance(it.get('resposta'), bool): err(f, f'{c} item {i}: resposta deve ser boolean')
                if not it.get('texto'): err(f, f'{c} item {i}: falta texto')
                if it.get('resposta') is False and not it.get('justificativa'): err(f, f'{c} item {i}: falso sem justificativa')
        elif t == 'discursiva':
            if q.get('subitens'):
                for s in q['subitens']: need(f, s, ['letra', 'pergunta', 'resposta_modelo', 'checklist'], f'{c} subitem')
            else: need(f, q, ['resposta_modelo', 'checklist'], c)
        elif t == 'lacunas':
            need(f, q, ['lacunas'], c)
            for l in q.get('lacunas', []): need(f, l, ['dica', 'resposta'], f'{c} lacuna')
        else: err(f, f'{c}: tipo inválido "{t}"')

def v_blocos(f, blocos, ids, ctx):
    for b in blocos:
        bid = b.get('id', '?'); t = b.get('tipo'); c = f'{ctx}/{bid}'
        if bid in ids: err(f, f'{c}: id de bloco repetido')
        ids.add(bid)
        req = {'titulo': ['texto'], 'subtitulo': ['texto'], 'texto': ['md'], 'lista': ['itens'],
               'destaque': ['estilo', 'md'], 'tabela': ['colunas', 'linhas'], 'fluxo': ['passos'],
               'cartoes': ['itens'], 'figura': ['ref'], 'foto': ['ref'], 'expansivel': ['titulo', 'blocos'],
               'quiz': ['pergunta', 'opcoes', 'explicacao'], 'revelar': ['pergunta', 'resposta'], 'resumo': ['itens']}
        if t not in req: err(f, f'{c}: tipo de bloco inválido "{t}"'); continue
        need(f, b, ['id'] + req[t], c)
        if t == 'destaque' and b.get('estilo') not in ESTILOS: err(f, f'{c}: estilo inválido')
        if t == 'tabela':
            n = len(b.get('colunas', []))
            for r in b.get('linhas', []):
                if len(r) != n: err(f, f'{c}: linha com {len(r)} células, esperado {n}')
        if t == 'figura' and b.get('ref') not in FIGS: err(f, f'{c}: figura desconhecida {b.get("ref")}')
        if t == 'foto' and b.get('ref') not in FOTOS: err(f, f'{c}: foto desconhecida {b.get("ref")}')
        if t == 'quiz':
            if not isinstance(b.get('correta'), int) or not (0 <= b['correta'] < len(b.get('opcoes', []))): err(f, f'{c}: quiz.correta inválido')
        if t == 'fluxo':
            for p in b.get('passos', []): need(f, p, ['titulo'], f'{c} passo')
        if t == 'cartoes':
            for p in b.get('itens', []): need(f, p, ['titulo', 'texto'], f'{c} cartão')
        if t == 'expansivel': v_blocos(f, b.get('blocos', []), ids, c)

def v_material(f, d):
    need(f, d, ['id', 'modulo', 'ordem', 'titulo', 'minutos', 'prioridade', 'topicos', 'resumo', 'objetivos', 'blocos'], 'capítulo')
    if d.get('modulo') not in MODULOS: err(f, 'módulo inválido')
    if d.get('prioridade') not in {'alta', 'media', 'baixa'}: err(f, 'prioridade inválida')
    tops(f, d.get('topicos'), 'capítulo')
    ids = set(); v_blocos(f, d.get('blocos', []), ids, d.get('id', '?'))
    if d.get('blocos') and d['blocos'][-1].get('tipo') != 'resumo': err(f, 'último bloco deve ser "resumo"')

def v_flash(f, d):
    need(f, d, ['modulo', 'cartoes'], 'raiz')
    ids = set()
    for c in d.get('cartoes', []):
        need(f, c, ['id', 'topico', 'frente', 'verso'], c.get('id', '?'))
        if c.get('id') in ids: err(f, f'id repetido {c.get("id")}')
        ids.add(c.get('id')); tops(f, [c.get('topico')], c.get('id', '?'))

alvos = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, 'questoes', '*.json')) + glob.glob(os.path.join(ROOT, 'material', '*.json')) + glob.glob(os.path.join(ROOT, 'flashcards', '*.json')))
for f in alvos:
    try: d = json.load(open(f, encoding='utf-8'))
    except Exception as e: err(f, f'JSON inválido: {e}'); continue
    p = os.path.abspath(f)
    if '/questoes/' in p: v_questoes(f, d)
    elif '/material/' in p: v_material(f, d)
    elif '/flashcards/' in p: v_flash(f, d)
print(f'{len(alvos)} arquivo(s) verificados; {len(erros)} erro(s)')
for e in erros: print(' -', e)
sys.exit(1 if erros else 0)
