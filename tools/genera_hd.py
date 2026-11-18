#!/usr/bin/env python3
# Genera los datos del renderizador HD (rtl/hd_video.sv):
#
#   rtl/init/panel_hd.hex   imagen del panel de 800x560 a 4 bits (paleta de panel.sv), 100 palabras
#                           de 32 bits por linea, 8 puntos por palabra empaquetados como en la
#                           Calypso (el byte n tiene los puntos 2n y 2n+1, el primero en el nibble
#                           alto).
#   rtl/init/hd_col.hex     por columna (0-799) a que LED(s) / interruptor / LED de disco pertenece:
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
#   python3 tools/genera_hd.py --rom IMSAI8080.ROM        panel original con las lineas dobladas
#   python3 tools/genera_hd.py --png panel_hd.png         imagen 800x560 en modo P (16 colores)
import argparse, os, sys

# --- constantes de rtl/imsai8080/panel/panel.sv -------------------------------------------------
LED_COLS = [29, 59, 90, 120, 151, 181, 212, 242, 303, 333, 364, 394, 425, 455, 486, 516,
            642, 670, 698, 726]     # corregidas en panel.sv (centro del LED - 16)
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

def dentro(v, ini, ancho):
    return v > ini and v < ini + ancho

def tablas():
    col = []
    for x in range(W):
        v = 0
        leds = [i for i, c in enumerate(LED_COLS) if dentro(x, c, LED_WIDTH)]
        assert len(leds) <= 2
        if len(leds) > 0:                   # algunas columnas son de dos LEDs a la vez
            v |= 1 << 23 | leds[0] << 18
        if len(leds) > 1:
            v |= 1 << 17 | leds[1] << 12
        sw = [i for i, c in enumerate(SWITCH_COLS + M_SWITCH_COLS) if dentro(x, c + 8, SWITCH_WIDTH)]
        assert len(sw) <= 1
        if sw:
            v |= 1 << 11 | sw[0] << 6
        dk = [i for i, c in enumerate(DISK_LED_COLS) if dentro(x, c, DISK_LED_WIDTH)]
        assert len(dk) <= 1
        if dk:
            v |= 1 << 5 | dk[0] << 3
        col.append(v)
    fila = []
    for y in range(H_SD):
        v = 0
        for i, r in enumerate(LED_ROWS):
            if dentro(y, r, LED_HEIGHT):
                v |= 1 << 7 | i << 5
        for i, r in enumerate(DISK_LED_ROWS):
            if dentro(y, r, DISK_LED_HEIGHT):
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
    d = open(path, 'rb').read()
    if len(d) != W * H_SD // 2:
        sys.exit("%s: se esperaban %d bytes" % (path, W * H_SD // 2))
    lineas = []
    for y in range(H_SD):
        l = d[y * 400:(y + 1) * 400]
        lineas += [l, l]
    return b''.join(lineas)

def panel_desde_png(path):
    from PIL import Image
    im = Image.open(path)
    if im.size != (W, H_HD) or im.mode != 'P':
        sys.exit("%s: hace falta una imagen 800x560 en modo P" % path)
    px = im.load()
    out = bytearray()
    for y in range(H_HD):
        for x in range(0, W, 2):
            a, b = px[x, y], px[x + 1, y]
            if a > 15 or b > 15:
                sys.exit("%s: color de paleta > 15 en (%d,%d)" % (path, x, y))
            out.append(a << 4 | b)
    return bytes(out)

def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--rom')
    g.add_argument('--png')
    a = ap.parse_args()
    panel = panel_desde_rom(a.rom) if a.rom else panel_desde_png(a.png)

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'rtl', 'init')
    with open(os.path.join(out, 'panel_hd.hex'), 'w') as f:
        for i in range(0, len(panel), 4):
            b = panel[i:i + 4]
            f.write('%08x\n' % (b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24))
    col, fila, led = tablas()
    for nombre, datos, digitos in (('hd_col.hex', col, 6), ('hd_row.hex', fila, 2), ('hd_led.hex', led, 2)):
        with open(os.path.join(out, nombre), 'w') as f:
            f.write('\n'.join('%0*x' % (digitos, v) for v in datos) + '\n')

if __name__ == '__main__':
    main()
