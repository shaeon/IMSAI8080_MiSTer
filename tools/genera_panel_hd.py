#!/usr/bin/env python3
# Redibuja el panel del IMSAI al doble de resolucion (1600x560) para el modo HD.
#
# Entrada: la imagen del panel de la Calypso (IMSAI8080.ROM, 800x280 a 4 bits).
# Salida:  una imagen 1600x560 en modo P con la misma paleta de 16 colores (para genera_hd.py
#          --png) y, si se pide, la misma en RGB antes de pasarla a la paleta.
#
#   - Lo que son rectangulos alineados (lineas, marcos, corchetes) se escala sin mas.
#   - Los LEDs, las palancas de los interruptores y los LEDs de disco se vuelven a dibujar con
#     suavizado en las mismas posiciones.
#   - Los textos se vuelven a escribir con DejaVu Sans / Liberation Sans, ajustando cada uno a la
#     caja que ocupa en el original.
#
# Uso: python3 tools/genera_panel_hd.py IMSAI8080.ROM panel_hd.png [vista_previa.png]
import os, sys, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 800, 280
PALETA = [(0x0, 0x0, 0x0), (0x0, 0x0, 0x1), (0x1, 0x1, 0x0), (0x4, 0x0, 0x0), (0x3, 0xa, 0xa),
          (0x6, 0x0, 0x0), (0xb, 0x0, 0x0), (0x2, 0x2, 0x2), (0x4, 0x5, 0x4), (0x7, 0x7, 0x7),
          (0x8, 0x8, 0x8), (0x9, 0x9, 0x9), (0xa, 0xa, 0xa), (0xa, 0xb, 0xa), (0xb, 0xc, 0xb),
          (0xf, 0xf, 0xf)]
RGB = [tuple(c * 17 for c in p) for p in PALETA]
GRIS = {7, 9, 10, 11, 12, 13, 14, 15}           # texto y lineas blancas
SUAVE = {1, 2, 8}                               # suavizado del texto (oscuro)
FUENTES = {
    'sans':  '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf',
    'logo':  '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    'drive': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    'disk':  '/usr/share/fonts/truetype/liberation/LiberationSans-BoldItalic.ttf',
}

# --- textos: (cadena, region x0, y0, x1, y1 en el original, fuente) ------------------------------
# Solo cuentan los trazos que caen enteros dentro de la region (asi quedan fuera las lineas).
TEXTOS = [
    ('I', (468, 0, 480, 44), 'logo'), ('M', (482, 0, 523, 44), 'logo'),
    ('S', (524, 0, 557, 45), 'logo'), ('A', (558, 0, 595, 44), 'logo'),
    ('I', (596, 0, 606, 44), 'logo'),
    ('8', (637, 0, 666, 45), 'logo'), ('0', (667, 0, 694, 45), 'logo'),
    ('8', (695, 0, 723, 45), 'logo'), ('0', (724, 0, 753, 45), 'logo'),
    ('MICROCOMPUTER', (659, 44, 726, 53), 'sans'), ('SYSTEM', (727, 44, 755, 53), 'sans'),
    ('PROGRAMMED', (270, 32, 327, 41), 'sans'), ('OUTPUT', (270, 41, 303, 51), 'sans'),
    ('MEMR', (35, 72, 60, 82), 'sans'), ('INP', (66, 72, 82, 82), 'sans'),
    ('M1', (98, 72, 110, 82), 'sans'), ('OUT', (127, 72, 146, 82), 'sans'),
    ('HLTA', (157, 72, 178, 82), 'sans'), ('STACK', (186, 72, 211, 82), 'sans'),
    ('WO', (219, 74, 235, 83), 'sans'), ('INTA', (248, 72, 268, 82), 'sans'),
    ('STATUS', (271, 84, 300, 94), 'sans'), ('BYTE', (271, 94, 292, 103), 'sans'),
    ('DATA', (547, 82, 568, 91), 'sans'), ('BUS', (547, 91, 564, 101), 'sans'),
    ('HEXADECIMAL', (547, 109, 603, 118), 'sans'), ('OCTAL', (547, 122, 574, 131), 'sans'),
    ('INTERRUPTS', (639, 117, 674, 123), 'sans'), ('ENABLED', (643, 123, 670, 131), 'sans'),
    ('RUN', (681, 121, 695, 129), 'sans'), ('WAIT', (706, 122, 721, 129), 'sans'),
    ('HOLD', (734, 122, 752, 130), 'sans'),
    ('ADDRESS', (268, 133, 306, 143), 'sans'), ('BUS', (268, 143, 306, 155), 'sans'),
    ('ADDRESS', (546, 134, 583, 143), 'sans'), ('BUS', (547, 143, 564, 153), 'sans'),
    ('EXAMINE', (580, 159, 609, 167), 'sans'), ('DEPOSIT', (611, 159, 639, 167), 'sans'),
    ('RESET', (642, 158, 670, 168), 'sans'), ('RUN', (673, 158, 697, 168), 'sans'),
    ('SINGLE', (700, 154, 729, 163), 'sans'), ('STEP', (700, 163, 729, 169), 'sans'),
    ('PWR ON', (730, 158, 761, 168), 'sans'),
    ('EXAMINE', (580, 172, 609, 180), 'sans'), ('NEXT', (586, 179, 604, 187), 'sans'),
    ('DEPOSIT', (611, 172, 639, 180), 'sans'), ('NEXT', (616, 179, 634, 187), 'sans'),
    ('EXT CLR', (643, 175, 668, 183), 'sans'), ('STOP', (675, 175, 693, 183), 'sans'),
    ('SINGLE', (703, 172, 726, 181), 'sans'), ('STEP', (706, 180, 723, 188), 'sans'),
    ('PWR OFF', (731, 176, 760, 184), 'sans'),
    ('ADDRESS - DATA', (401, 175, 451, 183), 'sans'),
    ('ADDRESS - PROGRAMMED INPUT', (104, 178, 201, 186), 'sans'),
    ('I', (25, 237, 33, 274), 'logo'), ('M', (35, 237, 70, 274), 'logo'),
    ('SA', (72, 236, 131, 275), 'logo'), ('I', (133, 237, 140, 274), 'logo'),
    ('FLOPPY', (171, 254, 243, 272), 'disk'), ('DISK', (244, 254, 290, 272), 'disk'),
    ('DRIVE 1', (576, 234, 618, 245), 'drive'), ('DRIVE 0', (670, 234, 717, 246), 'drive'),
    ('TRACK 00', (402, 249, 438, 258), 'sans'), ('WRITE', (496, 249, 522, 258), 'sans'),
    ('READY', (592, 248, 619, 257), 'sans'), ('READY', (687, 248, 713, 257), 'sans'),
    ('HEAD LOADED', (384, 264, 438, 273), 'sans'), ('WRITE ENABLED', (498, 264, 559, 273), 'sans'),
    ('SELECTED', (581, 263, 619, 273), 'sans'), ('SELECTED', (676, 264, 714, 273), 'sans'),
]

def lee_rom(path):
    d = open(path, 'rb').read()
    assert len(d) == W * H // 2
    return [[(d[y * 400 + x // 2] >> 4) if x % 2 == 0 else d[y * 400 + x // 2] & 15
             for x in range(W)] for y in range(H)]

def componentes(P, clase, excluir=None):
    """Componentes conexas (8 vecinos) de los puntos cuyo indice esta en 'clase'."""
    vis = [[False] * W for _ in range(H)]
    comps = []
    for y in range(H):
        for x in range(W):
            if P[y][x] in clase and not vis[y][x] and not (excluir and excluir[y][x]):
                pila, pts = [(x, y)], []
                vis[y][x] = True
                while pila:
                    a, b = pila.pop()
                    pts.append((a, b))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            u, v = a + dx, b + dy
                            if 0 <= u < W and 0 <= v < H and not vis[v][u] and P[v][u] in clase \
                                    and not (excluir and excluir[v][u]):
                                vis[v][u] = True
                                pila.append((u, v))
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                comps.append({'pts': pts, 'box': (min(xs), min(ys), max(xs), max(ys))})
    return comps

def mascara_lineas(P):
    """Puntos de lineas rectas: tramos de 12 o mas puntos del mismo color, en horizontal o vertical."""
    m = [[False] * W for _ in range(H)]
    for y in range(H):
        x = 0
        while x < W:
            x1 = x
            while x1 < W and P[y][x1] == P[y][x]:
                x1 += 1
            if P[y][x] in GRIS | SUAVE and x1 - x >= 12:
                for k in range(x, x1):
                    m[y][k] = True
            x = x1
    for x in range(W):
        y = 0
        while y < H:
            y1 = y
            while y1 < H and P[y1][x] == P[y][x]:
                y1 += 1
            if P[y][x] in GRIS | SUAVE and y1 - y >= 12:
                for k in range(y, y1):
                    m[k][x] = True
            y = y1
    return m

LINEAS = None

def con_suavizado(P, pts):
    """Los puntos y sus vecinos de colores de suavizado (que no son texto por si solos)."""
    conj = set(pts)
    for a, b in pts:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                u, v = a + dx, b + dy
                if 0 <= u < W and 0 <= v < H and P[v][u] in SUAVE and not LINEAS[v][u]:
                    conj.add((u, v))
    return conj

def caja(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)

def dentro(box, reg):
    return box[0] >= reg[0] and box[1] >= reg[1] and box[2] <= reg[2] and box[3] <= reg[3]

def mascara_texto(cadena, fuente, ancho, alto):
    """Texto blanco sobre negro ajustado exactamente a ancho x alto (escala de grises)."""
    f = ImageFont.truetype(FUENTES[fuente], 160)
    bb = f.getbbox(cadena)
    im = Image.new('L', (bb[2] - bb[0] + 20, bb[3] - bb[1] + 20), 0)
    ImageDraw.Draw(im).text((10 - bb[0], 10 - bb[1]), cadena, font=f, fill=255)
    im = im.crop(im.getbbox())
    if ancho is None:
        ancho = max(1, round(im.size[0] * alto / im.size[1]))
    return im.resize((ancho, alto), Image.LANCZOS)

def main():
    if len(sys.argv) < 3:
        sys.exit("uso: genera_panel_hd.py IMSAI8080.ROM panel_hd.png [vista_previa.png]")
    P = lee_rom(sys.argv[1])
    base = [row[:] for row in P]

    # --- textos: se buscan sus trazos y se borran de la base ---------------------------------
    # Los textos pequenos se buscan sin las lineas rectas (algunos tocan un marco); los grandes
    # (logotipo, DRIVE, FLOPPY DISK) tienen trazos largos y se buscan con todo.
    global LINEAS
    LINEAS = mascara_lineas(P)
    grises = componentes(P, GRIS, LINEAS)
    grandes = componentes(P, GRIS)
    textos = []
    for cadena, reg, fuente in TEXTOS:
        conj = grises if fuente == 'sans' else grandes
        cs = [c for c in conj if dentro(c['box'], reg)]
        if not cs:
            sys.exit("no hay trazos para '%s' en %s" % (cadena, reg))
        pts = con_suavizado(P, [p for c in cs for p in c['pts']])
        pts = [(a, b) for a, b in pts if reg[0] <= a <= reg[2] and reg[1] <= b <= reg[3]]
        if fuente != 'sans':
            # los grandes: fuera todo lo que no sea negro dentro de la region
            for b in range(reg[1], reg[3] + 1):
                for a in range(reg[0], reg[2] + 1):
                    base[b][a] = 0
        for a, b in pts:
            base[b][a] = 0
        for c in cs:
            conj.remove(c)
        textos.append((cadena, caja(pts), fuente))
        if os.environ.get('DEPURA') == cadena:
            print(cadena, reg, caja(pts), [c['box'] for c in cs])

    # numeros de los LEDs e interruptores: trazos pequenos en sus filas, agrupados por el LED
    # (o interruptor) mas cercano; asi se juntan los trozos de un mismo numero
    IZQ = [45, 75, 106, 136, 167, 197, 228, 258]
    DER = [319, 349, 380, 410, 441, 471, 502, 532]
    filas = ((54, 62, IZQ, list('76543210')), (71, 79, DER, list('76543210')),
             (108, 117, IZQ + DER, list('8421842184218421')),
             (123, 131, IZQ + DER, list('2142142121421421')),
             (158, 167, IZQ + DER, ['15', '14', '13', '12', '11', '10', '9', '8',
                                    '7', '6', '5', '4', '3', '2', '1', '0']),
             (170, 178, IZQ, list('76543210')))
    numeros = []
    for y0, y1, centros, cads in filas:
        grupos = {cx: [] for cx in centros}
        for c in [c for c in grises if c['box'][1] >= y0 and c['box'][3] <= y1 and
                  c['box'][2] - c['box'][0] <= 8 and c['box'][3] - c['box'][1] <= 6]:
            m = (c['box'][0] + c['box'][2]) / 2
            cx = min(centros, key=lambda k: abs(k - m))
            if abs(cx - m) <= 7:
                grupos[cx].append(c)
        for cx, cad in zip(centros, cads):
            g = grupos[cx]
            if not g:
                sys.exit("fila %d: falta el numero '%s' en x=%d" % (y0, cad, cx))
            pts = con_suavizado(P, [p for c in g for p in c['pts']])
            for a, b in pts:
                base[b][a] = 0
            for c in g:
                grises.remove(c)
            numeros.append((cad, caja(pts), y0))

    # misma altura para todos los numeros de una fila, ancho natural, centrados en su sitio
    for y0 in set(n[2] for n in numeros):
        fila = [n for n in numeros if n[2] == y0]
        alto = sorted(b[3] - b[1] + 1 for _, b, _ in fila)[len(fila) // 2]
        arriba = sorted(b[1] for _, b, _ in fila)[len(fila) // 2]
        for cad, b, _ in fila:
            textos.append((cad, ('centro', (b[0] + b[2] + 1) / 2, arriba, alto), 'sans'))

    # --- LEDs, palancas y LEDs de disco -------------------------------------------------------
    leds = [c for c in componentes(P, {3}) if c['box'][1] < 160 and len(c['pts']) > 100]
    disco = [c for c in componentes(P, {3}) if c['box'][1] >= 240 and len(c['pts']) > 50]
    palancas = [c for c in componentes(P, {4, 6}) if len(c['pts']) > 200]
    for c in leds + disco + palancas:
        for a, b in c['pts']:
            base[b][a] = 0
    # bordes oscuros de las palancas (indices 3 y 5 alrededor)
    for c in palancas:
        x0, y0, x1, y1 = c['box']
        for b in range(y0 - 2, y1 + 3):
            for a in range(x0 - 2, x1 + 3):
                if base[b][a] in (3, 5):
                    base[b][a] = 0
    # el suavizado de los bordes de LEDs y palancas (indices 2, 5, 8 junto a ellos) tambien fuera
    for y in range(H):
        for x in range(W):
            if base[y][x] in (2, 5) and y < 232:
                base[y][x] = 0

    # --- lienzo 1600x560 ----------------------------------------------------------------------
    S = 4                                       # sobremuestreo para el suavizado
    lienzo = Image.new('RGB', (1600, 560))
    px = lienzo.load()
    for y in range(H):
        for x in range(W):
            c = RGB[base[y][x]]
            if c != (0, 0, 0):
                for dy in (0, 1):
                    for dx in (0, 1):
                        px[2 * x + dx, 2 * y + dy] = c

    # formas suavizadas: se dibujan a 4x y se reducen
    capa = Image.new('RGB', (1600 * S, 560 * S))
    alfa = Image.new('L', (1600 * S, 560 * S), 0)
    dc = ImageDraw.Draw(capa)
    da = ImageDraw.Draw(alfa)
    for c in leds:
        n = len(c['pts'])
        cx = sum(p[0] for p in c['pts']) / n + 0.5
        cy = sum(p[1] for p in c['pts']) / n + 0.5
        r = math.sqrt(n / math.pi)
        rect = ((cx - r) * 2 * S, (cy - r) * 2 * S, (cx + r) * 2 * S, (cy + r) * 2 * S)
        dc.ellipse(rect, fill=RGB[3]); da.ellipse(rect, fill=255)
    for c in palancas + disco:
        x0, y0, x1, y1 = c['box']
        color = RGB[3] if c in disco else RGB[base_color(P, c)]
        radio = 1.5 if c in disco else 4
        rect = (x0 * 2 * S, y0 * 2 * S, (x1 + 1) * 2 * S - 1, (y1 + 1) * 2 * S - 1)
        dc.rounded_rectangle(rect, radius=radio * 2 * S, fill=color)
        da.rounded_rectangle(rect, radius=radio * 2 * S, fill=255)
    capa = capa.resize((1600, 560), Image.LANCZOS)
    alfa = alfa.resize((1600, 560), Image.LANCZOS)
    lienzo = Image.composite(capa, lienzo, alfa)

    # textos
    for cadena, b, fuente in textos:
        if b[0] == 'centro':
            _, cx, y0, alto = b
            m = mascara_texto(cadena, fuente, None, alto * 2)
            lienzo.paste((255, 255, 255), (int(round(cx * 2 - m.size[0] / 2)), y0 * 2), m)
        else:
            x0, y0, x1, y1 = b
            m = mascara_texto(cadena, fuente, (x1 - x0 + 1) * 2, (y1 - y0 + 1) * 2)
            lienzo.paste((255, 255, 255), (x0 * 2, y0 * 2), m)

    if len(sys.argv) > 3:
        lienzo.save(sys.argv[3])

    # --- paleta -------------------------------------------------------------------------------
    pr = lienzo.load()
    out = Image.new('P', (1600, 560))
    out.putpalette([v for c in RGB for v in c] + [0] * (768 - 48))
    po = out.load()
    cache = {}
    for y in range(560):
        for x in range(1600):
            c = pr[x, y]
            if c not in cache:
                cache[c] = cuantiza(*c)
            po[x, y] = cache[c]
    out.save(sys.argv[2])

def base_color(P, c):
    from collections import Counter
    return Counter(P[b][a] for a, b in c['pts']).most_common(1)[0][0]

def cuantiza(r, g, b):
    # casi negro -> fondo (indice 0): las barras de los interruptores se pintan donde el punto no
    # es 0, y un resto oscuro alrededor de las palancas las alargaria fuera de ellas
    if max(r, g, b) < 0x18:
        return 0
    # grises (texto): solo la escala neutra; el resto, el color de la paleta mas cercano
    if abs(r - g) < 12 and abs(g - b) < 12 and r > 20:
        cand = (0, 7, 9, 10, 11, 12, 15)
    else:
        cand = range(16)
    mejor, dmin = 0, 1e9
    for i in cand:
        R, G, B = RGB[i]
        d = 0.3 * (r - R) ** 2 + 0.59 * (g - G) ** 2 + 0.11 * (b - B) ** 2
        if d < dmin:
            mejor, dmin = i, d
    return mejor

if __name__ == '__main__':
    main()
