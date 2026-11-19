#!/usr/bin/env python3
# Genera los datos del renderizador HD (rtl/hd_video.sv):
#
#   rtl/init/hd_map.hex     el panel HD es una imagen de 1600x560 a 4 bits (paleta de panel.sv)
#   rtl/init/hd_tiles.hex   guardada como teselas de 8x8: un mapa de 200x70 con el numero de
#   rtl/init/hd_params.vh   tesela y las teselas distintas (8 palabras de 32 bits cada una).
#                           Entera serian 3,6 Mbit; asi, la mitad o menos (casi todo es negro).
#   rtl/init/hd_col.hex     por columna del panel original (0-799, la del HD / 2) a que LED(s) / interruptor / LED de disco pertenece:
#                           [23] [22:18] LED A, [17] [16:12] LED B, [11] [10:6] interruptor (0-15
#                           normales, 16-20 momentaneos), [5] [4:3] LED de disco.
#   (hd_row.hex: [7] [6:5] fila de LEDs, [4] [3] fila de LEDs de disco, [2] barra arriba,
#    [1] barra abajo, [0] barra en reposo de los momentaneos)
#   rtl/init/hd_row.hex     por fila del panel original (0-279) lo mismo.
#   rtl/init/hd_led.hex     (fila de LEDs, columna de LEDs) -> bit de 'leds' en panel.sv.
#
# Las tablas salen de las constantes de panel.sv (copiadas abajo) y reproducen exactamente sus
# comparaciones (col > c && col < c + ancho...), que el renderizador HD hace con la fila / 2.
#
# Uso:
#   python3 tools/genera_hd.py --rom IMSAI8080.ROM        panel original con cada punto 2x2
#   python3 tools/genera_hd.py --png panel_hd.png         imagen 1600x560 en modo P (16 colores)
import argparse, os, sys

# --- constantes de rtl/imsai8080/panel/panel.sv -------------------------------------------------
LED_COLS = [37, 68, 99, 130, 161, 191, 222, 253, 313, 344, 375, 405, 436, 467, 497, 528,
            654, 683, 711, 739]
LED_ROWS = [35, 86, 137]
LED_INDEX_COLS = [19, 18, 17, 16,
                  15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
                  15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
                  7, 6, 5, 4, 3, 2, 1, 0]
LED_INDEX_ROWS = [2] * 20 + [1] * 16 + [0] * 8
SWITCH_COLS = [521, 490, 459, 429, 399, 369, 338, 307, 246, 215, 184, 154, 125, 94, 63, 32]
M_SWITCH_COLS = [583, 615, 644, 673, 703]
DISK_LED_COLS = [445, 472, 624, 719]
DISK_LED_ROWS = [248, 264]
DISK_LED_INDEX_COLS = [0, 0, 1, 1, 2, 2, 3, 3]
DISK_LED_INDEX_ROWS = [0, 1, 0, 1, 0, 1, 0, 1]
LED_WIDTH, LED_HEIGHT = 32, 16
DISK_LED_WIDTH, DISK_LED_HEIGHT = 26, 10
SWITCH_ROW_ON, SWITCH_ROW_OFF, M_SWITCH_ROW_IDLE = 198, 220, 210
SWITCH_NOTCH_HEIGHT, SWITCH_WIDTH = 4, 23
PALETTE = [(0x0, 0x0, 0x0), (0x0, 0x0, 0x1), (0x1, 0x1, 0x0), (0x4, 0x0, 0x0), (0x3, 0xa, 0xa),
           (0x6, 0x0, 0x0), (0xb, 0x0, 0x0), (0x2, 0x2, 0x2), (0x4, 0x5, 0x4), (0x7, 0x7, 0x7),
           (0x8, 0x8, 0x8), (0x9, 0x9, 0x9), (0xa, 0xa, 0xa), (0xa, 0xb, 0xa), (0xb, 0xc, 0xb),
           (0xf, 0xf, 0xf)]

W, H_SD, H_HD = 800, 280, 560
WP = 1600                               # ancho del panel HD

# En panel.sv la imagen sale 8 puntos a la derecha de 'col' (la palabra de 8 puntos se carga un
# grupo antes), y todas las zonas estan en columnas de 'col'. El renderizador HD indexa las tablas
# con la columna de la imagen, asi que aqui se restan esos 8 puntos.
RETRASO = 8

def dentro(v, ini, ancho):
    return v > ini and v < ini + ancho

def centros_leds(panel):
    """Centros (en columnas de 800) de los 20 LEDs de la fila de abajo, de izquierda a derecha."""
    linea = panel[(LED_ROWS[2] + 8) * 2]
    centros, ini = [], None
    for x in range(WP + 1):
        es = x < WP and linea[x] == 3
        if es and ini is None:
            ini = x
        if not es and ini is not None:
            centros.append((ini + x - 1) / 4)
            ini = None
    if len(centros) != len(LED_COLS):
        sys.exit("se esperaban %d LEDs en la fila de abajo y hay %d" % (len(LED_COLS), len(centros)))
    return centros

def tablas(panel):
    # LEDs: en vez de las zonas de panel.sv (que en algunas columnas cogen un trozo del LED de al
    # lado) se usa una zona de 27 puntos centrada en cada LED del dibujo
    centros = centros_leds(panel)
    col = []
    for xi in range(W):
        v = 0
        x = xi + RETRASO                    # columna en 'col' de panel.sv
        leds = [i for i, c in enumerate(centros) if abs(xi - c) <= 13]
        assert len(leds) <= 2
        if len(leds) > 0:                   # algunas columnas son de dos LEDs a la vez
            v |= 1 << 23 | leds[0] << 18
        if len(leds) > 1:
            v |= 1 << 17 | leds[1] << 12
        sw = [i for i, c in enumerate(SWITCH_COLS + M_SWITCH_COLS) if dentro(x, c + 8, SWITCH_WIDTH)]
        assert len(sw) <= 1
        if sw:
            v |= 1 << 11 | sw[0] << 6
        # LEDs de disco: un punto mas por cada lado que en panel.sv (los rectangulos redibujados
        # ocupan el borde que alli se quedaba sin encender)
        dk = [i for i, c in enumerate(DISK_LED_COLS) if dentro(x, c - 1, DISK_LED_WIDTH + 2)]
        assert len(dk) <= 1
        if dk:
            v |= 1 << 5 | dk[0] << 3
        col.append(v)
    fila = []
    for y in range(H_SD):
        v = 0
        for i, r in enumerate(LED_ROWS):
            # una fila mas arriba que en panel.sv: el LED redibujado empieza en la fila r
            if dentro(y, r - 1, LED_HEIGHT + 1):
                v |= 1 << 7 | i << 5
        for i, r in enumerate(DISK_LED_ROWS):
            if dentro(y, r - 1, DISK_LED_HEIGHT + 2):
                v |= 1 << 4 | i << 3
        if dentro(y, SWITCH_ROW_ON, SWITCH_NOTCH_HEIGHT):
            v |= 1 << 2
        if dentro(y, SWITCH_ROW_OFF, SWITCH_NOTCH_HEIGHT):
            v |= 1 << 1
        if dentro(y, M_SWITCH_ROW_IDLE, SWITCH_NOTCH_HEIGHT):
            v |= 1 << 0
        fila.append(v)
    led = [0] * 128                     # {fila(2), columna(5)} -> {valido, bit(6)}
    for bit in range(len(LED_INDEX_COLS)):
        led[LED_INDEX_ROWS[bit] << 5 | LED_INDEX_COLS[bit]] = 1 << 6 | bit
    # comprobacion: los LEDs de disco van por {fila, columna} -> indice 0-7
    for i in range(8):
        assert DISK_LED_INDEX_COLS[i] * 2 + DISK_LED_INDEX_ROWS[i] == i
    return col, fila, led

def panel_desde_rom(path):
    """Panel original con cada punto como 2x2 (matriz 560 x 1600 de indices de paleta)."""
    d = open(path, 'rb').read()
    if len(d) != W * H_SD // 2:
        sys.exit("%s: se esperaban %d bytes" % (path, W * H_SD // 2))
    panel = []
    for y in range(H_SD):
        l = []
        for x in range(W):
            b = d[y * 400 + x // 2]
            v = (b >> 4) if x % 2 == 0 else b & 15
            l += [v, v]
        panel += [l, list(l)]
    return panel

def panel_desde_png(path):
    from PIL import Image
    im = Image.open(path)
    if im.size != (WP, H_HD) or im.mode != 'P':
        sys.exit("%s: hace falta una imagen 1600x560 en modo P" % path)
    px = im.load()
    panel = [[px[x, y] for x in range(WP)] for y in range(H_HD)]
    if max(max(l) for l in panel) > 15:
        sys.exit("%s: hay colores de paleta > 15" % path)
    return panel

def teselas(panel):
    """Trocea el panel en teselas de 8x8 sin repetir. Devuelve (mapa de 200x70, lista de teselas);
    cada tesela son 8 palabras de 32 bits (una por linea), el punto k en los bits [4k+3:4k]."""
    indice, lista, mapa = {}, [], []
    for ty in range(H_HD // 8):
        for tx in range(WP // 8):
            t = tuple(sum(panel[ty * 8 + l][tx * 8 + k] << (4 * k) for k in range(8)) for l in range(8))
            if t not in indice:
                indice[t] = len(lista)
                lista.append(t)
            mapa.append(indice[t])
    return mapa, lista

def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--rom')
    g.add_argument('--png')
    a = ap.parse_args()
    panel = panel_desde_rom(a.rom) if a.rom else panel_desde_png(a.png)

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'rtl', 'init')
    mapa, lista = teselas(panel)
    if len(lista) > 8192:
        sys.exit("demasiadas teselas distintas: %d" % len(lista))
    with open(os.path.join(out, 'hd_map.hex'), 'w') as f:
        f.write('\n'.join('%04x' % v for v in mapa) + '\n')
    with open(os.path.join(out, 'hd_tiles.hex'), 'w') as f:
        f.write('\n'.join('%08x' % w for t in lista for w in t) + '\n')
    with open(os.path.join(out, 'hd_params.vh'), 'w') as f:
        f.write("// Generado por tools/genera_hd.py\nlocalparam HD_TILES = %d;\n" % len(lista))
    print("%d teselas distintas de %d" % (len(lista), len(mapa)))
    col, fila, led = tablas(panel)
    for nombre, datos, digitos in (('hd_col.hex', col, 6), ('hd_row.hex', fila, 2), ('hd_led.hex', led, 2)):
        with open(os.path.join(out, nombre), 'w') as f:
            f.write('\n'.join('%0*x' % (digitos, v) for v in datos) + '\n')

if __name__ == '__main__':
    main()
