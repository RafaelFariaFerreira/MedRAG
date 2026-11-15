#!/usr/bin/env python3
"""Gera a identidade visual do MedRAG: ícone do app, capa e diagramas do README.

uso: python3 tools/gerar_arte.py            (precisa de google-chrome e pillow)

Tudo é desenhado em SVG a partir dos mesmos tokens de cor e renderizado com
Chrome headless (Inter embutida), em versão clara e escura.
"""
import base64
import io
import math
import subprocess
import tempfile
from html import escape
from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parent.parent
DOCS = RAIZ / "docs" / "img"
APP = RAIZ / "app"
FONTES = APP / "assets" / "fonts"
FONT = "Inter, 'Segoe UI', Helvetica, Arial, sans-serif"

MARCA = "#1F4E46"      # primary do tema claro do app
DESTAQUE = "#E07A45"

TEMAS = {
    "light": dict(card="#F6F5F1", surface="#FFFFFF", ink="#171716", soft="#66645E", faint="#A3A099",
                  line="#E1DFD7", primary=MARCA, on_primary="#FFFFFF", tint="#E2EBE8", accent="#D2662F"),
    "dark": dict(card="#14181A", surface="#1D2224", ink="#ECEAE4", soft="#A9A59C", faint="#6F6D67",
                 line="#30363A", primary="#7FD1BE", on_primary="#0C2420", tint="#1D302C", accent="#F0A070"),
}


# ───────────────────────── primitivas SVG ─────────────────────────

def svg(w, h, corpo, titulo=""):
    t = f"<title>{escape(titulo)}</title>" if titulo else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
            f'font-family="{FONT}">{t}{corpo}</svg>')


def txt(x, y, s, size=12, weight=400, fill="#000", anchor="start", ls=0, halo=None):
    h = f' stroke="{halo}" stroke-width="6" stroke-linejoin="round" paint-order="stroke"' if halo else ""
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" font-weight="{weight}" fill="{fill}" '
            f'text-anchor="{anchor}" letter-spacing="{ls}"{h}>{escape(s)}</text>')


def rect(x, y, w, h, r, fill="none", stroke=None, sw=1.2):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"{s}/>'


def no(c, x, y, w, h, titulo, subs=(), tipo="normal"):
    """Caixa com título e linhas de apoio centralizados. Devolve o SVG."""
    if tipo == "primario":
        out = rect(x, y, w, h, 12, c["primary"])
        ct, cs = c["on_primary"], c["on_primary"]
        op = ' fill-opacity="0.78"'
    else:
        out = rect(x, y, w, h, 12, c["surface"], c["line"])
        ct, cs, op = c["ink"], c["soft"], ""
    bloco = 15 + (5 + 16 * len(subs) if subs else 0)
    topo = y + (h - bloco) / 2
    out += txt(x + w / 2, topo + 12.5, titulo, 14.5, 600, ct, "middle", -0.1)
    for i, s in enumerate(subs):
        out += txt(x + w / 2, topo + 15 + 5 + 11.5 + 16 * i, s, 12, 400, cs, "middle").replace("<text", f"<text{op}", 1)
    return out


def ponta(c, x, y, dx, dy, cor=None):
    px, py = -dy, dx
    a = (x - 6 * dx + 4 * px, y - 6 * dy + 4 * py)
    b = (x - 6 * dx - 4 * px, y - 6 * dy - 4 * py)
    return (f'<path d="M{a[0]:.1f} {a[1]:.1f} L{x:.1f} {y:.1f} L{b[0]:.1f} {b[1]:.1f}" fill="none" '
            f'stroke="{cor or c["faint"]}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>')


def seta_h(c, x1, y1, x2, y2, tracejada=False, cor=None):
    """Conector com tangentes horizontais (reta se y1 == y2)."""
    d = 1 if x2 > x1 else -1
    xm = (x1 + x2) / 2
    caminho = f"M{x1} {y1} L{x2} {y2}" if y1 == y2 else f"M{x1} {y1} C{xm} {y1} {xm} {y2} {x2} {y2}"
    dash = ' stroke-dasharray="4 4"' if tracejada else ""
    return (f'<path d="{caminho}" fill="none" stroke="{cor or c["faint"]}" stroke-width="1.5" '
            f'stroke-linecap="round"{dash}/>' + ponta(c, x2, y2, d, 0, cor))


def seta_v(c, x1, y1, x2, y2):
    """Conector com tangentes verticais (reta se x1 == x2)."""
    d = 1 if y2 > y1 else -1
    ym = (y1 + y2) / 2
    caminho = f"M{x1} {y1} L{x2} {y2}" if x1 == x2 else f"M{x1} {y1} C{x1} {ym} {x2} {ym} {x2} {y2}"
    return (f'<path d="{caminho}" fill="none" stroke="{c["faint"]}" stroke-width="1.5" stroke-linecap="round"/>'
            + ponta(c, x2, y2, 0, d))


def rotulo(c, x, y, s):
    return txt(x, y, s, 11, 600, c["soft"], ls=1.4)


# ───────────────────────── ícone ─────────────────────────

def glifo(anel="#FFFFFF", nucleo=DESTAQUE):
    """Lupa cuja lente é uma célula: anel (membrana) + núcleo. Desenhado na grade 1024."""
    return (f'<circle cx="468" cy="468" r="190" fill="none" stroke="{anel}" stroke-width="68"/>'
            f'<line x1="612" y1="612" x2="766" y2="766" stroke="{anel}" stroke-width="68" stroke-linecap="round"/>'
            f'<circle cx="496" cy="440" r="46" fill="{nucleo}"/>')


def icone_svg(raio=228, escala=1.0):
    g = f'<g transform="translate(512 512) scale({escala}) translate(-509 -509)">{glifo()}</g>'
    return svg(1024, 1024, rect(0, 0, 1024, 1024, raio, MARCA) + g, "MedRAG")


def icone_frente_svg():
    # camada de frente do adaptive icon: transparente, glifo na zona segura central (66%)
    return svg(1024, 1024, f'<g transform="translate(512 512) scale(0.6) translate(-509 -509)">{glifo()}</g>')


def icone_mini(x, y, lado):
    e = lado / 1024
    return (f'<g transform="translate({x} {y}) scale({e})">{rect(0, 0, 1024, 1024, 236, MARCA)}'
            f'<g transform="translate(512 512) translate(-509 -509)">{glifo()}</g></g>')


# ───────────────────────── capa ─────────────────────────

def capa(c):
    W, H = 1600, 640
    o = rect(0, 0, W, H, 32, c["card"])
    # bloco de título
    o += icone_mini(96, 92, 44)
    o += txt(154, 122, "MedRAG", 22, 600, c["ink"], ls=-0.3)
    o += txt(93, 292, "Do PDF da aula", 60, 700, c["ink"], ls=-2.2)
    o += txt(93, 364, "à resposta com fonte.", 60, 700, c["primary"], ls=-2.2)
    o += txt(96, 428, "Um copiloto de estudos com RAG", 22, 400, c["soft"], ls=-0.2)
    o += txt(96, 460, "para a prova de Anatomia Patológica.", 22, 400, c["soft"], ls=-0.2)
    o += txt(96, 548, "Flutter  ·  SQLite  ·  BM25 no aparelho  ·  Claude API", 14, 500, c["faint"], ls=0.3)

    # cartão do copiloto
    x, y, w, h = 936, 96, 568, 448
    o += rect(x, y, w, h, 24, c["surface"], c["line"])
    o += rect(x + w - 32 - 316, y + 32, 316, 46, 23, c["primary"])
    o += txt(x + w - 32 - 158, y + 61, "Achados do carcinoma papilífero?", 16, 500, c["on_primary"], "middle")

    def linha(yy, partes):
        t = f'<text x="{x + 32}" y="{yy}" font-size="18" fill="{c["ink"]}">'
        for s, cit in partes:
            t += (f'<tspan font-size="13" font-weight="700" fill="{c["accent"]}" dy="-6">{escape(s)}</tspan>'
                  f'<tspan dy="6"> </tspan>' if cit else f"<tspan>{escape(s)}</tspan>")
        return t + "</text>"

    o += linha(y + 134, [("Núcleos em “vidro fosco”, sulcos nucleares", False)])
    o += linha(y + 164, [("e pseudoinclusões", False), (" 1", True), ("; corpos psamomatosos", False), (" 2", True)])
    o += f'<line x1="{x + 32}" y1="{y + 204}" x2="{x + w - 32}" y2="{y + 204}" stroke="{c["line"]}" stroke-width="1.2"/>'
    o += txt(x + 32, y + 240, "FONTES", 11, 600, c["faint"], ls=1.6)
    cx = x + 32
    for n, s, lw in (("1", "Resumo · Tireoide", 178), ("2", "Prova 150 · Q7", 154)):
        o += rect(cx, y + 256, lw, 38, 19, "none", c["line"])
        o += txt(cx + 18, y + 280.5, n, 13, 700, c["accent"])
        o += txt(cx + 36, y + 280.5, s, 14, 500, c["soft"])
        cx += lw + 12
    # campo de pergunta
    o += rect(x + 32, y + h - 32 - 50, w - 64, 50, 25, c["card"])
    o += txt(x + 56, y + h - 32 - 19.5, "Pergunte ao material…", 15, 400, c["faint"])
    bx, by = x + w - 32 - 25, y + h - 32 - 25
    o += f'<circle cx="{bx}" cy="{by}" r="17" fill="{c["primary"]}"/>'
    o += (f'<path d="M{bx - 6} {by} L{bx + 6} {by} M{bx + 1.5} {by - 4.5} L{bx + 6} {by} L{bx + 1.5} {by + 4.5}" '
          f'fill="none" stroke="{c["on_primary"]}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>')
    return W, H, svg(W, H, o, "MedRAG — do PDF da aula à resposta com fonte")


# ───────────────────────── diagramas ─────────────────────────

def d_arquitetura(c):
    W, H = 1000, 548
    o = rect(0, 0, 560, H, 20, c["card"]) + rect(640, 0, 360, H, 20, c["card"])
    o += rotulo(c, 24, 33, "NO COMPUTADOR · PYTHON") + rotulo(c, 664, 33, "NO CELULAR · FLUTTER")
    w, h, xa, xb = 220, 60, 24, 316
    y1, y2, y3, y4, y5 = 56, 160, 264, 368, 472
    ca, cb, xf = xa + w / 2, xb + w / 2, 170
    # conectores primeiro, caixas por cima
    o += seta_v(c, ca, y1 + h, ca, y2) + seta_v(c, cb, y1 + h, cb, y2)
    o += seta_v(c, cb - 44, y1 + h, ca + 44, y2)
    o += seta_v(c, ca, y2 + h, xf + 70, y3) + seta_v(c, cb, y2 + h, xf + 150, y3)
    o += seta_v(c, xf + 70, y3 + h, ca, y4) + seta_v(c, xf + 150, y3 + h, cb, y4)
    o += seta_v(c, ca, y4 + h, ca, y5) + seta_v(c, cb, y4 + h, cb, y5)
    o += seta_h(c, 536, y5 + 26, 664, 86)
    o += no(c, xa, y1, w, h, "Resumo das aulas", ["PDF · 40 páginas"])
    o += no(c, xb, y1, w, h, "Provas antigas", ["PDF · 119 páginas"])
    o += no(c, xa, y2, w, h, "markitdown", ["texto por página"])
    o += no(c, xb, y2, w, h, "OCR multimodal", ["1 .md por página com imagem"])
    o += no(c, xf, y3, w, h, "Fusão texto + OCR", ["resumo.md · provas.md"])
    o += no(c, xa, y4, w, h, "Chunking estrutural", ["~700–1300 caracteres"])
    o += no(c, xb, y4, w, h, "Curadoria em JSON", ["capítulos · questões · flashcards"])
    o += no(c, xa, y5, 512, 52, "Conteúdo validado", ["validar.py  →  rag.json · material.json · questoes.json …"])
    # celular
    ys = [56, 158, 260, 362, 464]
    for a, b in zip(ys, ys[1:]):
        o += seta_v(c, 820, a + h, 820, b)
    itens = [("SQLite", "rag_chunks + progresso"), ("BM25", "índice em memória, sem rede"),
             ("Montagem do prompt", "tela + trechos + pergunta"), ("Claude API", "streaming SSE"),
             ("Resposta com fontes citadas", "em tempo real, no app")]
    for i, (t, s) in enumerate(itens):
        o += no(c, 664, ys[i], 312, h, t, [s], "primario" if i == 4 else "normal")
    return W, H, svg(W, H, o, "Visão geral da arquitetura")


def d_ingestao(c):
    W, H = 1000, 248
    o = rect(0, 0, W, H, 20, c["card"])
    w, g, h = 160, 36, 84
    xs = [28 + i * (w + g) for i in range(5)]
    ya, yb, ym = 28, 136, 82
    o += seta_h(c, xs[0] + w, ym + h / 2, xs[1], ya + h / 2) + seta_h(c, xs[0] + w, ym + h / 2, xs[1], yb + h / 2)
    o += seta_h(c, xs[1] + w, ya + h / 2, xs[2], ya + h / 2) + seta_h(c, xs[1] + w, yb + h / 2, xs[2], yb + h / 2)
    o += seta_h(c, xs[2] + w, ya + h / 2, xs[3], ym + h / 2) + seta_h(c, xs[2] + w, yb + h / 2, xs[3], ym + h / 2)
    o += seta_h(c, xs[3] + w, ym + h / 2, xs[4], ym + h / 2)
    o += no(c, xs[0], ym, w, h, "PDF original")
    o += no(c, xs[1], ya, w, h, "Camada de texto", ["markitdown (pdfminer)", "1 PDF por página"])
    o += no(c, xs[1], yb, w, h, "Camada de imagem", ["pdfimages · pdftoppm", "imagem + página inteira"])
    o += no(c, xs[2], ya, w, h, "Texto por página", ["\\f separa as páginas"])
    o += no(c, xs[2], yb, w, h, "OCR por página", ["ocr/notes/pag-PPP.md"])
    o += no(c, xs[3], ym, w, h, "montar_md()", ["une a página N ao", "OCR da página N"], "primario")
    o += no(c, xs[4], ym, w, h, "Markdown final", ["resumo.md · provas.md", "texto + OCR por página"])
    return W, H, svg(W, H, o, "Ingestão: de PDF e foto para Markdown")


def d_chunking(c):
    W, H = 1000, 264
    o = rect(0, 0, W, H, 20, c["card"])
    xs, w, wr, h, yc = [28, 206, 384, 562, 832], 140, 232, 84, 132
    yr = [28, 102, 176]
    o += seta_h(c, xs[0] + w, yc, xs[1], yc) + seta_h(c, xs[1] + w, yc, xs[2], yc)
    for y in yr:
        o += seta_h(c, xs[2] + w, yc, xs[3], y + 30) + seta_h(c, xs[3] + wr, y + 30, xs[4], yc)
    o += no(c, xs[0], yc - h / 2, w, h, "Markdown", ["resumo.md", "provas.md"])
    o += no(c, xs[1], yc - 50, w, 100, "Unidades", ["título · parágrafo", "lista · questão", "bloco de OCR"])
    o += no(c, xs[2], yc - h / 2, w, h, "empacotar()", ["700–1300 caracteres"], "primario")
    o += no(c, xs[3], yr[0], wr, 60, "Cabe (≤ 1300)", ["acrescenta ao chunk atual"])
    o += no(c, xs[3], yr[1], wr, 60, "Já tem ≥ 700 e vem título", ["fecha; o título abre o próximo"])
    o += no(c, xs[3], yr[2], wr, 60, "Unidade grande demais", ["corta por frases e sobrepõe 1"])
    o += no(c, xs[4], yc - h / 2, w, h, "rag.json", ["325 chunks", "com fonte e seção"])
    return W, H, svg(W, H, o, "Chunking estrutural")


def d_sequencia(c):
    W = 1000
    xs = [84, 250, 416, 582, 748, 914]
    nomes = ["Estudante", "Tela atual", "Copiloto", "BM25 local", "SQLite", "Claude API"]
    msgs = [(0, 2, "“Hiperplasia folicular × linfoma folicular?”", False),
            (1, 2, "contexto da tela", True),
            (2, 3, "buscar(pergunta, tela)", False),
            (3, 2, "até 7 chunks + fontes", True),
            (2, 4, "salva a mensagem", False),
            (2, 5, "system em cache + 12 trocas + tela + trechos + pergunta", False),
            (5, 2, "streaming SSE (text_delta…)", True),
            (2, 0, "resposta em tempo real, com as fontes citadas", True),
            (2, 4, "salva a resposta + fontes", False)]
    y0, passo = 118, 46
    H = y0 + passo * (len(msgs) - 1) + 44
    o = rect(0, 0, W, H, 20, c["card"])
    for x in xs:
        o += f'<line x1="{x}" y1="66" x2="{x}" y2="{H - 24}" stroke="{c["line"]}" stroke-width="1.2"/>'
    for i, (x, n) in enumerate(zip(xs, nomes)):
        dest = i == 2
        o += rect(x - 62, 28, 124, 38, 19, c["primary"] if dest else c["surface"], None if dest else c["line"])
        o += txt(x, 52, n, 13.5, 600, c["on_primary"] if dest else c["ink"], "middle")
    for i, (a, b, s, volta) in enumerate(msgs):
        y = y0 + passo * i
        d = 1 if xs[b] > xs[a] else -1
        o += seta_h(c, xs[a] + 10 * d, y, xs[b] - 2 * d, y, volta, c["soft"])
        o += txt((xs[a] + xs[b]) / 2, y - 9, s, 12.5, 500 if not volta else 400, c["ink"] if not volta else c["soft"],
                 "middle", halo=c["card"])
        o += f'<circle cx="{xs[a]}" cy="{y}" r="10" fill="{c["tint"]}"/>'
        o += txt(xs[a], y + 3.8, str(i + 1), 10.5, 700, c["primary"], "middle")
    return W, H, svg(W, H, o, "Do clique à resposta")


# ───────────────────────── renderização ─────────────────────────

def _css_fontes():
    pesos = {"Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700}
    css = ""
    for nome, peso in pesos.items():
        b64 = base64.b64encode((FONTES / f"Inter-{nome}.ttf").read_bytes()).decode()
        css += (f"@font-face{{font-family:Inter;font-weight:{peso};"
                f"src:url(data:font/ttf;base64,{b64}) format('truetype')}}")
    return css


CSS = None


def render(svg_str, w, h, escala=2):
    """Renderiza o SVG com Chrome headless e devolve uma imagem PIL (RGBA, fundo transparente)."""
    global CSS
    CSS = CSS or _css_fontes()
    with tempfile.TemporaryDirectory() as tmp:
        pag, png = Path(tmp) / "p.html", Path(tmp) / "o.png"
        pag.write_text(f"<html><head><meta charset='utf-8'><style>{CSS}html,body{{margin:0;background:transparent}}"
                       f"svg{{display:block}}</style></head><body>{svg_str}</body></html>", encoding="utf-8")
        subprocess.run(["google-chrome", "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
                        f"--force-device-scale-factor={escala}", "--default-background-color=00000000",
                        f"--user-data-dir={tmp}/prof", f"--window-size={w},{h}", "--virtual-time-budget=3000",
                        f"--screenshot={png}", f"file://{pag}"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        im = Image.open(io.BytesIO(png.read_bytes())).convert("RGBA")
    return im.crop((0, 0, w * escala, h * escala))


def salvar(im, caminho):
    caminho.parent.mkdir(parents=True, exist_ok=True)
    im.save(caminho, optimize=True)
    print("ok", caminho.relative_to(RAIZ), f"{im.width}x{im.height}")


def reduzir(im, lado):
    return im.resize((lado, lado), Image.LANCZOS)


def main():
    # ── ícone ──
    marca = APP / "assets" / "branding"
    (marca / "icon.svg").write_text(icone_svg() + "\n", encoding="utf-8")
    (marca / "icon_foreground.svg").write_text(icone_frente_svg() + "\n", encoding="utf-8")
    cheio = render(icone_svg(), 1024, 1024, 1)
    frente = render(icone_frente_svg(), 1024, 1024, 1)
    mascara = render(icone_svg(raio=0, escala=0.74), 1024, 1024, 1).convert("RGB")
    res = APP / "android" / "app" / "src" / "main" / "res"
    for dens, lado in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        salvar(reduzir(cheio, lado), res / f"mipmap-{dens}" / "ic_launcher.png")
        salvar(reduzir(frente, lado * 9 // 4), res / f"mipmap-{dens}" / "ic_launcher_foreground.png")
    web = APP / "web"
    salvar(reduzir(cheio, 64), web / "favicon.png")
    for lado in (192, 512):
        salvar(reduzir(cheio, lado), web / "icons" / f"Icon-{lado}.png")
        salvar(reduzir(mascara, lado), web / "icons" / f"Icon-maskable-{lado}.png")
    salvar(reduzir(cheio, 512), DOCS / "icon.png")

    # ── capa e diagramas (claro + escuro) ──
    pecas = {"cover": capa, "arquitetura": d_arquitetura, "ingestao": d_ingestao,
             "chunking": d_chunking, "sequencia": d_sequencia}
    for nome, fn in pecas.items():
        for tema, c in TEMAS.items():
            w, h, s = fn(c)
            if nome == "cover" and tema == "light":
                (DOCS / "cover.svg").write_text(s + "\n", encoding="utf-8")
            salvar(render(s, w, h, 2), DOCS / (f"{nome}.png" if tema == "light" else f"{nome}-dark.png"))


if __name__ == "__main__":
    main()
