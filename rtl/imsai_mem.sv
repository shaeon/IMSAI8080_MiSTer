//-------------------------------------------------------------------------------------------------
// Memorias de IMSAI8080 para MiSTer, en BRAM.
//
// En la Calypso la RAM de 64K del IMSAI va en la PSRAM de la powerpack (psram64.sv) y la imagen
// del panel en la SDRAM (sdram.sv, leida a 32 bits). En MiSTer las dos caben en la BRAM del
// Cyclone V (64 KB + 128 KB), asi que no hace falta el modulo SDRAM, y las dos salen ya cargadas
// en el RBF: la RAM con el monitor MEMON/80 en F800 y el panel con la imagen IMSAI8080.ROM
// (ver tools/genera_init.py). Se pueden volver a cargar desde el OSD como en la Calypso.
//
// This program is free software; you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation; either version 2 of
// the License, or (at your option) any later version.
//-------------------------------------------------------------------------------------------------
`default_nettype none

// RAM principal de 64K.
// Como psram64.sv: la escritura se hace en el flanco de subida de 'we' con el dato de ese momento.
// La lectura es continua (dout sigue a addr con un ciclo de retraso); el core solo la usa con rd.
// Durante la carga de la ROM del monitor se escribe en cada pulso de ioctl_wr.
module imsai_ram
(
	input  wire        clk,

	input  wire [15:0] addr,
	input  wire        we,
	input  wire  [7:0] din,
	output reg   [7:0] dout,

	input  wire        dl,          // carga de la ROM del monitor en curso
	input  wire        dl_wr,
	input  wire [15:0] dl_addr,
	input  wire  [7:0] dl_data
);

	reg [7:0] mem[65536];
	initial $readmemh("rtl/init/ram.hex", mem);

	reg we_last = 1'b0;
	always @(posedge clk) we_last <= we;

	wire        wr   = dl ? dl_wr   : (we & ~we_last);
	wire [15:0] wa   = dl ? dl_addr : addr;
	wire  [7:0] wd   = dl ? dl_data : din;

	always @(posedge clk) begin
		if (wr) mem[wa] <= wd;
		dout <= mem[addr];
	end

endmodule

// Imagen del panel: 800x280 puntos de 4 bits = 112000 bytes, leidos de 4 en 4 (8 puntos) como en
// la SDRAM de la Calypso: la palabra n son los bytes 4n..4n+3 del fichero, el primero en los bits
// bajos. Se escribe byte a byte desde ioctl. Cuatro bancos de 28K x 8 (28000 palabras), uno por byte.
module imsai_panel_ram
(
	input  wire        clk,

	input  wire [14:0] rd_addr,     // palabra de 32 bits (ram_addr[16:2] del panel)
	output reg  [31:0] rd_data,

	input  wire        wr,
	input  wire [16:0] wr_addr,     // byte
	input  wire  [7:0] wr_data
);

	reg [7:0] b0[28672];
	reg [7:0] b1[28672];
	reg [7:0] b2[28672];
	reg [7:0] b3[28672];
	initial begin
		$readmemh("rtl/init/panel0.hex", b0);
		$readmemh("rtl/init/panel1.hex", b1);
		$readmemh("rtl/init/panel2.hex", b2);
		$readmemh("rtl/init/panel3.hex", b3);
	end

	always @(posedge clk) begin
		if (wr && wr_addr[1:0] == 2'd0) b0[wr_addr[16:2]] <= wr_data;
		if (wr && wr_addr[1:0] == 2'd1) b1[wr_addr[16:2]] <= wr_data;
		if (wr && wr_addr[1:0] == 2'd2) b2[wr_addr[16:2]] <= wr_data;
		if (wr && wr_addr[1:0] == 2'd3) b3[wr_addr[16:2]] <= wr_data;
		rd_data <= {b3[rd_addr], b2[rd_addr], b1[rd_addr], b0[rd_addr]};
	end

endmodule

`default_nettype wire
