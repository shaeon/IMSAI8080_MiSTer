//-------------------------------------------------------------------------------------------------
// IMSAI 8080 para MiSTer
//
// Core: Manuel Teira (teiram), calypso-ports/imsai8080 (https://github.com/teiram/calypso-ports).
// La maquina se ha copiado tal cual en rtl/imsai8080 (ver rtl/imsai8080/ORIGEN.md). Este fichero
// hace con el marco de MiSTer lo que rtl/calypso/imsai8080_calypso.sv hace con el de MiST:
// relojes, hps_io, memoria, video, audio y LEDs. El resto del cableado es el mismo.
//
// Port a MiSTer: Shaeon (Carlos Palmero).
//
// Relojes (rtl/pll.v, de un VCO de 900 MHz):
//   clk_sys  36 MHz   todo el core; tambien es el reloj de pixel del video 800x600 (56 Hz)
//   clk_2m5  2,5 MHz  el Votrax SC-01A
//
// Memoria: la RAM de 64K y la imagen del panel van en BRAM y salen cargadas en el RBF (no hace
// falta SDRAM ni ningun fichero). Se pueden cambiar:
//   indice 0x00  games/IMSAI8080/boot.rom   imagen del panel (IMSAI8080.ROM de la Calypso)
//   indice 0x40  games/IMSAI8080/boot1.rom  ROM del monitor, a F800 (IMSAI8080.R01)
//   indice 1     OSD "Reload panel"
//   indice 2     OSD "Reload ROM at F800"
//
// Video: el core genera 800x600 (1024x625 en total, 35,2 kHz / 56,25 Hz): el panel arriba (280
// lineas) y la consola abajo, o al reves con Ctrl+F2. Va directo, sin scandoubler.
//
// This program is free software; you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation; either version 2 of
// the License, or (at your option) any later version.
//-------------------------------------------------------------------------------------------------
`default_nettype none

module emu
(
	`include "sys/emu_ports.vh"
);
//--- defaults ------------------------------------------------------------------------------------

	assign ADC_BUS  = 'Z;
	assign USER_OUT = '1;
	assign {UART_RTS, UART_TXD, UART_DTR} = 0;
	assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
	assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH,
	        SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
	assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

	assign VGA_F1 = 0;
	assign VGA_SCALER = 0;
	assign VGA_DISABLE = 0;
	assign HDMI_FREEZE = 0;
	assign HDMI_BLACKOUT = 0;
	assign HDMI_BOB_DEINT = 0;

	assign BUTTONS = 0;
	assign LED_POWER = 0;

//--- config string -------------------------------------------------------------------------------
//
//  Los bits 0-6 son los mismos que en la Calypso.
//  bits usados: 0-10
//  0         1         2         3
//  01234567890123456789012345678901
//  XXXXXXXXXXX
//

	`include "build_id.v"
	localparam CONF_STR =
	{
		"IMSAI8080;;",
		"-;",
		"S0,DSK,Mount Drive 0;",
		"S1,DSK,Mount Drive 1;",
		"O[3],DSK Protect,Disable,Enable;",
		"-;",
		"F1,ROM,Reload Panel;",
		"F2,ROM,Reload ROM at F800;",
		"-;",
		"O[9:8],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
		"O[10],Scale,Normal,V-Integer;",
		"-;",
		"O[2:1],Console color,Cyan,White,Green,Amber;",
		"O[6],Flashing cursor,No,Yes;",
		"O[4],Votrax,Disabled,Enabled;",
		"O[5],Votrax Input,Console,Port B;",
		"-;",
		"R[0],Reset;",
		"V,v",`BUILD_DATE
	};

//--- relojes -------------------------------------------------------------------------------------

	wire clk_sys;      // 36 MHz (clk36m en la Calypso)
	wire clk_2m5;      // 2,5 MHz
	wire pll_locked;

	pll pll
	(
		.refclk  (CLK_50M   ),
		.rst     (1'b0      ),
		.outclk_0(clk_sys   ),
		.outclk_1(clk_2m5   ),
		.locked  (pll_locked)
	);

	// En la Calypso es la fase de la SDRAM; aqui solo la usa vga.sv para arrancar alineado
	reg [1:0] ce_counter = 2'd0;
	wire mem_clkref = ce_counter == 2'b00;
	always @(posedge clk_sys) ce_counter <= ce_counter + 1'd1;

//--- hps_io --------------------------------------------------------------------------------------

	wire [127:0] status;
	wire  [21:0] gamma_bus;
	wire   [1:0] buttons;
	wire  [10:0] ps2_key;

	wire  [31:0] sd_lba[2];
	wire   [1:0] sd_rd;
	wire   [1:0] sd_wr;
	wire   [1:0] sd_ack;
	wire   [8:0] sd_buff_addr;
	wire   [7:0] sd_buff_dout;
	wire   [7:0] sd_buff_din[2];
	wire         sd_buff_wr;
	wire   [1:0] img_mounted;
	wire  [63:0] img_size;

	wire         ioctl_download;
	wire  [15:0] ioctl_index;
	wire         ioctl_wr;
	wire  [26:0] ioctl_addr;
	wire   [7:0] ioctl_dout;

	hps_io #(.CONF_STR(CONF_STR), .VDNUM(2)) hps_io
	(
		.clk_sys           (clk_sys           ),
		.HPS_BUS           (HPS_BUS           ),
		.EXT_BUS           (                  ),
		.gamma_bus         (gamma_bus         ),

		.status            (status            ),
		.status_menumask   (16'd0             ),
		.buttons           (buttons           ),
		.forced_scandoubler(                  ),

		.ps2_key           (ps2_key           ),

		.sd_lba            (sd_lba            ),
		.sd_blk_cnt        ('{6'd0, 6'd0}     ),
		.sd_rd             (sd_rd             ),
		.sd_wr             (sd_wr             ),
		.sd_ack            (sd_ack            ),
		.sd_buff_addr      (sd_buff_addr      ),
		.sd_buff_dout      (sd_buff_dout      ),
		.sd_buff_din       (sd_buff_din       ),
		.sd_buff_wr        (sd_buff_wr        ),
		.img_mounted       (img_mounted       ),
		.img_readonly      (                  ),
		.img_size          (img_size          ),

		.ioctl_download    (ioctl_download    ),
		.ioctl_index       (ioctl_index       ),
		.ioctl_wr          (ioctl_wr          ),
		.ioctl_addr        (ioctl_addr        ),
		.ioctl_dout        (ioctl_dout        ),
		.ioctl_wait        (1'b0              )
	);

	// Teclado: ps2_key de MiSTer a las senales de user_io de MiST
	reg  key_toggle = 1'b0;
	always @(posedge clk_sys) key_toggle <= ps2_key[10];
	wire       key_strobe   = key_toggle ^ ps2_key[10];
	wire       key_pressed  = ps2_key[9];
	wire       key_extended = ps2_key[8];
	wire [7:0] key_code     = ps2_key[7:0];

//--- cargas y reset ------------------------------------------------------------------------------

	wire [7:0] dl_index = ioctl_index[7:0];
	wire panel_download = ioctl_download && (dl_index == 8'h00 || dl_index == 8'h01);
	wire rom_download   = ioctl_download && (dl_index == 8'h40 || dl_index == 8'h02);

	// En la Calypso empiezan a 0 (hay que cargar los dos ficheros); aqui ya vienen en el RBF
	reg panel_ready = 1'b1;
	reg rom_ready   = 1'b1;

	always @(posedge clk_sys) begin
		reg panel_download_last = 1'b0;
		reg rom_download_last   = 1'b0;
		panel_download_last <= panel_download;
		rom_download_last   <= rom_download;
		if (~panel_download_last & panel_download) panel_ready <= 1'b0;
		if (~rom_download_last   & rom_download)   rom_ready   <= 1'b0;
		if (panel_download_last & ~panel_download) panel_ready <= 1'b1;
		if (rom_download_last   & ~rom_download)   rom_ready   <= 1'b1;
	end

	wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~pll_locked | ~panel_ready | ~rom_ready;

//--- maquina (igual que imsai8080_calypso.sv) ----------------------------------------------------

	wire [16:2] vid_ram_addr;
	wire [31:0] ram_value;

	wire [3:0] R, G, B;
	wire hblank, vblank;
	wire hsync, vsync;
	wire [10:0] col;
	wire [9:0] row;

	vga vga
	(
		.clk36m(clk_sys    ),
		.reset (reset      ),
		.clkref(~mem_clkref),
		.col   (col        ),
		.row   (row        ),
		.hsync (hsync      ),
		.vsync (vsync      ),
		.hblank(hblank     ),
		.vblank(vblank     )
	);

	// El teclado va al panel o a la consola: Ctrl+F1 cambia; Ctrl+F2 intercambia panel y consola
	reg terminal_active = 1'b0;
	reg swapped_panels = 1'b0;
	always @(posedge clk_sys) begin
		reg ctrl = 1'b0;

		if (reset == 1'b1) begin
			terminal_active <= 1'b0;
			ctrl <= 1'b0;
		end
		else if (key_strobe == 1'b1) begin
			casez ({ctrl, key_code})
				{1'b1, 8'h05}: if (key_pressed == 1'b1) terminal_active <= ~terminal_active;
				{1'b1, 8'h06}: if (key_pressed == 1'b1) swapped_panels <= ~swapped_panels;
				{1'b?, 8'h14}: ctrl <= key_pressed;
			endcase
		end
	end

	localparam [9:0] PANEL_WIDTH = 10'd800;
	localparam [8:0] PANEL_HEIGHT = 9'd280;
	localparam [8:0] TERMINAL_HEIGHT = 9'd300;

	wire [3:0] r_panel;
	wire [3:0] g_panel;
	wire [3:0] b_panel;

	wire fdc_cpu_ready;
	wire [7:0] disk_leds;

	wire [7:0] terminal_data_out;
	wire [7:0] panel_data_out;
	wire [7:0] fdc_data_out;
	wire [7:0] ram_data_out;
	wire [7:0] portb_serial_bus_data_out;

	wire [15:0] bus_addr;
	wire [7:0] bus_cpu_data_in = panel_ce == 1'b1 ? panel_data_out :
		portb_serial_bus_data_out | terminal_data_out | fdc_data_out | ram_data_out;
	wire [7:0] bus_cpu_data_out;
	wire [7:0] bus_cpu_sysctl;
	wire bus_cpu_wait;
	wire bus_cpu_inte;
	wire bus_cpu_hlda;
	wire bus_cpu_rd;
	wire bus_cpu_wr_n;
	wire bus_cpu_sync;
	wire bus_xrdy;
	wire panel_ce;
	wire panel_we;
	wire [15:0] panel_audio;

	reg [4:0] cnt = 5'd0;
	always @(posedge clk_sys) begin
		if (cnt == 5'd17) cnt <= 5'd0;
		else cnt <= cnt + 1'd1;
	end

	wire f1 = cnt == 5'd0;
	wire f2 = cnt == 5'd9;

	panel panel
	(
		.clk(clk_sys),
		.f1(f1),
		.f2(f2),
		.reset(reset),
		.ready_in(fdc_cpu_ready),

		.col(col),
		.row(swapped_panels ? row - TERMINAL_HEIGHT : row),
		.hblank(hblank),
		.vblank(vblank),
		.ram_addr(vid_ram_addr),
		.ram_value(ram_value),

		.disk_leds(disk_leds),

		.bus_addr(bus_addr),
		.bus_data_in(bus_cpu_data_out),
		.bus_cpu_data_in(bus_cpu_data_in),
		.bus_data_out(panel_data_out),
		.bus_cpu_sysctl(bus_cpu_sysctl),
		.bus_cpu_sync(bus_cpu_sync),
		.bus_cpu_wait(bus_cpu_wait),
		.bus_cpu_inte(bus_cpu_inte),
		.bus_cpu_hlda(bus_cpu_hlda),
		.bus_cpu_rd(bus_cpu_rd),
		.bus_cpu_wr_n(bus_cpu_wr_n),

		.bus_xrdy(bus_xrdy),
		.panel_ce(panel_ce),
		.panel_we(panel_we),

		.key_pressed(key_pressed),
		.key_code(key_code),
		.key_strobe(key_strobe & ~terminal_active),
		.key_extended(key_extended),

		.r(r_panel),
		.g(g_panel),
		.b(b_panel),

		.audio(panel_audio)
	);

	wire pixel_terminal;
	wire [7:0] porta_serial_data;
	wire porta_serial_strobe;
	wire [15:0] terminal_audio;

	terminal #(
		.CARD_ADDR(4'd0),
		.CARD_PORT(2'b01)
	) terminal
	(
		.clk(clk_sys),
		.reset(reset),

		.xpos(col),
		.ypos(swapped_panels ? row : row - PANEL_HEIGHT),
		.hblank(hblank),
		.vblank(vblank),

		.key_pressed(key_pressed),
		.key_code(key_code),
		.key_strobe(key_strobe & terminal_active),
		.key_extended(key_extended),

		.bus_addr(bus_addr),
		.bus_cpu_rd(bus_cpu_rd),
		.bus_cpu_wr_n(bus_cpu_wr_n),
		.bus_cpu_sysctl(bus_cpu_sysctl),
		.bus_data_in(bus_cpu_data_out),
		.bus_data_out(terminal_data_out),
		.flashing_cursor(status[6]),

		.vout(pixel_terminal),
		.audio_out(terminal_audio),

		.serial_echo(porta_serial_data),
		.serial_echo_strobe(porta_serial_strobe)
	);

	cpu cpu_board
	(
		.clk(clk_sys),
		.f1(f1),
		.f2(f2),
		.reset(reset),

		.bus_cpu_xrdy(bus_xrdy),
		.bus_cpu_intr(1'b0),
		.bus_cpu_hold(1'b0),

		.bus_cpu_sync(bus_cpu_sync),
		.bus_cpu_wait(bus_cpu_wait),
		.bus_cpu_inte(bus_cpu_inte),
		.bus_cpu_hlda(bus_cpu_hlda),
		.bus_cpu_rd(bus_cpu_rd),
		.bus_cpu_wr_n(bus_cpu_wr_n),

		.bus_cpu_sysctl(bus_cpu_sysctl),
		.bus_addr(bus_addr),
		.bus_data_out(bus_cpu_data_out),
		.bus_data_in(bus_cpu_data_in)
	);

	// hps_io de MiSTer tiene una LBA y un buffer de entrada por unidad; fdc.sv ya los multiplexa
	wire [31:0] sd_lba_mux;
	wire  [7:0] sd_buff_din_mux;
	assign sd_lba[0] = sd_lba_mux;
	assign sd_lba[1] = sd_lba_mux;
	assign sd_buff_din[0] = sd_buff_din_mux;
	assign sd_buff_din[1] = sd_buff_din_mux;

	fdc fdc_board
	(
		.clk(clk_sys),
		.ce(f1),
		.reset(reset),

		.bus_cpu_sysctl(bus_cpu_sysctl),
		.bus_cpu_wr_n(bus_cpu_wr_n),
		.bus_cpu_rd(bus_cpu_rd),

		.bus_addr(bus_addr),
		.bus_data_in(bus_cpu_data_out),
		.bus_data_out(fdc_data_out),

		.sd_lba_mux(sd_lba_mux),
		.sd_rd(sd_rd),
		.sd_wr(sd_wr),
		.sd_ack(sd_ack),
		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din_mux(sd_buff_din_mux),
		.sd_buff_wr(sd_buff_wr),

		.img_mounted(img_mounted),
		.img_size(img_size),

		.fdc_cpu_ready(fdc_cpu_ready),

		.write_protect(status[3]),

		.disk_leds(disk_leds)
	);

	wire [7:0] portb_serial_data;
	wire portb_serial_strobe;

	sio2 #(
		.CARD_ADDR(4'd0),
		.CARD_PORT(2'b10)
	) serial_port_b
	(
		.clk(clk_sys),
		.reset(reset),
		.bus_cpu_sysctl(bus_cpu_sysctl),
		.bus_cpu_rd(bus_cpu_rd),
		.bus_cpu_wr_n(bus_cpu_wr_n),
		.bus_addr(bus_addr),
		.bus_data_in(bus_cpu_data_out),
		.bus_data_out(portb_serial_bus_data_out),
		.cts(1'b1),
		.rts(1'b1),

		.serial_in(),
		.serial_in_strobe(),
		.serial_out(portb_serial_data),
		.serial_out_strobe(portb_serial_strobe)
	);

	wire [17:0] votrax_audio;
	wire [7:0] votrax_serial_data = status[5] == 1'b1 ? portb_serial_data : porta_serial_data;
	wire votrax_serial_strobe = status[5] == 1'b1 ? portb_serial_strobe : porta_serial_strobe;

	votrax votrax
	(
		.clk36m(clk_sys),
		.clk2m5(clk_2m5),
		.reset(reset),

		.serial_data(votrax_serial_data),
		.serial_strobe(votrax_serial_strobe & status[4]),

		.audio(votrax_audio),
		.audio_valid(),

		.acia_status()
	);

//--- memoria -------------------------------------------------------------------------------------

	// Imagen del panel (en la Calypso, en la SDRAM)
	imsai_panel_ram panel_ram
	(
		.clk    (clk_sys                    ),
		.rd_addr(vid_ram_addr               ),
		.rd_data(ram_value                  ),
		.wr     (ioctl_wr & panel_download  ),
		.wr_addr(ioctl_addr[16:0]           ),
		.wr_data(ioctl_dout                 )
	);

	// RAM de 64K (en la Calypso, en la PSRAM). La ROM del monitor se carga en F800.
	wire ram_rd = bus_cpu_rd == 1'b1 && bus_cpu_sysctl[6] == 1'b0;
	wire ram_we = (bus_cpu_wr_n == 1'b0 && bus_cpu_sysctl[4] == 1'b0) || panel_we == 1'b1;
	wire [7:0] ram_din = panel_we == 1'b1 ? panel_data_out : bus_cpu_data_out;
	wire [7:0] ram_dout;
	assign ram_data_out = ram_rd == 1'b1 ? ram_dout : 8'h00;

	imsai_ram ram
	(
		.clk    (clk_sys                         ),
		.addr   (bus_addr                        ),
		.we     (ram_we                          ),
		.din    (ram_din                         ),
		.dout   (ram_dout                        ),
		.dl     (rom_download                    ),
		.dl_wr  (ioctl_wr                        ),
		.dl_addr({5'b11111, ioctl_addr[10:0]}    ),
		.dl_data(ioctl_dout                      )
	);

//--- video ---------------------------------------------------------------------------------------

	wire [11:0] rgb_t_green    = pixel_terminal == 1'b1 ? 12'h0e0 : 12'h111;
	wire [11:0] rgb_t_white    = pixel_terminal == 1'b1 ? 12'heee : 12'h111;
	wire [11:0] rgb_t_cyan     = pixel_terminal == 1'b1 ? 12'h7ee : 12'h111;
	wire [11:0] rgb_t_amber    = pixel_terminal == 1'b1 ? 12'hfb0 : 12'h111;
	wire [11:0] rgb_t_disabled = pixel_terminal == 1'b1 ? 12'h444 : 12'h111;

	wire [11:0] rgb_terminal = terminal_active ?
		status[2:1] == 2'b00 ? rgb_t_cyan :
		status[2:1] == 2'b01 ? rgb_t_white :
		status[2:1] == 2'b10 ? rgb_t_green :
		rgb_t_amber :
		rgb_t_disabled;

	assign R = swapped_panels ?
		(row < TERMINAL_HEIGHT ? rgb_terminal[11:8] : r_panel) :
		(row < PANEL_HEIGHT ? r_panel : rgb_terminal[11:8]);
	assign G = swapped_panels ?
		(row < TERMINAL_HEIGHT ? rgb_terminal[7:4] : g_panel) :
		(row < PANEL_HEIGHT ? g_panel : rgb_terminal[7:4]);
	assign B = swapped_panels ?
		(row < TERMINAL_HEIGHT ? rgb_terminal[3:0] : b_panel) :
		(row < PANEL_HEIGHT ? b_panel : rgb_terminal[3:0]);

	// Un punto por ciclo de 36 MHz (800x600 a 56 Hz): ya es VGA, no pasa por el scandoubler.
	// Sin correccion de gamma (GAMMA=0): gamma_corr solo avanza en los flancos de subida de
	// ce_pix, y aqui ce_pix esta siempre a 1, asi que con GAMMA=1 se quedaba todo el video parado
	// (pantalla negra con OSD; Quartus quitaba vga.sv entero por 'Lost fanout').
	wire [1:0] ar = status[9:8];
	wire       vga_de;

	assign CLK_VIDEO = clk_sys;
	assign VGA_SL    = 2'd0;

	video_freak video_freak
	(
		.CLK_VIDEO  (CLK_VIDEO  ),
		.CE_PIXEL   (CE_PIXEL   ),
		.VGA_VS     (VGA_VS     ),
		.HDMI_WIDTH (HDMI_WIDTH ),
		.HDMI_HEIGHT(HDMI_HEIGHT),
		.VGA_DE     (VGA_DE     ),
		.VIDEO_ARX  (VIDEO_ARX  ),
		.VIDEO_ARY  (VIDEO_ARY  ),
		.VGA_DE_IN  (vga_de     ),
		.ARX        ((!ar) ? 12'd4 : (ar - 1'd1)),
		.ARY        ((!ar) ? 12'd3 : 12'd0),
		.CROP_SIZE  (12'd0      ),
		.CROP_OFF   (5'd0       ),
		.SCALE      ({1'b0, status[10], 1'b0})
	);

	video_mixer #(.LINE_LENGTH(820), .GAMMA(0)) video_mixer
	(
		.CLK_VIDEO  (CLK_VIDEO  ),
		.CE_PIXEL   (CE_PIXEL   ),
		.ce_pix     (1'b1       ),
		.scandoubler(1'b0       ),
		.hq2x       (1'b0       ),
		.gamma_bus  (gamma_bus  ),
		.R          ({R, R}     ),
		.G          ({G, G}     ),
		.B          ({B, B}     ),
		.HSync      (hsync      ),
		.VSync      (vsync      ),
		.HBlank     (hblank     ),
		.VBlank     (vblank     ),
		.HDMI_FREEZE(1'b0       ),
		.freeze_sync(           ),
		.VGA_R      (VGA_R      ),
		.VGA_G      (VGA_G      ),
		.VGA_B      (VGA_B      ),
		.VGA_VS     (VGA_VS     ),
		.VGA_HS     (VGA_HS     ),
		.VGA_DE     (vga_de     )
	);

//--- audio ---------------------------------------------------------------------------------------

	// La misma mezcla que en la Calypso (alli va al I2S)
	reg [15:0] audio = 16'd0;
	always @(posedge clk_sys)
		audio <= status[4] == 1'b1 ?
			votrax_audio[17:2] + panel_audio + terminal_audio :
			panel_audio + terminal_audio;

	assign AUDIO_S   = 1'b1;
	assign AUDIO_L   = audio;
	assign AUDIO_R   = audio;
	assign AUDIO_MIX = 2'd0;

//--- leds ----------------------------------------------------------------------------------------

	assign LED_USER = ioctl_download | terminal_active;
	assign LED_DISK = {1'b0, (|sd_rd) | (|sd_wr)};

//-------------------------------------------------------------------------------------------------
endmodule

`default_nettype wire
