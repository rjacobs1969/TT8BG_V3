/********************************************************************************
 * Commodore 128 VDC
 *
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 * Extended for TT8BG V3 core by Robin Jacobs
 ********************************************************************************/

module vdc_top #(
	parameter RAM_ADDR_BITS = 16,
	parameter C_LATCH_WIDTH = 8,
	parameter S_LATCH_WIDTH = 82
)(
	input          version,   // 0=8563R9, 1=8568
	input          ram64k,    // 0=16K RAM, 1=64K RAM
	input          initRam,   // 1=initialize RAM on reset
	input          debug,     // 1=enable debug video output

	input          clk,		  // 32Mhz
	input          clk_b,     // Port B clock (CPU clock for direct ram access)
	input          enableBus,
	input          reset,
	input          init,

	input          cs,        // chip select
	input          we,        // write enable
	input    [7:0] db_in,     // data in
	output   [7:0] db_out,    // data out

	input          lp_n,      // light pen

	output         vsync,
	output         hsync,

	output  [3:0]   rgbi,

	// RBG output for TT8BG
	output [7:0] red_out,
	output [7:0] green_out,
	output [7:0] blue_out,


	// Extension for TT8BG:
	// - Ram is directly accessible by the CPU (changed to dual port RAM)
	// - registers R2-Rxx.. are directly accessible by the CPU at address $D602-$D6xx when IO is enabled and the tt8bg mode is enabled
	// - R38 is used to enable/disable the tt8bg mode, set to $74 to enable
	// - R39-R42 are read-only and provide the current column, pixel, row and line within the character cell respectively
	// - R43/R44 are used to generate a raster interrupt at a specific character line and sub scanline
	// - R64 RED value is used to set the color0
	// - R65 RED value is used to set the color1
	// - R66 RED value is used to set the color2
	//....
	// - R80 GREEN value is used to set the color0
	// - R81 GREEN value is used to set the color1
	// - R82 GREEN value is used to set the color2
	//....
	// - R96 BLUE value is used to set the color0
	// - R97 BLUE value is used to set the color1
	// - R98 BLUE value is used to set the color2
	//....
	// - R111 BLUE value is used to set the color15
	input          rd_b,
	input          we_b,
	input   [6:0]  direct_reg,
	input  [15:0]  addr_b,
	input   [7:0]  dai_b,
	output  [7:0]  dao_b,
	output 		   vcd_irq
);

reg enable;
always @(posedge clk) begin
	reg [1:0] clkdiv = 0;

	clkdiv <= clkdiv + 1'd1;
	enable <= ~(reg_dbl & clkdiv[1]) & clkdiv[0];
end

// Register file

                            // Reg      Init value   Description
reg   [7:0] reg_ht;         // R0      7E/7F 126/127 Horizontal total (minus 1) [126 for original ROM, 127 for PAL on DCR]
reg   [7:0] reg_hd;         // R1         50 80      Horizontal displayed
reg   [7:0] reg_hp;         // R2         66 102     Horizontal sync position
reg   [3:0] reg_vw;         // R3[7:4]     4 4       Vertical sync width
reg   [3:0] reg_hw;         // R3[3:0]     9 9       Horizontal sync width (plus 1)
reg   [7:0] reg_vt;         // R4      20/27 32/39   Vertical total (minus 1) [32 for NTSC, 39 for PAL]
reg   [4:0] reg_va;         // R5         00 0       Vertical total adjust
reg   [7:0] reg_vd;         // R6         19 25      Vertical displayed
reg   [7:0] reg_vp;         // R7      1D/20 29/32   Vertical sync position (plus 1) [29 for NTSC, 32 for PAL]
reg   [1:0] reg_im;         // R8          0 off     Interlace mode
reg   [4:0] reg_ctv;        // R9         07 7       Character Total Vertical (minus 1)
reg   [1:0] reg_cm;         // R10[6:5]    1 none    Cursor mode
reg   [4:0] reg_cs;         // R10[4:0]    0 0       Cursor scanline start
reg   [4:0] reg_ce;         // R11        07 7       Cursor scanline end (plus 1?)
reg  [15:0] reg_ds;         // R12/R13  0000 0000    Display start
reg  [15:0] reg_cp;         // R14/R15  0000 0000    Cursor position
reg   [7:0] reg_lpv;        // R16                   Light pen V position
reg   [7:0] reg_lph;        // R17                   Light pen H position
reg  [15:0] reg_ua;         // R18/R19       -       Update address
reg  [15:0] reg_aa;         // R20/R21  0800 0800    Attribute start address
reg   [3:0] reg_cth;        // R22[7:4]    7 7       Character total horizontal (minus 1)
reg   [3:0] reg_cdh;        // R22[3:0]    8 8       Character displayed horizontal (plus 1 in double width mode)
reg   [4:0] reg_cdv;        // R23        08 8       Character displayed vertical (minus 1)
reg         reg_copy;       // R24[7]      0 off     Block copy mode
reg         reg_rvs;        // R24[6]      0 off     Reverse screen
reg         reg_cbrate;     // R24[5]      1 1/30    Character blink rate
reg   [4:0] reg_vss;        // R24[4:0]   00 0       Vertical smooth scroll
reg         reg_text;       // R25[7]      0 text    Mode select (0=text/1=bitmap)
reg         reg_atr;        // R25[6]      1 on      Attribute enable
reg         reg_semi;       // R25[5]      0 off     Semi-graphic mode
reg         reg_dbl;        // R25[4]      0 off     Pixel double width
reg   [3:0] reg_hss;        // R25[3:0]  0/7 0/7     Smooth horizontal scroll [0 for v0, 7 for v1]
reg   [3:0] reg_fg;         // R26[7:4]    F white   Foreground RGBI
reg   [3:0] reg_bg;         // R26[3:0]    0 black   Background RGBI
reg   [7:0] reg_ai;         // R27        00 0       Address increment per row
reg   [2:0] reg_cb;         // R28[7:5]    1 2000    Character set start address
reg         reg_ram;        // R28[4]      0 4416    RAM type (0=16k accessible, 1=64k accessible)
reg   [4:0] reg_ul;         // R29        07 7       Underline scan line
reg   [7:0] reg_wc;         // R30                   Word count
reg   [7:0] reg_da;         // R31                   Data (in)
reg  [15:0] reg_ba;         // R32/R33               Block copy source address
reg   [7:0] reg_deb;        // R34        7D 125     Display enable begin
reg   [7:0] reg_dee;        // R35        64 100     Display enable end
reg   [3:0] reg_drr;        // R36         5 5       Ram refresh/scan line
reg         reg_hspol = 0;  // R37[7]                [v2 only], HSYnc polarity
reg         reg_vspol = 0;  // R37[6]                [v2 only], VSYnc polarity
// --------------------------
// TT8BG extension registers:
// --------------------------
reg         reg_tt8bg = 0;  // R38                   [v2 only], TT8BG mode (0=normal, 1=TT8BG extension enabled)
//                          // R39 read-only current column (0-255)
//                          // R40 read-only current pixel within the character cell (0-7)
//                          // R41 read-only current row (0-127)
//                          // R42 read-only current line within the character cell (0-31)
reg [15:0] rasterInterupt_reg;  // R43/R44  Generate raster interrupt at character line (R43), character scanline (R44)
reg [15:0] columnInterupt_reg;  // R45/R46  Generate column interrupt at character column (R45), pixel column (R46)
reg [7:0] red [0:15];       // R64-R79
reg [7:0] green [0:15];     // R80-R95
reg [7:0] blue [0:15];      // R96-R111


reg   [6:0] regSel;         // selected internal register (write to $D600)

wire        fetchFrame;
wire        fetchLine;
wire        fetchRow, lastRow;
wire        cursorV;
wire        newCol, endCol;
wire        rowbuf;

reg   [7:0] col, row;     // current column and row
reg   [3:0] pixel;		  // current pixel (0-7) in the character cell
reg   [4:0] line;		  // current line (0-31) in the character cell
reg   [1:0] blink;        // The 2 blink rates: 0=16 frames, 1=30 frames

reg  [15:0] dispaddr;

(* ramstyle = "no_rw_check" *) reg [7:0] scrnbuf[2][S_LATCH_WIDTH];
(* ramstyle = "no_rw_check" *) reg [7:0] attrbuf[2][S_LATCH_WIDTH];
(* ramstyle = "no_rw_check" *) reg [7:0] charbuf[C_LATCH_WIDTH];

reg         lpStatus;
wire        vsync_pos;
wire	    hsync_pos;
wire        busy;
wire  		hVisible, vVisible, hdispen;
wire        vcd_irq_vertical;
wire        vcd_irq_horizontal;

assign      vsync = vsync_pos ^ (~version & reg_vspol);
assign      hsync = hsync_pos ^ (~version & reg_hspol);
assign 		red_out = red[rgbi];
assign 		green_out = green[rgbi];
assign 		blue_out = blue[rgbi];
// VCD IRQ (tt8bg mode only)
// R43 has value row, R44 has value line
// R45 has value column, R46 has value pixel
// if only one of the rasterInterupt_reg or columnInterupt_reg is set, then the vcd_irq is set to the OR of the two
// if both are set, then the vcd_irq is set to the AND of the two
assign 		vcd_irq_vertical = reg_tt8bg && (row == rasterInterupt_reg[15:8]) && (line == rasterInterupt_reg[4:0]);
assign 		vcd_irq_horizontal = reg_tt8bg && (col == columnInterupt_reg[15:8]) && (pixel == columnInterupt_reg[3:0]);
assign 		vcd_irq = ((rasterInterupt_reg == 16'hffff) || (columnInterupt_reg == 16'hffff)) ? (vcd_irq_vertical || vcd_irq_horizontal) : (vcd_irq_vertical && vcd_irq_horizontal);

wire rs = (direct_reg == 6'h00) ? 1'b0 : 1'b1; // rs is now an internal signal, when direct-reg == 0 then rs is 0, otherwise it's 1
// Select the correct register for the case statement. either the internal register or the direct register depending on the tt8bg mode
wire [6:0] case_sel = (direct_reg == 6'h01 || !reg_tt8bg) ? {1'b0, regSel[5:0]} : direct_reg;

vdc_signals signals (
	.clk(clk),
	.reset(reset || init),
	.enable(enable),

	.db_in(db_in),

	.reg_ht(reg_ht),
	.reg_hd(reg_hd),
	.reg_hp(reg_hp),
	.reg_vw(reg_vw),
	.reg_hw(reg_hw),
	.reg_vt(reg_vt),
	.reg_va(reg_va),
	.reg_vd(reg_vd),
	.reg_vp(reg_vp),
	.reg_im(reg_im),
	.reg_ctv(reg_ctv),
	.reg_cs(reg_cs),
	.reg_ce(reg_ce),
	.reg_cth(reg_cth),
	.reg_vss(reg_vss),
	.reg_text(reg_text),
	.reg_atr(reg_atr),
	.reg_dbl(reg_dbl),
	.reg_ai(reg_ai),
	.reg_deb(reg_deb),
	.reg_dee(reg_dee),

	.fetchFrame(fetchFrame),
	.fetchLine(fetchLine),
	.fetchRow(fetchRow),
	.cursorV(cursorV),
	.lastRow(lastRow),
	.newCol(newCol),
	.endCol(endCol),

	.col(col),
	.row(row),
	.pixel(pixel),
	.line(line),

	.hVisible(hVisible),
	.vVisible(vVisible),
	.hdispen(hdispen),
	.blink(blink),

	.vsync(vsync_pos),
	.hsync(hsync_pos)
);

vdc_ramiface #(
	.RAM_ADDR_BITS(RAM_ADDR_BITS),
	.S_LATCH_WIDTH(S_LATCH_WIDTH),
	.C_LATCH_WIDTH(C_LATCH_WIDTH)
) ram (
	.ram64k(ram64k),
	.initRam(initRam),
	.debug(debug),

	.clk(clk),
	.clk_b(clk_b),
	.reset(reset),
	.enable(enable),

	.regA(case_sel[5:0]),
	.db_in(db_in),
	.enableBus(enableBus),
	.cs(cs),
	.rs(rs),
	.we(we),

	.reg_ht(reg_ht),
	.reg_hd(reg_hd),
	.reg_ai(reg_ai),
	.reg_copy(reg_copy),
	.reg_ram(reg_ram),
	.reg_atr(reg_atr),
	.reg_text(reg_text),
	.reg_ctv(reg_ctv),
	.reg_ds(reg_ds),
	.reg_aa(reg_aa),
	.reg_cb(reg_cb),
	.reg_drr(reg_drr),

	.reg_ua(reg_ua),
	.reg_wc(reg_wc),
	.reg_da(reg_da),
	.reg_ba(reg_ba),

	.fetchFrame(fetchFrame),
	.fetchLine(fetchLine),
	.fetchRow(fetchRow),
	.lastRow(lastRow),
	.newCol(newCol),
	.endCol(endCol),
	.col(col),
	.line(line),

	.busy(busy),
	.rowbuf(rowbuf),
	.attrbuf(attrbuf),
	.charbuf(charbuf),
	.dispaddr(dispaddr),

	// Port B signals
	.rd_b(rd_b),
	.we_b(we_b),
	.addr_b(addr_b),
	.dai_b(dai_b),
	.dao_b(dao_b)
);

vdc_video #(
	.S_LATCH_WIDTH(S_LATCH_WIDTH),
	.C_LATCH_WIDTH(C_LATCH_WIDTH)
) video (
	.debug(debug),

	.clk(clk),
	.reset(reset),
	.enable(enable),

	.reg_hd(reg_hd),
	.reg_cth(reg_cth),
	.reg_cdh(reg_cdh),
	.reg_cdv(reg_cdv),
	.reg_hss(reg_hss),

	.reg_ul(reg_ul),
	.reg_cbrate(reg_cbrate),
	.reg_text(reg_text),
	.reg_atr(reg_atr),
	.reg_semi(reg_semi),
	.reg_dbl(reg_dbl),
	.reg_rvs(reg_rvs),
	.reg_fg(reg_fg),
	.reg_bg(reg_bg),

	.reg_cm(reg_cm),
	.reg_cp(reg_cp),

	.fetchFrame(fetchFrame),
	.fetchLine(fetchLine),
	.fetchRow(fetchRow),
	.cursorV(cursorV),

	.hVisible(hVisible),
	.vVisible(vVisible),
	.hdispen(hdispen),
	.blink(blink),
	.rowbuf(rowbuf),
	.col(col),
	.pixel(pixel),
	.line(line),
	.attrbuf(attrbuf),
	.charbuf(charbuf),
	.dispaddr(dispaddr),

	.rgbi(rgbi)
);

// Registers
always @(posedge clk) begin
	reg lp_n0;

	if (reset) begin
		regSel <= 0;

		// Initialize color arrays using for loop
		for (integer i = 0; i < 16; i = i + 1) begin
			case (i)
				0: begin red[i] <= 8'h00; green[i] <= 8'h00; blue[i] <= 8'h00; end  // Black
				1: begin red[i] <= 8'h55; green[i] <= 8'h55; blue[i] <= 8'h55; end  // Dark gray
				2: begin red[i] <= 8'h00; green[i] <= 8'h00; blue[i] <= 8'h7f; end  // Dark Blue
				3: begin red[i] <= 8'h00; green[i] <= 8'h00; blue[i] <= 8'hff; end  // Blue
				4: begin red[i] <= 8'h00; green[i] <= 8'h7f; blue[i] <= 8'h00; end  // Dark Green
				5: begin red[i] <= 8'h00; green[i] <= 8'hff; blue[i] <= 8'h00; end  // Green
				6: begin red[i] <= 8'h00; green[i] <= 8'h7f; blue[i] <= 8'h7f; end  // Dark Cyan
				7: begin red[i] <= 8'h00; green[i] <= 8'hff; blue[i] <= 8'hff; end  // Cyan
				8: begin red[i] <= 8'h7f; green[i] <= 8'h00; blue[i] <= 8'h00; end  // Dark Red
				9: begin red[i] <= 8'hff; green[i] <= 8'h00; blue[i] <= 8'h00; end  // Red
				10: begin red[i] <= 8'h3f; green[i] <= 8'h00; blue[i] <= 8'h3f; end // Dark Magenta
				11: begin red[i] <= 8'hff; green[i] <= 8'h00; blue[i] <= 8'hff; end // Magenta
				12: begin red[i] <= 8'h3f; green[i] <= 8'h3f; blue[i] <= 8'h00; end // Dark Yellow
				13: begin red[i] <= 8'hff; green[i] <= 8'hff; blue[i] <= 8'h00; end // Yellow
				14: begin red[i] <= 8'haa; green[i] <= 8'haa; blue[i] <= 8'haa; end // Light Gray
				15: begin red[i] <= 8'hff; green[i] <= 8'hff; blue[i] <= 8'hff; end // White
			endcase
		end

		reg_ht <= 0;
		reg_hd <= 0;
		reg_hp <= 0;
		reg_vw <= 0;
		reg_hw <= 0;
		reg_vt <= 0;
		reg_va <= 0;
		reg_vd <= 0;
		reg_vp <= 0;
		reg_im <= 0;
		reg_ctv <= 0;
		reg_cm <= 0;
		reg_cs <= 0;
		reg_ce <= 0;
		reg_ds <= 0;
		reg_cp <= 0;
		reg_lpv <= 0;
		reg_lph <= 0;
		reg_aa <= 0;
		reg_cth <= 0;
		reg_cdh <= 0;
		reg_cdv <= 0;
		reg_copy <= 0;
		reg_rvs <= 0;
		reg_cbrate <= 0;
		reg_vss <= 0;
		reg_text <= 0;
		reg_atr <= 0;
		reg_semi <= 0;
		reg_dbl <= 0;
		reg_hss <= 0;
		reg_fg <= 0;
		reg_bg <= 0;
		reg_ai <= 0;
		reg_cb <= 0;
		reg_ram <= 0;
		reg_ul <= 0;
		reg_deb <= 0;
		reg_dee <= 0;
		reg_drr <= 0;
		reg_hspol <= 0;
		reg_vspol <= 0;
		reg_tt8bg <= 0;
		rasterInterupt_reg <= 16'hffff;
		columnInterupt_reg <= 16'hffff;
		lp_n0 <= 0;
	end
	else if (cs)
		if (we) begin
			if (enableBus) begin
				if (direct_reg == 6'h00)
					regSel <= {1'b0, db_in[5:0]};
				else
					case (case_sel)
						0: reg_ht       <= db_in;
						1: reg_hd       <= db_in;
						2: reg_hp       <= db_in;
						3: begin
								reg_vw    <= db_in[7:4];
								reg_hw    <= db_in[3:0];
							end
						4: reg_vt       <= db_in;
						5: reg_va       <= db_in[4:0];
						6: reg_vd       <= db_in;
						7: reg_vp       <= db_in;
						8: reg_im       <= db_in[1:0];
						9: reg_ctv      <= db_in[4:0];
						10: begin
								reg_cm     <= db_in[6:5];
								reg_cs     <= db_in[4:0];
							end
						11: reg_ce       <= db_in[4:0];
						12: reg_ds[15:8] <= db_in;
						13: reg_ds[7:0]  <= db_in;
						14: reg_cp[15:8] <= db_in;
						15: reg_cp[7:0]  <= db_in;
						// R16-R17 are read-only
						// writes to R18-R19 are handled by vdc_ramiface
						20: reg_aa[15:8] <= db_in;
						21: reg_aa[7:0]  <= db_in;
						22: begin
								reg_cth    <= db_in[7:4];
								reg_cdh    <= db_in[3:0];
							end
						23: reg_cdv      <= db_in[4:0];
						24: begin
								reg_copy   <= db_in[7];
								reg_rvs    <= db_in[6];
								reg_cbrate <= db_in[5];
								reg_vss    <= db_in[4:0];
							end
						25: begin
								reg_text   <= db_in[7];
								reg_atr    <= db_in[6];
								reg_semi   <= db_in[5];
								reg_dbl    <= db_in[4];
								reg_hss    <= db_in[3:0];
							end
						26: begin
								reg_fg     <= db_in[7:4];
								reg_bg     <= db_in[3:0];
							end
						27: reg_ai       <= db_in;
						28: begin
								reg_cb     <= db_in[7:5];
								reg_ram    <= db_in[4];
							end
						29: reg_ul       <= db_in[4:0];
						// writes to R30-R33 are handled by vdc_ramiface
						34: reg_deb      <= db_in;
						35: reg_dee      <= db_in;
						36: reg_drr      <= db_in[3:0];
						// R37 only exists in 8568
						37: if (version) begin
								reg_hspol  <= db_in[7];
								reg_vspol  <= db_in[6];
							end
						38: if (version) begin
								reg_tt8bg  <= (db_in == 8'h74) ? 1'b1 : 1'b0;
							end
						43: rasterInterupt_reg[15:8] <= db_in;
						44: rasterInterupt_reg[7:0] <= db_in;
						45: columnInterupt_reg[15:8] <= db_in;
						46: columnInterupt_reg[7:0] <= db_in;
						64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79: red[case_sel - 64] <= db_in;
						80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95: green[case_sel - 80] <= db_in;
						96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111: blue[case_sel - 96] <= db_in;

					endcase
			end
		end
		else begin
			if (direct_reg == 6'h00)
				db_out <= {~busy, lpStatus, ~vVisible, 3'b000, version, ~version};
			else
				case (case_sel)
					 0: db_out <= reg_ht;
					 1: db_out <= reg_hd;
					 2: db_out <= reg_hp;
					 3: db_out <= {reg_vw, reg_hw};
					 4: db_out <= reg_vt;
					 5: db_out <= {3'b111, reg_va};
					 6: db_out <= reg_vd;
					 7: db_out <= reg_vp;
					 8: db_out <= {6'b111111, reg_im};
					 9: db_out <= {3'b111, reg_ctv};
					10: db_out <= {1'b1, reg_cm, reg_cs};
					11: db_out <= {3'b111, reg_ce};
					12: db_out <= reg_ds[15:8];
					13: db_out <= reg_ds[7:0];
					14: db_out <= reg_cp[15:8];
					15: db_out <= reg_cp[7:0];
					16: begin db_out <= reg_lpv; if (enableBus) lpStatus <= 0; end
					17: begin db_out <= reg_lph; if (enableBus) lpStatus <= 0; end
					18: db_out <= reg_ua[15:8];
					19: db_out <= reg_ua[7:0];
					20: db_out <= reg_aa[15:8];
					21: db_out <= reg_aa[7:0];
					22: db_out <= {reg_cth, reg_cdh};
					23: db_out <= {3'b111, reg_cdv};
					24: db_out <= {reg_copy, reg_rvs, reg_cbrate, reg_vss};
					25: db_out <= {reg_text, reg_atr, reg_semi, reg_dbl, reg_hss};
					26: db_out <= {reg_fg, reg_bg};
					27: db_out <= reg_ai;
					28: db_out <= {reg_cb, reg_ram, 4'b1111};
					29: db_out <= {3'b111, reg_ul};
					30: db_out <= reg_wc;
					31: db_out <= reg_da;
					32: db_out <= reg_ba[15:8];
					33: db_out <= reg_ba[7:0];
					34: db_out <= reg_deb;
					35: db_out <= reg_dee;
					36: db_out <= {4'b1111, reg_drr};
					37: db_out <= {reg_hspol|~version, reg_vspol|~version, 6'b111111};
					38: db_out <= (reg_tt8bg) ? reg_tt8bg : 8'b11111111;
                    39: db_out <= (reg_tt8bg) ? col : 8'b11111111;                // current column (0-255)
                    40: db_out <= (reg_tt8bg) ? {4'b0000, pixel} : 8'b11111111 ;  // current pixel (0-7)
                    41: db_out <= (reg_tt8bg) ? row : 8'b11111111;                // current row (0-127)
                    42: db_out <= (reg_tt8bg) ? {3'b000, line} : 8'b11111111;     // current line (0-31)
					43: db_out <= (reg_tt8bg) ? rasterInterupt_reg[15:8] : 8'b11111111;
					44: db_out <= (reg_tt8bg) ? rasterInterupt_reg[7:0]  : 8'b11111111;
					45: db_out <= (reg_tt8bg) ? columnInterupt_reg[15:8] : 8'b11111111;
					46: db_out <= (reg_tt8bg) ? columnInterupt_reg[7:0]  : 8'b11111111;
					64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79: db_out <= red[case_sel - 64];
					80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95: db_out <= green[case_sel - 80];
					96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111: db_out <= blue[case_sel - 96];


					default: db_out <= 8'b11111111;
				endcase
		end

	// Light pen
	lp_n0 <= lp_n;
	if (~lp_n0 && lp_n && ~lpStatus) begin
		reg_lph <= col;
		reg_lpv <= row;
		lpStatus <= 1;
	end
end



endmodule