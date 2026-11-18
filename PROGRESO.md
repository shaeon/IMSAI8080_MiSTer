# Progreso: fuente VT220, modo HD 1080p y panel HD

Para retomar con "sigue". Se va actualizando a medida que se avanza.

## Decisiones

- **Modo HD**: el core saca 960x1080 a 60 Hz con reloj de vídeo de 72 MHz (1100x1091 en total).
  El escalador de MiSTer dobla en horizontal de forma exacta (16:9 -> 1920x1080), así que cada
  punto del core son 2x1 píxeles de pantalla y, con las líneas dobladas, 2x2.
  - 1920 de ancho real (148,5 MHz) se descarta: dobla el ancho de banda del escalador con la DDR3
    y el reloj de entrada del escalador; demasiado riesgo.
  - 72 MHz = 2 x 36 MHz del core, del mismo PLL (VCO 720 MHz: 72 /10, 36 /20, 2,5 /288). Así
    CLK_VIDEO es siempre 72 MHz: en modo 800x600 el CE_PIXEL va a 36 MHz y en HD a 72 MHz. No hace
    falta multiplexar relojes y los cruces 36 -> 72 son síncronos.
- **Renderizador HD propio** (`rtl/hd_video.sv`), aparte del de teiram, que se queda para el modo
  800x600. Lee el estado del core:
  - texto de la consola: copia de la RAM de vídeo del terminal (doble puerto 36/72 MHz) que se
    escribe a la vez que la original (`terminal.sv` saca las señales de escritura);
  - cursor, LEDs, interruptores: puertos nuevos en `terminal.sv` y `panel.sv`.
- **Distribución HD** (en puntos del core, 960x1080): margen X 80. Panel 800x560 (Y 5-564),
  hueco de 10, consola 800x500 (Y 575-1074). Con Ctrl+F2 se intercambian.
- **Consola HD**: celdas de 10x10 dobladas en vertical (20 líneas), 25 filas = 500. De la celda
  de 12 líneas de la fuente se usan las líneas 1-10.
- **Fuente VT220**: Glass TTY VT220 (svofski, dominio público / Unlicense), rasterizada a 20 px:
  10x10 con estiramiento de puntos ya aplicado. Se coloca en las líneas 1-10 de la celda de 12
  para que valga en los dos modos. Los gráficos (índices 0x5E-0x7E) siguen siendo los de Wang.
- **Líneas de barrido** (solo HD, solo la consola): la segunda copia de cada línea se oscurece
  0/25/50/75 %.
- **Panel HD**: imagen 800x560 a 4 bits con la misma paleta (las mismas reglas de LEDs: índice 3,
  e interruptores: != 0). Primero se usa el panel original con las líneas dobladas; después se
  redibuja a más resolución.

## Estado

- [x] Fuentes: tools/genera_fuentes.py -> rtl/init/font_vt220.hex y rtl/init/font_hd.hex
- [x] Fuente VT220 en modo 800x600 (terminal.sv: entrada font_vt220, rtl/font_rom_vt220.sv)
- [x] Puertos nuevos en terminal.sv y panel.sv
- [x] PLL con 72 MHz (VCO 720)
- [x] hd_video.sv + tools/genera_hd.py (tablas de LEDs/interruptores, panel_hd.hex)
- [x] Integración en IMSAI8080.sv, OSD (O[11] modo, O[12] fuente, O[14:13] barrido)
- [x] Simulación del modo HD (verilator en /home/claude/sim, stubs): cuadro 960x1080 correcto;
      coincide punto a punto con las reglas de panel.sv
- [x] ~~Arreglado en panel.sv: zonas de los LEDs descentradas~~ No era un fallo: en panel.sv la
      imagen sale 8 puntos a la derecha de 'col' y las zonas estan en columnas de 'col'. Se ha
      deshecho el cambio. El fallo estaba en las tablas HD, que no tenian en cuenta ese retraso:
      LEDs a medias y barras de los interruptores fuera de las palancas (probado en la placa).
      Ahora genera_hd.py resta los 8 puntos, centra las zonas de los LEDs en los LEDs del dibujo
      y amplia un punto las de los LEDs de disco; genera_panel_hd.py pasa a 0 los casi negros.
- [x] Panel HD redibujado (tools/genera_panel_hd.py -> rtl/init/panel_hd.png -> genera_hd.py --png)
- [x] Compilación y tiempos (primera versión: clk_vid +3,2 ns; 547/553 bloques de RAM, se ha
      reducido el panel SD a 28K por banco)
- [x] README, ORIGEN.md (cambios en los ficheros de teiram)
- [x] Compilación final (Quartus 17.0.2, SEED 2): cumple tiempos (clk_vid +3,3 ns, clk_sys +7,6 ns, pll_hdmi +0,19 ns);
      531/553 bloques de RAM, 30 % de ALMs. Commit y entrega.

## Pendiente / ideas

- Probar en la placa: modo HD por HDMI, cambio de modo en caliente, fuente VT220 en 800x600.
- Los bloques de RAM van casi llenos (~99 %): cualquier ampliación tendría que sacar algo a SDRAM.
