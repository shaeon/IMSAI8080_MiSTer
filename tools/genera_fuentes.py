#!/usr/bin/env python3
# Genera las fuentes de la consola:
#
#   rtl/init/font_vt220.hex  1524 (+ relleno hasta 2048) x 10 bits, mismo formato que wang-font.mif (127 caracteres de
#                            12 lineas), para el modo 800x600. Texto VT220 (ASCII 0x20-0x7D) en
#                            las lineas 1-10 de cada celda; graficos y 0x7E-0x7F de la Wang.
#   rtl/init/font_hd.hex     4096 x 10 bits para el modo HD: 0-1523 Wang, 2048-3571 VT220.
#                            El modo HD solo usa las lineas 1-10 de cada celda.
#
# La VT220 sale de Glass TTY VT220 (Viacheslav Slavinsky, https://github.com/svofski/glasstty,
# dominio publico / Unlicense). A 20 px cada caracter es una celda de 10x20 con los puntos ya
# estirados como en el VT220 y las lineas solo en las filas pares: 10x10.
#
# Uso: python3 tools/genera_fuentes.py rtl/imsai8080/rom/font/wang-font.mif Glass_TTY_VT220.ttf
import os, re, sys
from PIL import Image, ImageDraw, ImageFont

CELL = 12
CHARS = 127

def lee_mif(path):
    d = {}
    for a, v in re.findall(r'^\s*([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)\s*;', open(path).read(), re.M):
        d[int(a, 16)] = int(v, 16)
    return [d.get(i, 0) for i in range(CHARS * CELL)]

def glifo_vt220(font, ch):
    im = Image.new('L', (10, 20), 0)
    ImageDraw.Draw(im).text((0, 0), ch, font=font, fill=255)
    lineas = []
    for y in range(20):
        v = 0
        for x in range(10):
            if im.getpixel((x, y)) > 127:
                v |= 1 << (9 - x)
        lineas.append(v)
    # comprobaciones: nada en las filas impares (huecos de barrido) ni fuera de la celda
    for y in range(1, 20, 2):
        if lineas[y]:
            sys.exit("'%s': punto en la fila impar %d" % (ch, y))
    bb = font.getbbox(ch)
    if ch != ' ' and (bb[2] > 10 or bb[3] > 20 or bb[0] < 0 or bb[1] < 0):
        sys.exit("'%s': se sale de la celda 10x20 %s" % (ch, bb))
    return [lineas[y] for y in range(0, 20, 2)]

def escribe_hex(path, datos):
    with open(path, 'w') as f:
        f.write('\n'.join('%03x' % v for v in datos) + '\n')

def main():
    if len(sys.argv) != 3:
        sys.exit("uso: genera_fuentes.py wang-font.mif Glass_TTY_VT220.ttf")
    wang = lee_mif(sys.argv[1])
    font = ImageFont.truetype(sys.argv[2], 20)

    vt = list(wang)
    for idx in range(0x5E):                     # ASCII 0x20-0x7D
        g = glifo_vt220(font, chr(idx + 0x20))
        base = idx * CELL
        vt[base] = 0
        for k in range(10):
            vt[base + 1 + k] = g[k]
        vt[base + 11] = 0

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'rtl', 'init')
    escribe_hex(os.path.join(out, 'font_vt220.hex'), vt + [0] * (2048 - len(vt)))
    hd = [0] * 4096
    hd[0:len(wang)] = wang
    hd[2048:2048 + len(vt)] = vt
    escribe_hex(os.path.join(out, 'font_hd.hex'), hd)

    # vista previa (no se usa en la sintesis)
    if os.environ.get('PREVIEW'):
        S = 4
        im = Image.new('L', (32 * 10 * S, 4 * 2 * 12 * S), 0)
        for f, tabla in enumerate((wang, vt)):
            for c in range(0x60):
                ox = (c % 32) * 10 * S
                oy = (f * 3 + c // 32) * 12 * S
                for l in range(12):
                    for x in range(10):
                        if tabla[c * CELL + l] >> (9 - x) & 1:
                            for dy in range(S // 2):
                                for dx in range(S):
                                    im.putpixel((ox + x * S + dx, oy + l * S + dy), 255)
        im.save(os.environ['PREVIEW'])

if __name__ == '__main__':
    main()
