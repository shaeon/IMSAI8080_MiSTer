# IMSAI 8080 para MiSTer

*[Read in English](README.md)*

Core de MiSTer del **IMSAI 8080** (1975) con su panel frontal, una consola de vídeo, dos unidades
de disco (controladora VersaFloppy con WD1793), un segundo puerto serie y el sintetizador de voz
**Votrax** (Type 'N Talk). Es el core de la Calypso de Manuel Teira
([teiram/calypso-ports](https://github.com/teiram/calypso-ports/tree/master/imsai8080), versión
0.5), metido en el marco de MiSTer.

Port a MiSTer: Shaeon (Carlos Palmero).

Además de la salida original de 800×600, tiene un **modo HD 1080p** con el panel redibujado a más
resolución y la consola a píxeles 2×2 exactos, y la consola puede usar una **fuente VT220** con
líneas de barrido.

## Instalación

- Copia el `.rbf` de `releases/` en `/media/fat/_Computer/`.
- Copia el contenido de la carpeta `sd/` en la raíz de la SD (`/media/fat/`). Deja en
  `games/IMSAI8080/`:
  - `boot.rom` (imagen del panel, el `IMSAI8080.ROM` de la Calypso) y `boot1.rom` (monitor
    MEMON/80, el `IMSAI8080.R01`), que el core carga solos al arrancar;
  - los discos de la Calypso: `cpm22.dsk` (CP/M 2.2), `wordstar.dsk`, `sc2.dsk` (SuperCalc 2) y
    `zorks.dsk` (Zork I y II).
- Las dos ROM también van dentro del RBF, así que el core arranca aunque falten. Los ficheros
  sirven para cambiarlas sin recompilar.

Los discos son EDSK de 77 pistas, 26 sectores de 128 bytes, 64 entradas de directorio y 2 pistas
de sistema.

## Uso

El ordenador arranca parado (WAIT) y el teclado está en el panel. Una sesión típica:

1. Pon F800 en los interruptores de dirección (teclas 1, 2, 3, 4 y 5).
2. EXAMINE (tecla A): en el bus de datos se ve F3.
3. RUN (tecla F): la consola muestra el mensaje de MEMON/80.
4. Monta el disco de CP/M en la unidad 0, pasa el teclado a la consola (Ctrl+F1) y arranca con el
   comando `BO` del monitor.

## Teclas

| Tecla | |
|---|---|
| 1-8 | Interruptores de entrada programada / dirección alta |
| Q-I | Interruptores de dirección / datos |
| A / Z | EXAMINE / EXAMINE NEXT |
| S / X | DEPOSIT / DEPOSIT NEXT |
| D / C | RESET / EXT CLR |
| F / V | RUN / STOP |
| G / B | SINGLE STEP |
| Ctrl+F1 | El teclado va al panel o a la consola |
| Ctrl+F2 | Intercambia la posición del panel y la consola |

## OSD

| Opción | |
|---|---|
| Mount Drive 0 / 1 | Imágenes EDSK |
| DSK Protect | Protección contra escritura de los discos |
| Reload Panel | Carga otra imagen de panel (`.ROM`) |
| Reload ROM at F800 | Vuelve a cargar el monitor en F800 (por ejemplo después de usar CP/M, que lo pisa) |
| Video mode | `800x600` (el de la Calypso) o `HD 1080p` (ver más abajo) |
| Aspect ratio, Scale | Las opciones habituales de MiSTer |
| Console color | Cian, blanco, verde o ámbar. Con el teclado en el panel sale más apagado (40 %) |
| Console font | `Wang` (la original) o `VT220` |
| Scanlines (HD) | Oscurece la segunda línea de cada par en la consola del modo HD: no, 25, 50 o 75 % |
| Flashing cursor | Cursor parpadeante |
| Votrax / Votrax Input | Activa el Votrax y elige si lee de la consola o del puerto B |
| Reset | |

## Modo HD 1080p

El modo de la Calypso (800×600) se ve escalado 1,8 veces en una pantalla de 1080 líneas, con líneas
desiguales. El modo HD saca **960×1080 a 60 Hz** y el escalador de MiSTer lo dobla en horizontal de
forma exacta, así que todo sale a escala entera:

- **Panel** a 1600×560 en pantalla, **redibujado** con el doble de resolución vertical: LEDs,
  palancas y LEDs de disco vueltos a dibujar con suavizado y todos los textos escritos de nuevo
  (`tools/genera_panel_hd.py`, a partir de la imagen de la Calypso).
- **Consola** de 80×25 a 1600×500, con caracteres de 10×10 en píxeles de 2×2. Con la fuente VT220 y
  `Scanlines` se parece mucho a un terminal de fósforo.
- Ctrl+F2 sigue intercambiando panel y consola.

Pensado para HDMI a 1080p (`video_mode=8` en `MiSTer.ini`). Por la salida analógica sale a 65 kHz,
que muchos monitores no aceptan: para VGA, mejor el modo 800×600.

## Fuente VT220

La fuente `VT220` es Glass TTY VT220 de Viacheslav Slavinsky
([svofski/glasstty](https://github.com/svofski/glasstty), dominio público), que reproduce los
caracteres del DEC VT220 con su estiramiento de puntos (`tools/genera_fuentes.py`). Los caracteres
gráficos del terminal siguen siendo los de la fuente Wang.

## Qué cambia respecto a la Calypso

La máquina (`rtl/imsai8080`) es una copia de la carpeta del core en calypso-ports (ver
[rtl/imsai8080/ORIGEN.md](rtl/imsai8080/ORIGEN.md): git no permite un submódulo de una sola
carpeta), con unos pocos cambios marcados con `MiSTer:` y apuntados allí. El Votrax sí es un
submódulo. El pegamento de MiSTer está en `IMSAI8080.sv`:

- **Relojes**: un PLL de 50 MHz con VCO de 720 MHz da 36 MHz (todo el core y el píxel de
  800×600), 2,5 MHz (Votrax) y 72 MHz (vídeo y modo HD). Los 72 MHz de la SDRAM y la PSRAM de la
  Calypso no hacen falta.
- **Memoria**: la RAM de 64K (PSRAM en la Calypso) y la imagen del panel (SDRAM en la Calypso) van
  en BRAM (`rtl/imsai_mem.sv`) y salen inicializadas en el RBF (`tools/genera_init.py`). El core
  no usa la SDRAM de MiSTer.
- **Vídeo**: 800x600 a 56 Hz (35,2 kHz) o el modo HD, directo a la salida VGA y al escalador
  HDMI, sin scandoubler.
- **Teclado**: `ps2_key` de `hps_io` convertido a las señales de `user_io` de MiST.
- **Audio**: la misma mezcla, por la salida de audio de MiSTer en lugar del I2S.

## Compilar

Con Quartus 17.0 (`IMSAI8080.qpf`) o `build.bat`. Hace falta el submódulo:
`git clone --recursive` o `git submodule update --init`.

Cada push compila el core en GitHub Actions (imagen Docker `raetro/quartus:17.0`) y deja el
`.rbf` y los informes en la pestaña *Actions*. Al subir una etiqueta `v*` se crea además una
Release con el `.rbf`.

## Créditos

- **Manuel Teira (teiram)**: el core IMSAI 8080 de la Calypso.
- Viacheslav Slavinsky y Sorgelig: WD1793. Fred VanEijk y Cyril Venditti: core Altair 8800, del
  que sale parte del código. 1801BM1@gmail.com: el 8080 (vm80a).
- MEMON/80 de Martin Eberhard.
- Viacheslav Slavinsky: fuente Glass TTY VT220.
- El marco de MiSTer (`sys/`, MiSTer-devel, Sorgelig).

## Licencia

GPL v2 o posterior, como el core y el marco `sys/`. IMSAI es marca de sus respectivos dueños.

---

Desarrollado con la ayuda de Claude (Anthropic).
