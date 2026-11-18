// PLL de IMSAI8080 (VCO de 720 MHz a partir de los 50 MHz de la placa):
//   outclk_0  36 MHz   clk_sys: todo el core y el video 800x600 (/20)
//   outclk_1  2,5 MHz  reloj del sintetizador Votrax SC-01A (/288)
//   outclk_2  72 MHz   clk_vid: CLK_VIDEO y el renderizador HD (/10)
// En la Calypso salian del mismo PLL junto con 72 MHz para SDRAM/PSRAM, que
// aqui no hacen falta (la RAM y el panel van en BRAM).

module pll (
		input  wire  refclk,
		input  wire  rst,
		output wire  outclk_0,
		output wire  outclk_1,
		output wire  outclk_2,
		output wire  locked
	);

	pll_0002 pll_inst (
		.refclk   (refclk),
		.rst      (rst),
		.outclk_0 (outclk_0),
		.outclk_1 (outclk_1),
		.outclk_2 (outclk_2),
		.locked   (locked)
	);

endmodule
