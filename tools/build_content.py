#!/usr/bin/env python3
"""Empacota o conteúdo de `conteudo/` nos assets do app Flutter (`app/assets/`).

Uso (na raiz do projeto):
    python3 tools/build_content.py            # aborta se a validação encontrar erros
    python3 tools/build_content.py --forcar   # segue mesmo com erros de esquema (JSON ilegível sempre aborta)

Gera:
    conteudo/md/provas.md, conteudo/md/resumo.md        (texto do markitdown + OCR das imagens)
    app/assets/content/{material,questoes,flashcards,rag,fotos,version}.json
    app/assets/figuras/*.png, app/assets/fotos/*.jpg     (redimensionadas)
Idempotente: rodar de novo sem mudanças na origem produz os mesmos arquivos.
"""
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from collections import Counter, OrderedDict, defaultdict

try:
    from PIL import Image, ImageOps
except ImportError:  # imagens são opcionais; o resto funciona sem PIL
    Image = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
C = os.path.join(ROOT, 'conteudo')
MD = os.path.join(C, 'md')
CACHE = os.path.join(MD, '.cache')
ASSETS = os.path.join(ROOT, 'app', 'assets')
OUT = os.path.join(ASSETS, 'content')
PDF_RESUMO = os.path.join(ROOT, 'Resumo P2 - Anatomia Patológica II .pdf')

MODULOS = [
    {'id': 'tireoide', 'titulo': 'Tireoide', 'subtitulo': 'Bócios, tireoidites e os quatro carcinomas'},
    {'id': 'linfadenopatias', 'titulo': 'Linfadenopatias reacionais', 'subtitulo': 'O linfonodo responde por compartimentos'},
    {'id': 'linfomas', 'titulo': 'Linfomas', 'subtitulo': 'Hodgkin, não Hodgkin e a imuno-histoquímica'},
]
MOD_ORDEM = {m['id']: i for i, m in enumerate(MODULOS)}
CAPITULOS_ESPERADOS = [f'tir-{i:02d}' for i in range(1, 7)] + [f'lfa-{i:02d}' for i in range(1, 6)] + \
    [f'lin-{i:02d}' for i in range(1, 8)]
PROVAS_ORDEM = ['p151', 'p150', 'p148', 'p147', 'p145lin', 'p145tgf', 'p143', 'p140', 'p136', 'p130',
                'pd1', 'pd2', 'pd3', 'pd4', 'pd5', 'comp']
FONTE_RANK = {'oficial': 0, 'foto': 1, 'misto': 2, 'aluno': 3, 'notebooklm': 4, 'chat': 5, 'inferido': 6}
CONF_RANK = {'alta': 0, 'media': 1, 'baixa': 2}
NAO_OFICIAL = {'chat', 'notebooklm', 'aluno'}
JACCARD_MIN = 0.82
ALVO_MIN, ALVO_MAX = 700, 1300
MAX_LARGURA = 1400

avisos = []


def aviso(msg):
    avisos.append(msg)


def rel(p):
    return os.path.relpath(p, ROOT)


def ler_json(p):
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def escrever(p, texto):
    """Escreve só se mudou (idempotente, preserva mtime)."""
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if os.path.exists(p):
        with open(p, encoding='utf-8') as f:
            if f.read() == texto:
                return False
    with open(p, 'w', encoding='utf-8') as f:
        f.write(texto)
    return True


def dump(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(',', ':'))


# ============================================================================ 1. validação

def validar(forcar):
    r = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'validar.py')],
                       cwd=ROOT, capture_output=True, text=True)
    saida = (r.stdout + r.stderr).strip()
    print('== Validação (tools/validar.py)')
    print('   ' + saida.replace('\n', '\n   '))
    if r.returncode != 0:
        ilegivel = 'JSON inválido' in saida
        if ilegivel or not forcar:
            print('\nABORTADO: há JSON inválido em conteudo/. Corrija os erros acima e rode de novo'
                  + ('' if ilegivel else ' (ou use --forcar para seguir mesmo assim).'))
            sys.exit(1)
        aviso('validação com erros de esquema ignorados por --forcar')


# ============================================================================ 2. Markdown finais

def _ocr(pasta, n):
    p = os.path.join(C, 'ocr', pasta, f'pag-{n:03d}.md')
    if os.path.exists(p):
        with open(p, encoding='utf-8') as f:
            return f.read().strip()
    return None


def montar_md(paginas, pasta_ocr, titulo):
    out = [f'# {titulo}', '']
    n_ocr = 0
    for n, txt in enumerate(paginas, 1):
        out += [f'<!-- página {n} -->', '', txt.strip('\n'), '']
        o = _ocr(pasta_ocr, n)
        if o:
            n_ocr += 1
            out += [f'### Imagens e anotações da página {n} (OCR)', '', o, '']
    return '\n'.join(out).rstrip() + '\n', n_ocr


def gerar_provas_md():
    raw = os.path.join(MD, 'notes_raw.md')
    if not os.path.exists(raw):
        aviso('conteudo/md/notes_raw.md ausente: provas.md não gerado')
        return None
    with open(raw, encoding='utf-8') as f:
        paginas = f.read().split('\f')
    if paginas and not paginas[-1].strip():
        paginas = paginas[:-1]
    md, n_ocr = montar_md(paginas, 'notes', 'Provas antigas com gabaritos (Notes)')
    escrever(os.path.join(MD, 'provas.md'), md)
    return {'paginas': len(paginas), 'ocr': n_ocr}


def _norm_stream(s):
    """Texto -> fluxo sem espaços/marcadores, com mapa de índices."""
    chars, idx = [], []
    for i, ch in enumerate(s):
        for c in unicodedata.normalize('NFKC', ch).lower():
            if c.isalnum():
                chars.append(c)
                idx.append(i)
    return ''.join(chars), idx


def _markitdown_paginas(pdf, n_pag, pasta):
    """Converte cada página com markitdown (uma vez; fica em cache)."""
    os.makedirs(pasta, exist_ok=True)
    faltam = [p for p in range(1, n_pag + 1) if not os.path.exists(os.path.join(pasta, f'pag-{p:03d}.md'))]
    if not faltam:
        return True
    if not shutil.which('pdfseparate'):
        aviso('pdfseparate não encontrado: não dá para reconverter o resumo página a página')
        return False
    tmp = tempfile.mkdtemp(prefix='resumo-pags-')
    try:
        subprocess.run(['pdfseparate', pdf, os.path.join(tmp, 'p-%03d.pdf')], check=True)
        py = os.path.expanduser('~/.local/share/uv/tools/markitdown/bin/python')
        if os.path.exists(py):  # um processo só, via API Python do markitdown
            prog = ('import sys\nfrom markitdown import MarkItDown\nm=MarkItDown()\n'
                    'for a,b in zip(sys.argv[1::2],sys.argv[2::2]):\n'
                    '    open(b,"w",encoding="utf-8").write(m.convert(a).text_content)\n')
            args = []
            for p in faltam:
                args += [os.path.join(tmp, f'p-{p:03d}.pdf'), os.path.join(pasta, f'pag-{p:03d}.md')]
            subprocess.run([py, '-c', prog] + args, check=True)
        else:
            exe = shutil.which('markitdown') or os.path.expanduser('~/.local/bin/markitdown')
            if not os.path.exists(exe):
                aviso('markitdown não encontrado: resumo.md sem marcação de páginas')
                return False
            for p in faltam:
                r = subprocess.run([exe, os.path.join(tmp, f'p-{p:03d}.pdf')], capture_output=True, text=True,
                                   check=True)
                with open(os.path.join(pasta, f'pag-{p:03d}.md'), 'w', encoding='utf-8') as f:
                    f.write(r.stdout)
        return True
    except subprocess.CalledProcessError as e:
        aviso(f'falha ao reconverter o resumo página a página: {e}')
        return False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _n_paginas_pdf(pdf):
    try:
        r = subprocess.run(['pdfinfo', pdf], capture_output=True, text=True, check=True)
        return int(re.search(r'^Pages:\s+(\d+)', r.stdout, re.M).group(1))
    except Exception:
        return 40


def gerar_resumo_md():
    raw_p = os.path.join(MD, 'resumo_raw.md')
    if not os.path.exists(raw_p):
        aviso('conteudo/md/resumo_raw.md ausente: resumo.md não gerado')
        return None
    with open(raw_p, encoding='utf-8') as f:
        raw = f.read()
    paginas_pdf = []
    if os.path.exists(PDF_RESUMO):
        h = hashlib.sha1(open(PDF_RESUMO, 'rb').read()).hexdigest()[:12]
        pasta = os.path.join(CACHE, f'resumo-{h}')
        n_pag = _n_paginas_pdf(PDF_RESUMO)
        if _markitdown_paginas(PDF_RESUMO, n_pag, pasta):
            for p in range(1, n_pag + 1):
                with open(os.path.join(pasta, f'pag-{p:03d}.md'), encoding='utf-8') as f:
                    paginas_pdf.append(f.read())
    else:
        aviso('PDF do resumo ausente: resumo.md sem marcação de páginas')
    if not paginas_pdf:
        md, n_ocr = montar_md([raw], 'resumo', 'Resumo das aulas (P2)')
        escrever(os.path.join(MD, 'resumo.md'), md)
        return {'paginas': 1, 'ocr': n_ocr, 'falhas': 0}

    # Alinha cada página reconvertida ao texto de resumo_raw.md (que é o texto mais limpo):
    # procura o começo de cada página no fluxo normalizado e corta o raw no início dessa linha.
    stream, idx = _norm_stream(raw)

    def inicio_linha(pos):
        lo = raw.rfind('\n', 0, pos) + 1
        # traz junto as linhas vazias / número de página solto imediatamente acima
        while lo > 0:
            ant = raw.rfind('\n', 0, lo - 1) + 1
            if re.fullmatch(r'\s*\d{0,3}\s*', raw[ant:lo]):
                lo = ant
            else:
                break
        return lo

    cortes, cursor, falhas = [], 0, 0
    for n, pt in enumerate(paginas_pdf, 1):
        sp, _ = _norm_stream(pt)
        sp_sem_num = re.sub(r'^\d{1,3}', '', sp)
        achou = None
        if len(sp_sem_num) >= 12:
            for k in range(0, min(len(sp_sem_num), 400), 25):
                w = sp_sem_num[k:k + 30]
                if len(w) < 12:
                    break
                f = stream.find(w, cursor)
                if f >= 0:
                    achou = max(cursor, f - k)
                    break
            if achou is None:
                falhas += 1
                aviso(f'resumo: não consegui localizar o início da página {n} no resumo_raw.md')
        if achou is None:
            cortes.append(None)
            continue
        cursor = achou
        cortes.append(inicio_linha(idx[achou]))
    # monta as fatias: página sem corte fica vazia (imagem pura ou não localizada)
    pos = [c for c in cortes]
    paginas = []
    validos = [(i, c) for i, c in enumerate(pos) if c is not None]
    for i, c in enumerate(pos):
        if c is None:
            paginas.append('')
            continue
        prox = next((c2 for j, c2 in validos if j > i), len(raw))
        ini = 0 if i == validos[0][0] else c
        paginas.append(raw[ini:prox])
    md, n_ocr = montar_md(paginas, 'resumo', 'Resumo das aulas (P2)')
    escrever(os.path.join(MD, 'resumo.md'), md)
    return {'paginas': len(paginas), 'ocr': n_ocr, 'falhas': falhas}


# ============================================================================ 3. material

def _limpar_blocos(blocos, figs, fotos, cap):
    out = []
    for b in blocos:
        t = b.get('tipo')
        if t == 'figura' and b.get('ref') not in figs:
            aviso(f'{cap}: bloco figura "{b.get("ref")}" removido (PNG ausente em conteudo/figuras)')
            continue
        if t == 'foto' and b.get('ref') not in fotos:
            aviso(f'{cap}: bloco foto "{b.get("ref")}" removido (fora do manifesto de fotos)')
            continue
        if t == 'expansivel':
            b = dict(b)
            b['blocos'] = _limpar_blocos(b.get('blocos', []), figs, fotos, cap)
            if not b['blocos']:
                aviso(f'{cap}: expansível "{b.get("titulo")}" ficou vazio e foi removido')
                continue
        out.append(b)
    return out


def gerar_material(fotos_refs):
    figs = {os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(C, 'figuras', '*.png'))}
    caps = []
    for p in sorted(glob.glob(os.path.join(C, 'material', '*.json'))):
        d = ler_json(p)
        d['blocos'] = _limpar_blocos(d.get('blocos', []), figs, fotos_refs, d.get('id', rel(p)))
        caps.append(d)
    caps.sort(key=lambda c: (MOD_ORDEM.get(c.get('modulo'), 99), c.get('ordem', 0), c.get('id', '')))
    ids = {c.get('id') for c in caps}
    for e in CAPITULOS_ESPERADOS:
        if e not in ids:
            aviso(f'capítulo esperado ausente: {e}')
    return {'modulos': MODULOS, 'capitulos': caps}


# ============================================================================ 4. questões

def _sem_acento(s):
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn')


def _tokens(s):
    s = _sem_acento(s.lower())
    s = re.sub(r'[^\w\s]', ' ', s).replace('_', ' ')
    return set(s.split())


def _texto_comparacao(q):
    partes = [q.get('enunciado', '')]
    if not (q.get('tipo') == 'discursiva' and q.get('subitens')):
        partes += [a.get('texto', '') for a in q.get('alternativas', [])]
        partes += [i.get('texto', '') for i in q.get('itens', [])]
        if q.get('tipo') == 'lacunas':
            partes += [l.get('dica', '') for l in q.get('lacunas', [])]
    return ' '.join(partes)


def gerar_questoes():
    arquivos = sorted(glob.glob(os.path.join(C, 'questoes', '*.json')))
    por_id = {}
    for p in arquivos:
        d = ler_json(p)
        pid = d.get('prova', {}).get('id') or os.path.splitext(os.path.basename(p))[0]
        if pid in por_id:
            aviso(f'prova {pid} duplicada ({rel(p)}); ignorada')
            continue
        por_id[pid] = d
    for e in PROVAS_ORDEM:
        if e not in por_id:
            aviso(f'prova esperada ausente: {e}')
    extras = sorted(k for k in por_id if k not in PROVAS_ORDEM)
    for e in extras:
        aviso(f'prova fora da lista esperada incluída no fim: {e}')
    ordem = [k for k in PROVAS_ORDEM if k in por_id] + extras
    provas, questoes, vistos = [], [], set()
    prova_idx = {}
    for i, pid in enumerate(ordem):
        d = por_id[pid]
        pr = dict(d['prova'])
        pr['id'] = pid
        provas.append(pr)
        prova_idx[pid] = i
        for q in d.get('questoes', []):
            q = dict(q)
            if q.get('id') in vistos:
                novo = f'{pid}-{q.get("id")}'
                aviso(f'id de questão repetido {q.get("id")} -> renomeado {novo}')
                q['id'] = novo
            vistos.add(q['id'])
            q['prova_id'] = pid
            questoes.append(q)
    titulo = {p['id']: p.get('titulo', p['id']) for p in provas}

    # --- agrupamento de questões repetidas (union-find, Jaccard de tokens)
    toks = [_tokens(_texto_comparacao(q)) for q in questoes]
    pai = list(range(len(questoes)))

    def raiz(i):
        while pai[i] != i:
            pai[i] = pai[pai[i]]
            i = pai[i]
        return i

    for i in range(len(questoes)):
        for j in range(i + 1, len(questoes)):
            if questoes[i].get('tipo') != questoes[j].get('tipo') or \
                    questoes[i]['prova_id'] == questoes[j]['prova_id']:  # só entre provas diferentes
                continue
            a, b = toks[i], toks[j]
            if not a or not b:
                continue
            if len(a & b) / len(a | b) >= JACCARD_MIN:
                ri, rj = raiz(i), raiz(j)
                if ri != rj:
                    pai[max(ri, rj)] = min(ri, rj)
    grupos = defaultdict(list)
    for i in range(len(questoes)):
        grupos[raiz(i)].append(i)
    repetidos = []
    for membros in grupos.values():
        membros.sort()
        gid = questoes[membros[0]]['id']
        provas_g = []
        for m in membros:
            pid = questoes[m]['prova_id']
            if pid not in provas_g:
                provas_g.append(pid)
        provas_g.sort(key=lambda x: prova_idx[x])

        def chave(m):
            q = questoes[m]
            return (FONTE_RANK.get(q.get('gabarito_fonte'), 9), CONF_RANK.get(q.get('confianca'), 9),
                    prova_idx[q['prova_id']], m)
        rep = min(membros, key=chave)
        for m in membros:
            q = questoes[m]
            q['grupo'] = gid
            q['freq'] = len(provas_g)
            q['provas_do_grupo'] = [titulo[x] for x in provas_g]
            q['representante'] = (m == rep)
        if len(membros) > 1:
            repetidos.append((len(provas_g), [questoes[m]['id'] for m in membros], questoes[rep]['id'],
                              questoes[membros[0]].get('enunciado', '')))
    repetidos.sort(key=lambda r: (-r[0], r[1][0]))
    return {'provas': provas, 'questoes': questoes}, repetidos


# ============================================================================ 5. flashcards

def gerar_flashcards():
    arquivos = []
    for p in sorted(glob.glob(os.path.join(C, 'flashcards', '*.json'))):
        d = ler_json(p)
        arquivos.append((MOD_ORDEM.get(d.get('modulo'), 99), os.path.basename(p), d))
    arquivos.sort(key=lambda x: (x[0], x[1]))
    cartoes, ids = [], set()
    for _, nome, d in arquivos:
        for c in d.get('cartoes', []):
            c = dict(c)
            c['modulo'] = d.get('modulo')
            cid = c.get('id') or f'fc-{nome}-{len(cartoes)}'
            if cid in ids:
                n = 2
                while f'{cid}-{n}' in ids:
                    n += 1
                aviso(f'flashcard id repetido {cid} ({nome}) -> renomeado {cid}-{n}')
                cid = f'{cid}-{n}'
            c['id'] = cid
            ids.add(cid)
            cartoes.append(c)
    for m in MODULOS:
        if not any(x[2].get('modulo') == m['id'] for x in arquivos):
            aviso(f'flashcards do módulo {m["id"]} ausentes')
    return {'cartoes': cartoes}


# ============================================================================ 6. RAG

BULLETS = {'●': '•', '○': '–', '■': '·', '▪': '·', '\uf0b7': '•', '\uf0a7': '–'}
RE_SENT = re.compile(r'(?<=[.!?…])\s+(?=[A-ZÀ-Ú0-9“"(•–])')


def _frases(t):
    return [s for s in RE_SENT.split(t) if s.strip()]


class Unidade:
    __slots__ = ('texto', 'titulo', 'secao', 'prosa', 'q')

    def __init__(self, texto, secao, titulo=False, prosa=True, q=None):
        self.texto, self.secao, self.titulo, self.prosa, self.q = texto, secao, titulo, prosa, q


def _juntar(linhas):
    return '\n'.join(linhas).strip()


def empacotar(unidades, fonte, prefixo='', rotulo=None):
    """Agrupa unidades em chunks de ~700–1300 caracteres.
    - corta de preferência antes de um título; nunca deixa título pendurado no fim;
    - unidade grande demais é cortada por frases, com sobreposição de 1 frase;
    - `rotulo(lista_de_unidades, secao)` permite montar a seção (ex.: "Questões 4–6")."""
    chunks = []
    cur = []  # lista de (texto, unidade)

    def tam():
        return sum(len(t) + 1 for t, _ in cur)

    def flush(sobrepor=None):
        nonlocal cur
        pend = []
        while cur and cur[-1][1].titulo:  # título no fim vai para o próximo chunk
            pend.insert(0, cur.pop())
        if cur and any(not u.titulo for _, u in cur):
            us = [u for _, u in cur]
            secao = next((u.texto for u in us if u.titulo), None) if us[0].titulo else None
            secao = secao or us[0].secao
            if rotulo:
                secao = rotulo(us, secao)
            texto = _juntar([t for t, _ in cur])
            chunks.append({'fonte': fonte, 'secao': secao, 'texto': prefixo + texto})
        cur = pend
        if sobrepor:
            cur.append(sobrepor)

    for u in unidades:
        if u.titulo:
            if tam() >= 450:
                flush()
            cur.append((u.texto, u))
            continue
        if tam() + len(u.texto) + 1 <= ALVO_MAX:
            cur.append((u.texto, u))
            continue
        if tam() >= ALVO_MIN or (not u.prosa and len(u.texto) <= ALVO_MAX and tam() >= 300):
            # corte natural antes desta unidade; sobreposição de 1 frase só em prosa contínua
            ult = cur[-1] if cur else None
            sob = None
            if u.prosa and ult and ult[1].prosa and not ult[1].titulo:
                fr = _frases(ult[0])
                if fr and len(fr[-1]) <= 220 and len(fr[-1]) < len(ult[0]):
                    sob = (fr[-1], Unidade(fr[-1], ult[1].secao, prosa=True, q=ult[1].q))
            flush(sob)
            if tam() + len(u.texto) + 1 <= ALVO_MAX:
                cur.append((u.texto, u))
                continue
        # unidade não cabe: corta por linhas e, se preciso, por frases (sobreposição de 1 pedaço)
        pecas = []  # (texto, separador_antes)
        for i, linha in enumerate(u.texto.split('\n')):
            frs = _frases(linha) if len(linha) > 300 else [linha]
            for j, f in enumerate(frs):
                while len(f) > ALVO_MAX - 200:  # sem pontuação: corta em espaço
                    k = f.rfind(' ', 200, ALVO_MAX - 200)
                    k = k if k > 0 else ALVO_MAX - 200
                    pecas.append((f[:k], '\n' if (i and not j) else ' '))
                    f, j = f[k:].lstrip(), 1
                pecas.append((f, '\n' if (i and not j) else ' '))
        buf = ''
        for f, sep in pecas:
            if buf and tam() + len(buf) + len(f) + 2 > ALVO_MAX:
                cur.append((buf, u))
                flush()
                ult = buf.split('\n')[-1]
                ult = (_frases(ult) or [ult])[-1]
                cont = f'[questão {u.q}, continuação] ' if (u.q is not None and not u.prosa) else ''
                buf = cont + ult
            buf = (buf + sep + f) if buf else f
        if buf:
            cur.append((buf, u))
    flush()
    # chunks minúsculos: junta ao anterior da mesma seção se couber
    final = []
    for c in chunks:
        if len(c['texto']) - len(prefixo) < 40:  # resto inútil ("Não tem foto da prova")
            continue
        if final and len(c['texto']) < 250 and final[-1]['fonte'] == c['fonte'] \
                and len(final[-1]['texto']) + len(c['texto']) <= ALVO_MAX + 100 \
                and final[-1]['texto'].startswith(prefixo):
            final[-1]['texto'] += '\n' + c['texto'][len(prefixo):]
        else:
            final.append(c)
    return final


def _limpar_linha_tabela(l):
    if re.fullmatch(r'\s*\|?(\s*:?-{3,}:?\s*\|)+\s*:?-*:?\s*\|?\s*', l):
        return None
    if l.strip().startswith('|'):
        cel = [c.strip() for c in l.strip().strip('|').split('|')]
        return ' '.join(c for c in cel if c)
    return l


def _tabela_md_para_linhas(linhas):
    """Tabela markdown bem formada (OCR) -> 1 linha legível por registro."""
    rows = [[c.strip() for c in l.strip().strip('|').split('|')] for l in linhas
            if not re.fullmatch(r'\s*\|?(\s*:?-{3,}:?\s*\|)+\s*:?-*:?\s*\|?\s*', l)]
    if len(rows) < 2:
        return [' '.join(c for c in r if c) for r in rows]
    cab, out = rows[0], []
    for r in rows[1:]:
        partes = [r[0] + ':'] if r and r[0] else []
        for h, v in zip(cab[1:], r[1:]):
            if v:
                partes.append(f'{h} = {v};')
        linha = ' '.join(partes).rstrip(';')
        out.append(linha if linha.endswith(('.', '!', '?', ')')) else linha + '.')
    return out


def _limpar_ocr(texto):
    """Bloco de OCR -> (tipo, título, linhas limpas)."""
    linhas = texto.splitlines()
    tipo = 'Imagem'
    m = re.match(r'##\s*P[áa]gina\s*\d+\s*[—-]+\s*(.+)', linhas[0]) if linhas else None
    if m:
        tipo = m.group(1).strip()
        linhas = linhas[1:]
    out, tab, titulo = [], [], None
    secao_anot = em_codigo = False

    def solta_tab():
        if tab:
            out.extend(_tabela_md_para_linhas(tab))
            tab.clear()

    for l in linhas:
        s = l.strip()
        if s.startswith('|'):
            tab.append(s)
            continue
        solta_tab()
        if not s:
            continue
        if s.startswith('**Descrição:**'):
            out.append('Descrição da imagem: ' + s[len('**Descrição:**'):].strip())
            continue
        if s.startswith('**Transcrição'):
            resto = re.sub(r'^\*\*Transcrição[^*]*\*\*', '', s).strip()
            secao_anot = False
            out.append('Texto da imagem:' + (' ' + resto if resto else ''))
            continue
        if s.startswith('**Anotações manuscritas:**'):
            resto = s[len('**Anotações manuscritas:**'):].strip()
            secao_anot = True
            out.append('Anotações manuscritas:' + (' ' + resto if resto else ''))
            continue
        if secao_anot and re.fullmatch(r'nenhuma\.?', s, re.I):
            out[-1] += ' nenhuma.'
            continue
        if s.startswith('```'):
            em_codigo = not em_codigo
            continue
        if em_codigo or re.fullmatch(r'\[rodap[ée]\]\s*\d*|\d{1,3}', s):
            continue
        s = s.replace('**', '')
        if titulo is None and out and out[-1].startswith('Texto da imagem') and len(s) <= 90 \
                and not s.startswith('['):
            titulo = s.rstrip(':')
        out.append(s)
    solta_tab()
    # "Anotações manuscritas: nenhuma." no fim não ajuda o RAG
    if out and re.fullmatch(r'Anotações manuscritas: nenhuma\.', out[-1]):
        out.pop()
    if out and out[-1] == 'Texto da imagem:':
        out.pop()
    return tipo, titulo, out


def _paginas_md(caminho):
    """Lê o md processado -> lista de (n, texto_da_página, ocr_ou_None)."""
    with open(caminho, encoding='utf-8') as f:
        t = f.read()
    partes = re.split(r'^<!-- página (\d+) -->\s*$', t, flags=re.M)
    out = []
    for i in range(1, len(partes), 2):
        n, corpo = int(partes[i]), partes[i + 1]
        m = re.search(r'^### Imagens e anotações da página \d+ \(OCR\)\s*$', corpo, re.M)
        if m:
            out.append((n, corpo[:m.start()], corpo[m.end():].strip()))
        else:
            out.append((n, corpo, None))
    return out


# ---------------------------------------------------------------- resumo

def _eh_titulo_resumo(s, anterior):
    if not s or s[0] in '●○■•-–' or len(s) > 70:
        return False
    if s.startswith('→ ') and re.match(r'→ (Linfoma|Micose|Doença|Carcinoma|Tireoidite)', s):
        return True
    letras = [c for c in s if c.isalpha()]
    if len(letras) < 4:
        return False
    palavras = s.split()
    maius = sum(c.isupper() for c in letras) / len(letras)
    ant_fecha = (not anterior) or anterior[-1] in '.!?:)”"' or re.fullmatch(r'\d{1,3}', anterior) is not None
    if maius > 0.8 and len(palavras) <= 7 and s[-1] not in '.,;!)' and ant_fecha:
        return True
    if maius <= 0.8 and s[0].isupper() and len(palavras) <= 7 and s[-1] not in '.,;:' and ant_fecha \
            and not re.match(r'(Obs|OBS|Ex|Bogliolo|Robbins)\b', s) and not re.search(r'\b(é|são|foi|tem|há)\b', s):
        return True
    return False


def _unidades_texto(texto, secao_atual, eh_titulo, estado, modo='prosa'):
    """Quebra texto corrido (linhas quebradas do markitdown) em unidades: itens com marcador,
    parágrafos, notas de rodapé e títulos. `estado` guarda o nº da última nota entre páginas.
    Devolve (unidades, secao_atual)."""
    us = []
    buf = []
    anterior = ''

    def solta():
        if buf:
            us.append(Unidade(' '.join(buf), secao_atual))
            buf.clear()

    for l in texto.splitlines():
        l = _limpar_linha_tabela(l)
        if l is None:
            continue
        s = re.sub(r'\s+', ' ', l).strip()
        if not s:
            if modo == 'prosa':
                solta()
            continue
        if re.fullmatch(r'\d{1,3}', s):  # número de página solto
            continue
        for k, v in BULLETS.items():
            if s.startswith(k):
                s = v + ' ' + s[len(k):].strip()
        if eh_titulo(s, anterior):
            solta()
            secao_atual = s.lstrip('→ ').strip()
            us.append(Unidade(s, secao_atual, titulo=True))
            anterior = s
            continue
        m = re.match(r'^(\d{1,2}) ([A-Za-zÀ-ú].*)', s)  # nota de rodapé: numeração sequencial
        if m and int(m.group(1)) != estado.get('nota', 0) + 1:
            m = None
        if m:
            estado['nota'] = int(m.group(1))
        novo_item = s[0] in '•–·' or re.match(r'^(\d{1,2}[.)]|[a-z]\)|Obs\b|OBS\b)', s) or m \
            or (buf and s[0].isupper() and (len(anterior) < 62 or anterior[-1] in '.!?'))
        if novo_item:
            solta()
            if m:
                s = f'(nota {m.group(1)}: {m.group(2)}'
        buf.append(s)
        anterior = s
    solta()
    for u in us:  # notas de rodapé (de uma ou várias linhas): fecha o parêntese
        if u.texto.startswith('(nota '):
            u.texto += ')'
    return us, secao_atual


def chunks_resumo():
    p = os.path.join(MD, 'resumo.md')
    if not os.path.exists(p):
        return []
    fontes = OrderedDict((k, []) for k in ('Tireoide', 'Linfadenopatias', 'Linfomas'))
    modulo = 'Tireoide'
    secao = 'TIREOIDE'
    estado = {}
    for n, texto, ocr in _paginas_md(p):
        us, secao = _unidades_texto(texto, secao, _eh_titulo_resumo, estado)
        for u in us:
            if u.titulo:
                nt = _sem_acento(u.texto.lower())
                if modulo == 'Tireoide' and nt.startswith('linfadenopatias reacionais'):
                    modulo = 'Linfadenopatias'
                elif modulo == 'Linfadenopatias' and nt == 'linfomas':
                    modulo = 'Linfomas'
            fontes[modulo].append(u)
        if ocr:
            tipo, titulo, linhas = _limpar_ocr(ocr)
            sec = f'Imagem p. {n}: {titulo}' if titulo else f'Imagem p. {n} ({secao})'
            fontes[modulo].append(Unidade(sec, sec, titulo=True))
            # descrição + texto da imagem: cada linha é uma unidade (tabelas viram 1 linha por registro)
            for l in linhas:
                fontes[modulo].append(Unidade(l, sec, prosa=False))
            # depois da imagem, volta ao título corrente do texto
            fontes[modulo].append(Unidade(secao, secao, titulo=True))
    out = []
    for mod, us in fontes.items():
        # remove títulos repetidos em sequência (ex.: retorno ao título após imagem seguido de outro título)
        limpo = []
        for u in us:
            if u.titulo and limpo and limpo[-1].titulo:
                limpo[-1] = u
            else:
                limpo.append(u)
        out += empacotar(limpo, f'Resumo · {mod}')
    return out


# ---------------------------------------------------------------- provas

RE_PROVA = re.compile(r'^(Prova \d+ \(\d+\.\d\)|Ano desconhecido \d+|Compilado de questões[^\n]*?)\s*(\(([^)]*)\))?\s*$')
RE_PARTE = re.compile(r'^(Prova transcrita|Fotos originais|Gabarito(?: oficial| Notebook LM| por aluno| chat(?:\s*/\s*aluno)?)?)\s*$')
RE_QNUM = re.compile(r'^(\d{1,2})\s*(?:[.)]|\s-|-\s|–)\s*\S')


def _fonte_gabarito(rotulo, prova_json):
    r = rotulo.lower()
    if 'oficial' in r:
        return 'oficial'
    if 'notebook' in r:
        return 'notebooklm'
    if 'chat' in r:
        return 'chat'
    if 'aluno' in r:
        return 'aluno'
    return (prova_json or {}).get('gabarito_fonte')


def chunks_provas():
    p = os.path.join(MD, 'provas.md')
    if not os.path.exists(p):
        return []
    provas_json = {}
    for f in glob.glob(os.path.join(C, 'questoes', '*.json')):
        try:
            pr = ler_json(f).get('prova', {})
        except Exception:
            continue
        for pg in (pr.get('paginas') or [])[:1]:
            provas_json[pg] = pr

    # 1) segmenta em (prova, parte) -> linhas, e blocos de OCR
    secoes = []  # dicts: fonte, parte, linhas | ocr
    atual = None
    titulos_usados = Counter()
    for n, texto, ocr in _paginas_md(p):
        linhas = texto.strip('\n').splitlines()
        nao_vazias = [l.strip() for l in linhas if l.strip() and not re.fullmatch(r'\d{1,3}', l.strip())]
        if len(nao_vazias) == 1 and RE_PROVA.match(nao_vazias[0]):
            m = RE_PROVA.match(nao_vazias[0])
            pj = provas_json.get(n)
            base = m.group(1).strip()
            titulo = (pj or {}).get('titulo') or base
            titulos_usados[titulo] += 1
            if titulos_usados[titulo] > 1 and m.group(3):
                titulo = f'{titulo} · {m.group(3)}'
            atual = {'fonte': titulo, 'json': pj, 'parte': None}
            continue
        if atual is None:  # capa e sumário
            continue
        for l in linhas:
            s = l.strip()
            mp = RE_PARTE.match(s)
            if mp:
                atual['parte'] = mp.group(1)
                secoes.append({'fonte': atual['fonte'], 'json': atual['json'], 'parte': mp.group(1), 'linhas': []})
                continue
            if not secoes or secoes[-1].get('ocr') is not None or secoes[-1]['fonte'] != atual['fonte']:
                secoes.append({'fonte': atual['fonte'], 'json': atual['json'], 'cont': True,
                               'parte': atual['parte'] or 'Prova transcrita', 'linhas': []})
            secoes[-1]['linhas'].append(l)
        if ocr:
            secoes.append({'fonte': atual['fonte'], 'json': atual['json'], 'parte': None, 'ocr': ocr, 'pag': n})

    # junta seções consecutivas da mesma prova/parte (quebradas por OCR no meio)
    # (a parte continua na página seguinte mesmo com um bloco de OCR entre elas)
    juntas, ult_texto = [], None
    for s in secoes:
        if s.get('ocr') is None and s.get('cont') and ult_texto is not None \
                and ult_texto['fonte'] == s['fonte'] and ult_texto['parte'] == s['parte']:
            ult_texto['linhas'] += s['linhas']
            continue
        juntas.append(s)
        if s.get('ocr') is None:
            ult_texto = s
    # OCRs vão depois do texto da prova (não interrompem as questões)
    texto_s = [s for s in juntas if s.get('ocr') is None]
    ocr_s = [s for s in juntas if s.get('ocr') is not None]

    out = []
    for s in texto_s:
        if s['parte'] == 'Fotos originais':
            continue
        us = _unidades_prova(s['linhas'])
        if not us:
            continue
        parte = s['parte']
        prefixo = ''
        if parte.startswith('Gabarito'):
            fg = _fonte_gabarito(parte, s['json'])
            if fg in NAO_OFICIAL:
                prefixo = '(gabarito não oficial) '

        def rotulo(lista, secao, parte=parte):
            nums = [u.q for u in lista if u.q is not None]
            base = 'Questões' if parte == 'Prova transcrita' else parte
            if not nums:
                return base if parte != 'Prova transcrita' else 'Prova transcrita'
            a, b = min(nums), max(nums)
            faixa = f'{a}' if a == b else f'{a}–{b}'
            if parte == 'Prova transcrita':
                return f'Questão {faixa}' if a == b else f'Questões {faixa}'
            return f'{parte} · questão {faixa}' if a == b else f'{parte} · questões {faixa}'
        out += empacotar(us, s['fonte'], prefixo, rotulo)
    for s in ocr_s:
        tipo, titulo, linhas = _limpar_ocr(s['ocr'])
        sec = f'{tipo[:1].upper()}{tipo[1:]} (p. {s["pag"]})'
        us = [Unidade(l, sec, prosa=True) for l in linhas]
        out += empacotar(us, s['fonte'], '', None)
    # mantém a ordem do documento: prova por prova
    ordem_f = list(OrderedDict.fromkeys(s['fonte'] for s in juntas))
    out.sort(key=lambda c: ordem_f.index(c['fonte']))
    return out


def _unidades_prova(linhas):
    """Linhas de uma parte de prova -> unidades = questões inteiras (ou itens de gabarito)."""
    us, cur, num, ult = [], [], None, 0

    def solta():
        if cur:
            us.append(Unidade(_juntar(cur), '', prosa=False, q=num))
            cur.clear()

    for l in linhas:
        l = _limpar_linha_tabela(l)
        if l is None:
            continue
        s = re.sub(r'\s+', ' ', l).strip()
        if not s or re.fullmatch(r'\d{1,3}', s):
            continue
        for k, v in BULLETS.items():
            if s.startswith(k):
                s = v + ' ' + s[len(k):].strip()
        m = RE_QNUM.match(s)
        if m and (num is None or 0 < int(m.group(1)) - ult <= 3):
            solta()
            num = ult = int(m.group(1))
            cur.append(s)
            continue
        novo = re.match(r'^([a-zA-Z][).]|\(\s?\)|_{2,}|[•–·]|✅|📌|\[)\s*', s)
        if cur and not novo and not re.search(r'[:?]$', cur[-1]):
            cur[-1] += ' ' + s
        else:
            cur.append(s)
    solta()
    return us


def gerar_rag():
    r = chunks_resumo()
    p = chunks_provas()
    return {'chunks': r + p}, len(r), len(p)


# ============================================================================ 7. imagens

def _sincronizar(origens, destino, max_lado, so_largura):
    os.makedirs(destino, exist_ok=True)
    gk = os.path.join(destino, '.gitkeep')
    if not os.path.exists(gk):
        open(gk, 'w').close()
    feitos, nomes = 0, set()
    for src in origens:
        nome = os.path.basename(src)
        nomes.add(nome)
        dst = os.path.join(destino, nome)
        if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
            continue
        if Image is None:
            shutil.copy2(src, dst)
            aviso(f'PIL ausente: {nome} copiada sem redimensionar')
            feitos += 1
            continue
        im = Image.open(src)
        im = ImageOps.exif_transpose(im)
        w, h = im.size
        lado = w if so_largura else max(w, h)
        if lado > max_lado:
            f = max_lado / lado
            im = im.resize((max(1, round(w * f)), max(1, round(h * f))), Image.LANCZOS)
        if nome.lower().endswith(('.jpg', '.jpeg')):
            im.convert('RGB').save(dst, 'JPEG', quality=85, optimize=True, progressive=True)
        else:
            im.save(dst, 'PNG', optimize=True)
        feitos += 1
    removidos = 0
    for f in os.listdir(destino):
        if f != '.gitkeep' and f not in nomes and os.path.isfile(os.path.join(destino, f)):
            os.remove(os.path.join(destino, f))
            removidos += 1
    return len(nomes), feitos, removidos


def carregar_manifesto_fotos():
    p = os.path.join(C, 'fotos', 'manifest.json')
    if not os.path.exists(p):
        return []
    try:
        d = ler_json(p)
    except Exception as e:
        aviso(f'conteudo/fotos/manifest.json ilegível ({e}); fotos ignoradas')
        return []
    if isinstance(d, dict):
        d = d.get('fotos', [])
    out = []
    for x in d:
        if not isinstance(x, dict) or not x.get('ref'):
            aviso(f'entrada do manifesto de fotos sem "ref": {x}')
            continue
        arq = x.get('arquivo') or x.get('file') or x.get('path')
        if arq and not os.path.exists(os.path.join(C, 'fotos', os.path.basename(arq))):
            aviso(f'foto {x["ref"]}: arquivo {arq} não existe; removida do manifesto')
            continue
        out.append(x)
    return out


# ============================================================================ main

def main():
    forcar = '--forcar' in sys.argv
    os.chdir(ROOT)
    validar(forcar)

    print('\n== Markdown')
    pm = gerar_provas_md()
    rm = gerar_resumo_md()
    if pm:
        print(f'   conteudo/md/provas.md: {pm["paginas"]} páginas, {pm["ocr"]} com OCR')
    if rm:
        print(f'   conteudo/md/resumo.md: {rm["paginas"]} páginas, {rm["ocr"]} com OCR'
              + (f', {rm["falhas"]} página(s) não localizadas' if rm.get('falhas') else ''))

    fotos = carregar_manifesto_fotos()
    material = gerar_material({f['ref'] for f in fotos})
    questoes, repetidos = gerar_questoes()
    flash = gerar_flashcards()
    rag, n_rr, n_rp = gerar_rag()

    gerados = OrderedDict([('material.json', material), ('questoes.json', questoes),
                           ('flashcards.json', flash), ('rag.json', rag), ('fotos.json', fotos)])
    os.makedirs(OUT, exist_ok=True)
    h = hashlib.sha1()
    for nome, obj in gerados.items():
        s = dump(obj)
        h.update(nome.encode() + b'\0' + s.encode('utf-8'))
        escrever(os.path.join(OUT, nome), s)
    versao = h.hexdigest()[:12]
    escrever(os.path.join(OUT, 'version.json'), dump({'version': versao}))

    figs = sorted(glob.glob(os.path.join(C, 'figuras', '*.png')))
    fts = sorted(f for e in ('*.jpg', '*.jpeg', '*.JPG', '*.png') for f in glob.glob(os.path.join(C, 'fotos', e)))
    rf = _sincronizar(figs, os.path.join(ASSETS, 'figuras'), MAX_LARGURA, True)
    rt = _sincronizar(fts, os.path.join(ASSETS, 'fotos'), MAX_LARGURA, False)

    # ------------------------------------------------------------ resumo
    print('\n== Material')
    cpm = Counter(c['modulo'] for c in material['capitulos'])
    for m in MODULOS:
        ids = [c['id'] for c in material['capitulos'] if c['modulo'] == m['id']]
        print(f'   {m["id"]:16s} {cpm.get(m["id"], 0):2d} capítulo(s)  {" ".join(ids)}')
    print('\n== Questões')
    qpp = Counter(q['prova_id'] for q in questoes['questoes'])
    for pr in questoes['provas']:
        print(f'   {pr["id"]:8s} {qpp.get(pr["id"], 0):3d}  {pr.get("titulo", "")}  [{pr.get("gabarito_fonte", "?")}]')
    print(f'   total: {len(questoes["questoes"])} questões em {len(questoes["provas"])} provas; por tipo: '
          + ', '.join(f'{k} {v}' for k, v in Counter(q['tipo'] for q in questoes['questoes']).most_common()))
    print(f'   representantes: {sum(1 for q in questoes["questoes"] if q["representante"])}')
    print(f'\n== Grupos de questões repetidas ({len(repetidos)}; freq = nº de provas)')
    for freq, ids, rep, enun in repetidos:
        e = re.sub(r'\s+', ' ', enun)[:90]
        print(f'   freq {freq}  {", ".join(ids)}  (rep. {rep})\n            "{e}…"')
    print('\n== Flashcards')
    fpm = Counter(c['modulo'] for c in flash['cartoes'])
    for m in MODULOS:
        print(f'   {m["id"]:16s} {fpm.get(m["id"], 0):3d}')
    print('\n== RAG')
    ch = rag['chunks']
    media = sum(len(c['texto']) for c in ch) / len(ch) if ch else 0
    print(f'   {len(ch)} chunks (resumo {n_rr}, provas {n_rp}); tamanho médio {media:.0f} caracteres; '
          f'min {min((len(c["texto"]) for c in ch), default=0)}, max {max((len(c["texto"]) for c in ch), default=0)}')
    for f, n in Counter(c['fonte'] for c in ch).items():
        print(f'     {n:3d}  {f}')
    print('\n== Imagens')
    print(f'   figuras: {rf[0]} na origem, {rf[1]} (re)gravadas, {rf[2]} removidas')
    print(f'   fotos:   {rt[0]} na origem, {rt[1]} (re)gravadas, {rt[2]} removidas; manifesto com {len(fotos)} entrada(s)')
    print(f'\n== version.json: {versao}')
    print(f'\n== Avisos ({len(avisos)})')
    for a in avisos:
        print('   - ' + a)


if __name__ == '__main__':
    main()
