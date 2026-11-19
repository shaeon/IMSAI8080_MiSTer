//-------------------------------------------------------------------------------------------------
// Renderizador HD de IMSAI8080 para MiSTer
//
// Saca 1920x1080 reales a 30 Hz (2200x1091 en total) con un reloj de 72 MHz: cada punto es un
// pixel de una pantalla de 1080p. Son 30 cuadros por segundo porque 1920 puntos a 60 Hz pedirian
// 144 MHz en el core y en la entrada del escalador; el escalador de MiSTer repite cada cuadro y la
// salida HDMI sigue a 60 Hz (con vsync_adjust=0).
//
//   - Panel: imagen de 1600x560 a 4 bits, guardada como teselas de 8x8 (rtl/init/hd_map.hex y
//     hd_tiles.hex), con la paleta y las reglas de panel.sv para LEDs (indice 3 -> rojo) e
//     interruptores (barra gris donde el punto no es 0). Las zonas de LEDs e interruptores se
//     buscan en tablas por columna y por fila del panel original (tools/genera_hd.py): la columna
//     y la fila HD / 2.
//   - Consola: 80x25 caracteres de 10x10 con cada punto a 2x2 (20 lineas por fila), leyendo una
//     copia de la RAM de video del terminal. Fuente Wang o VT220 (lineas 1-10 de la celda de 12).
//     La segunda copia de cada linea se puede oscurecer (lineas de barrido).
//
// Distribucion: margen X 160, panel 1600x560 en Y 5, consola 1600x500 en Y 575; con 'swap' la
// consola va arriba (Y 5) y el panel abajo (Y 515). Solo las 1600 columnas centrales son zona
// visible (1600x1080, 40:27).
//
// Las entradas que vienen del core (36 MHz) salen del mismo PLL que clk (72 MHz) y son sincronas.
//
// Shaeon (Carlos Palmero). GPL v2 o posterior.
//-------------------------------------------------------------------------------------------------
`default_nettype none

module hd_video
(
	input  wire        clk,             // 72 MHz
	input  wire        clk_core,        // 36 MHz (escritura de la copia de la RAM de video)

	// Opciones
	input  wire        swap,            // consola arriba
	input  wire        font_vt220,
	input  wire  [1:0] scanlines,       // 0 no, 1 25 %, 2 50 %, 3 75 %
	input  wire  [1:0] term_color,      // 0 cian, 1 blanco, 2 verde, 3 ambar
	input  wire        term_active,     // el teclado va a la consola
	input  wire        flashing_cursor,

	// Terminal (dominio de clk_core)
	input  wire        vram_we,
	input  wire [11:0] vram_addr,
	input  wire  [8:0] vram_data,
	input  wire  [4:0] cursor_row,
	input  wire  [6:0] cursor_col,
	input  wire        cursor_on,
	input  wire        cursor_block,
	input  wire        cursor_timer,

	// Panel
	input  wire [43:0] leds,
	input  wire [15:0] switches,
	input  wire  [9:0] m_switches,
	input  wire  [7:0] disk_leds,

	output reg   [7:0] R,
	output reg   [7:0] G,
	output reg   [7:0] B,
	output reg         HSync,
	output reg         VSync,
	output reg         HBlank,
	output reg         VBlank
);

	localparam [11:0] H_ACT = 12'd1920, H_SS = 12'd2008, H_SE = 12'd2052, H_TOT = 12'd2200;
	localparam [10:0] V_ACT = 11'd1080, V_SS = 11'd1083, V_SE = 11'd1088, V_TOT = 11'd1091;
	localparam [11:0] X0 = 12'd160;

	localparam [10:0] PANEL_H = 11'd560;
	localparam [10:0] CONS_H  = 11'd500;

	wire [10:0] PY0 = swap ? 11'd515 : 11'd5;
	wire [10:0] CY0 = swap ? 11'd5   : 11'd575;

//--- memorias ------------------------------------------------------------------------------------

	`include "rtl/init/hd_params.vh"
	reg [12:0] map_rom[14000];          // 200x70 teselas
	reg [31:0] tile_rom[HD_TILES * 8];  // 8 lineas de 8 puntos por tesela
	reg [23:0] col_lut[800];
	reg  [7:0] row_lut[280];
	reg  [6:0] led_map[128];
	reg  [9:0] font_rom[4096];
	initial begin
		$readmemh("rtl/init/hd_map.hex", map_rom);
		$readmemh("rtl/init/hd_tiles.hex", tile_rom);
		$readmemh("rtl/init/hd_col.hex", col_lut);
		$readmemh("rtl/init/hd_row.hex", row_lut);
		$readmemh("rtl/init/hd_led.hex", led_map);
		$readmemh("rtl/init/font_hd.hex", font_rom);
	end

	// Copia de la RAM de video del terminal: se escribe a 36 MHz a la vez que la original
	reg [8:0] vram[4096];
	always @(posedge clk_core) if (vram_we) vram[vram_addr] <= vram_data;

//--- etapa 0: contadores -------------------------------------------------------------------------

	reg [11:0] hc = 12'd0;
	reg [10:0] vc = 11'd0;
	reg  [3:0] px = 4'd0;           // punto dentro del caracter
	reg  [6:0] col = 7'd0;          // columna de la consola
	reg        ph = 1'b0;           // mitad del punto de la consola (cada punto son 2 pixeles)
	reg [13:0] p_base = 14'd0;      // direccion en el mapa de la fila de teselas (200 por fila)
	reg  [9:0] p_line = 10'd0;      // linea del panel (0-559)
	reg  [4:0] c_row = 5'd0;        // fila de la consola
	reg  [4:0] c_cl = 5'd0;         // linea dentro de la fila (0-19)
	reg        in_p = 1'b0, in_c = 1'b0;

	always @(posedge clk) begin
		if (hc == H_TOT - 1'd1) begin
			hc <= 12'd0;
			if (vc == V_TOT - 1'd1) vc <= 11'd0;
			else vc <= vc + 1'd1;

			// valores de la linea siguiente (vc + 1)
			if (vc + 1'd1 == PY0) begin
				in_p <= 1'b1; p_line <= 10'd0; p_base <= 14'd0;
			end
			else if (in_p) begin
				if (p_line == PANEL_H - 1'd1) in_p <= 1'b0;
				p_line <= p_line + 1'd1;
				if (p_line[2:0] == 3'd7) p_base <= p_base + 14'd200;
			end

			if (vc + 1'd1 == CY0) begin
				in_c <= 1'b1; c_row <= 5'd0; c_cl <= 5'd0;
			end
			else if (in_c) begin
				if (c_row == 5'd24 && c_cl == 5'd19) in_c <= 1'b0;
				if (c_cl == 5'd19) begin
					c_cl <= 5'd0;
					c_row <= c_row + 1'd1;
				end
				else c_cl <= c_cl + 1'd1;
			end
		end
		else hc <= hc + 1'd1;

		if (hc == X0 - 1'd1) begin
			px <= 4'd0;
			col <= 7'd0;
			ph <= 1'b0;
		end
		else begin
			ph <= ~ph;
			if (ph) begin
				if (px == 4'd9) begin
					px <= 4'd0;
					col <= col + 1'd1;
				end
				else px <= px + 1'd1;
			end
		end
	end

	wire        s0_inx = hc >= X0 && hc < X0 + 12'd1600;
	wire [10:0] s0_x = hc[10:0] - X0[10:0];
	// Zona visible: solo las 1600 columnas del panel y la consola (los margenes de 160 a cada lado
	// van en el borrado). Asi el escalador ve una imagen de 1600x1080 (40:27): con "Original" sale
	// a 1:1 con bandas negras a los lados y con "Full Screen" se estira a todo el ancho.
	wire       s0_hb = hc < X0 || hc >= X0 + 12'd1600;
	wire       s0_vb = vc >= V_ACT;
	wire       s0_hs = hc >= H_SS && hc < H_SE;
	wire       s0_vs = vc >= V_SS && vc < V_SE;

	// Estado del panel y del cursor congelado durante cada cuadro (como leds_latched en panel.sv)
	reg [43:0] leds_l;
	reg [15:0] sw_l;
	reg  [9:0] msw_l;
	reg  [7:0] dl_l;
	always @(posedge clk) if (hc == 12'd0 && vc == V_ACT) begin
		leds_l <= leds;
		sw_l <= switches;
		msw_l <= m_switches;
		dl_l <= disk_leds;
	end

//--- etapa 1: direcciones ------------------------------------------------------------------------

	reg [13:0] s1_maddr;
	reg [10:0] s1_x;
	reg  [8:0] s1_prow;
	reg  [2:0] s1_pl;
	reg [11:0] s1_vaddr;
	reg  [3:0] s1_px;
	reg  [6:0] s1_col;
	reg  [4:0] s1_row;
	reg  [3:0] s1_l;
	reg        s1_odd, s1_p, s1_c;
	reg  [3:0] s1_sync;             // {hs, vs, hb, vb}

	always @(posedge clk) begin
		s1_maddr <= p_base + s0_x[10:3];
		s1_x     <= s0_x;
		s1_prow  <= p_line[9:1];
		s1_pl    <= p_line[2:0];
		s1_vaddr <= {c_row, col};
		s1_px    <= px;
		s1_col   <= col;
		s1_row   <= c_row;
		s1_l     <= c_cl[4:1];
		s1_odd   <= c_cl[0];
		s1_p     <= in_p & s0_inx & ~s0_vb;
		s1_c     <= in_c & s0_inx & ~s0_vb;
		s1_sync  <= {s0_hs, s0_vs, s0_hb, s0_vb};
	end

//--- etapa 2: lecturas ---------------------------------------------------------------------------

	reg [12:0] s2_tile;
	reg [23:0] s2_colv;
	reg  [7:0] s2_rowv;
	reg  [8:0] s2_code;
	always @(posedge clk) begin
		s2_tile <= map_rom[s1_maddr];
		s2_colv <= col_lut[s1_x[10:1]];
		s2_rowv <= row_lut[s1_prow];
		s2_code <= vram[s1_vaddr];
	end

	reg  [2:0] s2_sub, s2_pl;
	reg  [3:0] s2_px, s2_l;
	reg  [6:0] s2_col;
	reg  [4:0] s2_row;
	reg        s2_odd, s2_p, s2_c;
	reg  [3:0] s2_sync;
	always @(posedge clk) begin
		s2_sub  <= s1_x[2:0];
		s2_pl   <= s1_pl;
		s2_px   <= s1_px;
		s2_l    <= s1_l;
		s2_col  <= s1_col;
		s2_row  <= s1_row;
		s2_odd  <= s1_odd;
		s2_p    <= s1_p;
		s2_c    <= s1_c;
		s2_sync <= s1_sync;
	end

//--- etapa 3 -------------------------------------------------------------------------------------

	// Caracter de la consola (como char_codebase en terminal.sv)
	wire        s2_gr = s2_code[6:0] >= 7'h5E && s2_code[6:0] <= 7'h7E;
	wire  [6:0] s2_cb = (s2_code[8] && s2_gr) ? s2_code[6:0] :
	                    (s2_code[6:0] < 7'h20 ? 7'd0 : s2_code[6:0] - 7'h20);
	wire [10:0] s2_fa = {s2_cb, 3'b000} + {1'b0, s2_cb, 2'b00} + 11'd1 + s2_l;

	reg [31:0] s3_word;
	reg  [2:0] s3_sub;
	always @(posedge clk) begin
		s3_word <= tile_rom[{s2_tile, s2_pl}];
		s3_sub  <= s2_sub;
	end

	reg  [6:0] s3_mapa_addr, s3_mapb_addr;
	reg        s3_ledav, s3_ledbv, s3_swv, s3_dv;
	reg  [4:0] s3_swidx;
	reg  [2:0] s3_didx;
	reg  [2:0] s3_swrows;           // {arriba, abajo, reposo}
	reg [11:0] s3_faddr;
	reg        s3_rev;
	reg  [3:0] s3_px, s3_l;
	reg        s3_cur, s3_odd, s3_p, s3_c;
	reg  [3:0] s3_sync;

	always @(posedge clk) begin
		s3_mapa_addr <= {s2_rowv[6:5], s2_colv[22:18]};
		s3_mapb_addr <= {s2_rowv[6:5], s2_colv[16:12]};
		s3_ledav     <= s2_colv[23] & s2_rowv[7];
		s3_ledbv     <= s2_colv[17] & s2_rowv[7];
		s3_swv       <= s2_colv[11];
		s3_swidx     <= s2_colv[10:6];
		s3_swrows    <= s2_rowv[2:0];
		s3_dv        <= s2_colv[5] & s2_rowv[4];
		s3_didx      <= {s2_colv[4:3], s2_rowv[3]};

		s3_faddr     <= {font_vt220, s2_fa};
		s3_rev       <= s2_code[7];
		s3_cur       <= cursor_on && s2_row == cursor_row && s2_col == cursor_col &&
		                (~flashing_cursor || cursor_timer) && (cursor_block || s2_l >= 4'd8);
		s3_px        <= s2_px;
		s3_l         <= s2_l;
		s3_odd       <= s2_odd;
		s3_p         <= s2_p;
		s3_c         <= s2_c;
		s3_sync      <= s2_sync;
	end

//--- etapa 4 -------------------------------------------------------------------------------------

	reg  [6:0] s4_mapa, s4_mapb;
	reg  [9:0] s4_font;
	always @(posedge clk) begin
		s4_mapa <= led_map[s3_mapa_addr];
		s4_mapb <= led_map[s3_mapb_addr];
		s4_font <= font_rom[s3_faddr];
	end

	reg  [3:0] s4_pix;
	reg        s4_ledav, s4_ledbv, s4_dv, s4_bar;
	reg  [2:0] s4_didx;
	reg        s4_rev, s4_cur, s4_odd, s4_p, s4_c;
	reg  [3:0] s4_px;
	reg  [3:0] s4_sync;

	// Barra de los interruptores (como en panel.sv)
	wire [3:0] s3_m   = s3_swidx[2:0];
	wire       s3_mp0 = msw_l[{s3_m, 1'b1}];      // m_switches_p[m][0]: arriba
	wire       s3_mp1 = msw_l[{s3_m, 1'b0}];      // m_switches_p[m][1]: abajo
	wire       s3_bar = s3_swv && (s3_swidx < 5'd16 ?
		(s3_swrows[2] & sw_l[s3_swidx[3:0]]) | (s3_swrows[1] & ~sw_l[s3_swidx[3:0]]) :
		(s3_swrows[2] & s3_mp0) | (s3_swrows[1] & s3_mp1) | (s3_swrows[0] & ~s3_mp0 & ~s3_mp1));

	always @(posedge clk) begin
		s4_pix   <= s3_word[{s3_sub, 2'b00} +: 4];   // el punto k, en los bits [4k+3:4k]
		s4_ledav <= s3_ledav;
		s4_ledbv <= s3_ledbv;
		s4_dv    <= s3_dv;
		s4_didx  <= s3_didx;
		s4_bar   <= s3_bar;
		s4_rev   <= s3_rev;
		s4_cur   <= s3_cur;
		s4_px    <= s3_px;
		s4_odd   <= s3_odd;
		s4_p     <= s3_p;
		s4_c     <= s3_c;
		s4_sync  <= s3_sync;
	end

//--- etapa 5: colores ----------------------------------------------------------------------------

	function [11:0] paleta(input [3:0] i);
		case (i)
			4'd0:  paleta = 12'h000; 4'd1:  paleta = 12'h001; 4'd2:  paleta = 12'h110; 4'd3:  paleta = 12'h400;
			4'd4:  paleta = 12'h3aa; 4'd5:  paleta = 12'h600; 4'd6:  paleta = 12'hb00; 4'd7:  paleta = 12'h222;
			4'd8:  paleta = 12'h454; 4'd9:  paleta = 12'h777; 4'd10: paleta = 12'h888; 4'd11: paleta = 12'h999;
			4'd12: paleta = 12'haaa; 4'd13: paleta = 12'haba; 4'd14: paleta = 12'hbcb; default: paleta = 12'hfff;
		endcase
	endfunction

	wire s4_led_on = (s4_ledav & s4_mapa[6] & leds_l[s4_mapa[5:0]]) |
	                 (s4_ledbv & s4_mapb[6] & leds_l[s4_mapb[5:0]]) |
	                 (s4_dv & dl_l[s4_didx]);

	wire [11:0] s4_prgb = (s4_bar && s4_pix != 4'd0) ? 12'hbbb :
	                      (s4_led_on && s4_pix == 4'd3) ? 12'hf00 : paleta(s4_pix);

	wire        s4_dot = s4_font[4'd9 - s4_px] ^ s4_rev;
	wire        s4_on = s4_dot | s4_cur;
	// Color de la consola; con el teclado en el panel, el mismo al 40 % (como en IMSAI8080.sv)
	wire [11:0] s4_fg = term_color == 2'd0 ? (term_active ? 12'h7ee : 12'h366) :
	                    term_color == 2'd1 ? (term_active ? 12'heee : 12'h666) :
	                    term_color == 2'd2 ? (term_active ? 12'h0e0 : 12'h060) :
	                                         (term_active ? 12'hfb0 : 12'h640);
	wire [11:0] s4_crgb = s4_on ? s4_fg : 12'h111;

	reg [23:0] s5_rgb;
	reg  [1:0] s5_dark;
	reg  [3:0] s5_sync;
	always @(posedge clk) begin
		if (s4_p)
			s5_rgb <= {s4_prgb[11:8], s4_prgb[11:8], s4_prgb[7:4], s4_prgb[7:4], s4_prgb[3:0], s4_prgb[3:0]};
		else if (s4_c)
			s5_rgb <= {s4_crgb[11:8], s4_crgb[11:8], s4_crgb[7:4], s4_crgb[7:4], s4_crgb[3:0], s4_crgb[3:0]};
		else
			s5_rgb <= 24'd0;
		s5_dark <= (s4_c & s4_odd) ? scanlines : 2'd0;
		s5_sync <= s4_sync;
	end

//--- etapa 6: lineas de barrido y salida ---------------------------------------------------------

	function [7:0] oscurece(input [7:0] c, input [1:0] n);
		case (n)
			2'd0: oscurece = c;
			2'd1: oscurece = c - {2'b00, c[7:2]};
			2'd2: oscurece = {1'b0, c[7:1]};
			default: oscurece = {2'b00, c[7:2]};
		endcase
	endfunction

	always @(posedge clk) begin
		R <= oscurece(s5_rgb[23:16], s5_dark);
		G <= oscurece(s5_rgb[15:8], s5_dark);
		B <= oscurece(s5_rgb[7:0], s5_dark);
		{HSync, VSync, HBlank, VBlank} <= s5_sync;
	end

endmodule

`default_nettype wire
