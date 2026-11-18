#!/usr/bin/env python3
# Genera los ficheros de inicializacion de la BRAM (rtl/init/*.hex) a partir de los binarios de
# la Calypso (calypso-ports/imsai8080/extra-binaries):
#   IMSAI8080.ROM  imagen del panel, 800x280 a 4 bits (112000 bytes) -> panel0..3.hex
#                  (un fichero por byte de cada palabra de 32 bits, 28672 entradas)
#   IMSAI8080.R01  monitor MEMON/80 -> ram.hex (64K de RAM, con el monitor en F800)
#
# Uso: python3 tools/genera_init.py IMSAI8080.ROM IMSAI8080.R01
import sys, os

def main():
    if len(sys.argv) != 3:
        sys.exit("uso: genera_init.py IMSAI8080.ROM IMSAI8080.R01")
    panel = open(sys.argv[1], 'rb').read()
    rom = open(sys.argv[2], 'rb').read()
    if len(panel) > 4 * 28672:
        sys.exit("la imagen del panel no cabe en 112K")
    if len(rom) > 2048:
        sys.exit("la ROM del monitor no cabe en F800-FFFF")
    panel = panel + bytes(4 * 28672 - len(panel))
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'rtl', 'init')
    for lane in range(4):
        with open(os.path.join(out, 'panel%d.hex' % lane), 'w') as f:
            f.write('\n'.join('%02x' % panel[i * 4 + lane] for i in range(28672)) + '\n')
    ram = bytearray(65536)
    ram[0xF800:0xF800 + len(rom)] = rom
    with open(os.path.join(out, 'ram.hex'), 'w') as f:
        f.write('\n'.join('%02x' % b for b in ram) + '\n')

if __name__ == '__main__':
    main()
