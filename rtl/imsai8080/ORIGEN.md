# Origen de esta carpeta

Copia de `imsai8080/` de [teiram/calypso-ports](https://github.com/teiram/calypso-ports/tree/master/imsai8080)
(commit `55e40a641a3da4134990557c7f75252e3fa8b1eb`, 14-11-2026), core IMSAI 8080 de Manuel Teira,
versión 0.5.

No se usa un submódulo porque git no permite apuntar un submódulo a una subcarpeta de otro
repositorio, y calypso-ports entero (con todos sus submódulos) es muy grande para usar solo esto.

Qué se ha copiado:

- `rtl/` salvo `rtl/calypso/` (top, PLL, SDRAM y PSRAM de la Calypso), que aquí está en
  `IMSAI8080.sv` y `rtl/imsai_mem.sv`. `vga.sv` está en la raíz de esta carpeta.
- `rom/` (los `.mif` del juego de caracteres, del sonido de los interruptores y del Votrax).
- `asm/` (fuentes de MEMON/80 y de la BIOS de CP/M), como referencia.
- `readme.md` del original, como `readme_calypso.md`.

`votrax/votrax-sc01a-vhdl` es un submódulo (teiram/votrax-sc01a-vhdl, commit `0025f6f`, el mismo
que fija calypso-ports).

## Cambios en los ficheros de teiram

Todos marcados en el código con `MiSTer:`.

- `terminal/terminal.sv`
  - Entrada `font_vt220`: elige entre la fuente Wang (`font_rom`) y la VT220
    (`rtl/font_rom_vt220.sv`).
  - Salidas `hd_*` para el renderizador HD: las escrituras en la RAM de vídeo (para tener una copia)
    y el estado del cursor.
- `panel/panel.sv`
  - Salidas `hd_leds`, `hd_switches` y `hd_m_switches` para el renderizador HD.

Para actualizar: copiar de nuevo las mismas carpetas desde calypso-ports, volver a aplicar estos
cambios y anotar aquí el commit.
