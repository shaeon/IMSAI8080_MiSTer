# Restricciones propias del core (las generales estan en sys/sys_top.sdc, que ya deriva los
# relojes del PLL).

# Salidas de rtl/pll.v. En get_clocks, con los corchetes escapados.
set clk_sys {emu|pll|pll_inst|altera_pll_i|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk}
set clk_2m5 {emu|pll|pll_inst|altera_pll_i|general\[1\].gpll~PLL_OUTPUT_COUNTER|divclk}

# ----------------------------------------------------------------------------
# clk_sys (36 MHz) <-> Votrax (2,5 MHz)
# ----------------------------------------------------------------------------
# En votrax.sv la CPU 6800 (cpu68) va a 2,5 MHz, y su RAM, su ROM, el registro de lectura
# (data_in), la ACIA y el SC-01A van a 36 MHz. 36/2,5 = 14,4 no es entero, asi que los flancos
# no estan alineados y TimeQuest acaba analizando las rutas con un margen de 2-3 ns (-5,4 ns de
# holgura). En realidad el lado de 36 MHz muestrea cada dato de la CPU unas 14 veces por ciclo de
# 2,5 MHz y la CPU recoge el suyo 400 ns despues: se tratan como asincronos.
set_clock_groups -asynchronous \
	-group [get_clocks $clk_sys] \
	-group [get_clocks $clk_2m5]
