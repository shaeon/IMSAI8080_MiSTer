# IMSAI 8080 for MiSTer

*[Leer en español](README_es.md)*

MiSTer core for the **IMSAI 8080** (1975) with its front panel, a video console, two floppy
drives (VersaFloppy controller with a WD1793), a second serial port and the **Votrax** speech
synthesizer (Type 'N Talk). It is the Calypso core by Manuel Teira
([teiram/calypso-ports](https://github.com/teiram/calypso-ports/tree/master/imsai8080), version
0.5), wrapped in the MiSTer framework.

MiSTer port: Shaeon (Carlos Palmero).

Besides the original 800×600 output it has an **HD 1080p mode** with the panel redrawn at higher
resolution and the console at exact 2×2 pixels, and the console can use a **VT220 font** with
scanlines.

## Installation

- Copy the `.rbf` from `releases/` to `/media/fat/_Computer/`.
- Copy the contents of the `sd/` folder to the root of the SD card (`/media/fat/`). It puts in
  `games/IMSAI8080/`:
  - `boot.rom` (panel image, the Calypso `IMSAI8080.ROM`) and `boot1.rom` (MEMON/80 monitor,
    `IMSAI8080.R01`), which the core loads automatically when it starts;
  - the Calypso disks: `cpm22.dsk` (CP/M 2.2), `wordstar.dsk`, `sc2.dsk` (SuperCalc 2) and
    `zorks.dsk` (Zork I and II).
- Both ROMs are also built into the RBF, so the core starts even without them. The files let you
  replace them without recompiling.

Disks are EDSK with 77 tracks, 26 sectors of 128 bytes, 64 directory entries and 2 system
tracks.

## Usage

The computer starts stopped (WAIT) with the keyboard on the panel. A typical session:

1. Set F800 on the address switches (keys 1, 2, 3, 4 and 5).
2. EXAMINE (key A): the data bus shows F3.
3. RUN (key F): the console shows the MEMON/80 banner.
4. Mount the CP/M disk in drive 0, switch the keyboard to the console (Ctrl+F1) and boot with
   the monitor command `BO`.

## Keys

| Key | |
|---|---|
| 1-8 | Programmed input / high address switches |
| Q-I | Address / data switches |
| A / Z | EXAMINE / EXAMINE NEXT |
| S / X | DEPOSIT / DEPOSIT NEXT |
| D / C | RESET / EXT CLR |
| F / V | RUN / STOP |
| G / B | SINGLE STEP |
| Ctrl+F1 | Keyboard to the panel or to the console |
| Ctrl+F2 | Swap panel and console positions |

## OSD

| Option | |
|---|---|
| Mount Drive 0 / 1 | EDSK images |
| DSK Protect | Write protection for the disks |
| Reload Panel | Load another panel image (`.ROM`) |
| Reload ROM at F800 | Reload the monitor at F800 (for example after CP/M has overwritten it) |
| Video mode | `800x600` (the Calypso one) or `HD 1080p` (see below) |
| Aspect ratio, Scale | The usual MiSTer options |
| Console color | Cyan, white, green or amber. Dimmed (40 %) while the keyboard is on the panel |
| Console font | `Wang` (the original) or `VT220` |
| Scanlines (HD) | Darkens the second line of each pair in the HD console: none, 25, 50 or 75 % |
| Flashing cursor | Blinking cursor |
| Votrax / Votrax Input | Enable the Votrax and choose whether it reads from the console or port B |
| Reset | |

## HD 1080p mode

The Calypso mode (800×600) is scaled 1.8 times on a 1080-line screen, with uneven lines. The HD
mode outputs **960×1080 at 60 Hz** and the MiSTer scaler doubles it horizontally in an exact way, so
everything is shown at an integer scale:

- **Panel** at 1600×560 on screen, **redrawn** with twice the vertical resolution: LEDs, switch
  paddles and disk LEDs redrawn with antialiasing and every label typeset again
  (`tools/genera_panel_hd.py`, from the Calypso image).
- **Console** 80×25 at 1600×500, with 10×10 characters in 2×2 pixels. With the VT220 font and
  `Scanlines` it looks very much like a phosphor terminal.
- Ctrl+F2 still swaps panel and console.

Meant for HDMI at 1080p (`video_mode=8` in `MiSTer.ini`). On the analog output it runs at 65 kHz,
which many monitors do not accept: for VGA, use the 800×600 mode.

## VT220 font

The `VT220` font is Glass TTY VT220 by Viacheslav Slavinsky
([svofski/glasstty](https://github.com/svofski/glasstty), public domain), which reproduces the DEC
VT220 characters with their dot stretching (`tools/genera_fuentes.py`). The terminal graphics
characters are still those of the Wang font.

## What is different from the Calypso

The machine (`rtl/imsai8080`) is a copy of the core folder in calypso-ports (see
[rtl/imsai8080/ORIGEN.md](rtl/imsai8080/ORIGEN.md): git cannot make a submodule of a single
folder), with a few changes marked `MiSTer:` and listed there. The Votrax is a submodule. The
MiSTer glue is in `IMSAI8080.sv`:

- **Clocks**: one PLL from 50 MHz with a 720 MHz VCO gives 36 MHz (the whole core and the 800×600
  pixel clock), 2.5 MHz (Votrax) and 72 MHz (video and HD mode). The Calypso 72 MHz for SDRAM and
  PSRAM are not needed.
- **Memory**: the 64K RAM (PSRAM on the Calypso) and the panel image (SDRAM on the Calypso) are
  in BRAM (`rtl/imsai_mem.sv`), initialised in the RBF (`tools/genera_init.py`). The core does
  not use the MiSTer SDRAM.
- **Video**: 800x600 at 56 Hz (35.2 kHz) or the HD mode, straight to the VGA output and the HDMI
  scaler, no scandoubler.
- **Keyboard**: `ps2_key` from `hps_io` converted to the MiST `user_io` signals.
- **Audio**: the same mix, through the MiSTer audio output instead of I2S.

## Building

With Quartus 17.0 (`IMSAI8080.qpf`) or `build.bat`. The submodule is needed:
`git clone --recursive` or `git submodule update --init`.

Every push builds the core in GitHub Actions (Docker image `raetro/quartus:17.0`) and leaves the
`.rbf` and the reports in the *Actions* tab. Pushing a `v*` tag also creates a Release with the
`.rbf`.

## Credits

- **Manuel Teira (teiram)**: the Calypso IMSAI 8080 core.
- Viacheslav Slavinsky and Sorgelig: WD1793. Fred VanEijk and Cyril Venditti: Altair 8800 core,
  where part of the code comes from. 1801BM1@gmail.com: the 8080 (vm80a).
- MEMON/80 by Martin Eberhard.
- Viacheslav Slavinsky: Glass TTY VT220 font.
- The MiSTer framework (`sys/`, MiSTer-devel, Sorgelig).

## Licence

GPL v2 or later, like the core and the `sys/` framework. IMSAI is a trademark of its respective
owners.

---

Developed with the help of Claude (Anthropic).
