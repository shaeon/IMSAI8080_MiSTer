//-------------------------------------------------------------------------------------------------
// Fuente VT220 de la consola para el modo 800x600 (rtl/init/font_vt220.hex, tools/genera_fuentes.py).
// Igual que font_rom.v del terminal (altsyncram con entrada y salida registradas): el dato sale
// dos ciclos despues de la direccion.
//-------------------------------------------------------------------------------------------------
module font_rom_vt220
(
	input  wire        clock,
	input  wire [10:0] address,
	output reg   [9:0] q
);

	reg [9:0] mem[2048];
	initial $readmemh("rtl/init/font_vt220.hex", mem);

	reg [10:0] addr_r;
	always @(posedge clock) begin
		addr_r <= address;
		q <= mem[addr_r];
	end

endmodule
