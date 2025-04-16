// ---------------------------------------------------------------------------------
// Commodore 128 MMU
//
// for the C128 MiSTer FPGA core, by Erik Scheffers
// ---------------------------------------------------------------------------------

module mmu8722 (
    // config
    input sys256k,  // "0" 128k system RAM, "1" 256k system RAM
    input osmode,   // reset state for c128_n: "0" C128, "1" C64
    input cpumode,  // reset state for z80_n: "0" Z80, "1" 8502

    // bus
    input clk,
    input reset,
    input enable,

    input cs_io,  // select IO registers at $D50x
    input cs_lr,  // select Load registers at $FF0x

    input we,

    input [15:0] addr,
    input [7:0] din,
    output reg [7:0] dout,

    // 6529 style bidir pins
    input d4080i,
    output d4080o,
    input exromi,
    output exromo,
    input gamei,
    output gameo,
    input fsdiri,
    output fsdiro,

    // system config
    output reg c128_n,              // "0" C128, "1" C64
    output reg z80_n,               // "0" Z80, "1" 8502
    output reg [1:0] rombank,       // "00" system rom  "01" internal rom "10" external rom "11" ram
    output reg iosel,               // "0" select IO  "1" select rom/ram according to rombank

    // translated address bus
    output reg [15:0] tAddr,
    output reg [1:0] cpuBank,
    output reg [1:0] vicBank
);

    // Internal registers
    reg [7:0] reg_cr;
    reg [7:0] reg_pcr [0:3];
    reg reg_cpu;
    reg reg_fsdir;
    reg reg_exrom;
    reg reg_game;
    reg reg_d4080;
    reg reg_os;
    reg [1:0] reg_unused06;
    reg [1:0] reg_vicbank;
    reg reg_commonH;
    reg reg_commonL;
    reg [1:0] reg_commonSz;

    reg [3:0] reg_p0hb;
    reg [3:0] reg_p0h;
    reg [7:0] reg_p0l;
    reg [3:0] reg_p1hb;
    reg [3:0] reg_p1h;
    reg [7:0] reg_p1l;

    // Internal signals
    wire fsdir;
    wire exrom;
    wire game;
    wire d4080;

    wire [15:8] page;
    wire [1:0] systemMask;
    wire [7:0] commonPageMask;
    wire [15:8] commonPage;
    wire [1:0] cpuMask;
    wire [3:0] crBank;

    // Assign outputs
    assign d4080 = d4080i & reg_d4080;
    assign d4080o = d4080;
    assign game = gamei & reg_game;
    assign gameo = game;
    assign exrom = exromi & reg_exrom;
    assign exromo = exrom;
    assign fsdir = fsdiri & reg_fsdir;
    assign fsdiro = fsdir;

    // System mask calculation
    assign systemMask = {sys256k, 1'b1};

    // Common page mask calculation
    assign commonPageMask = (reg_commonSz == 2'b00) ? 8'b11111100 :  // 00..03 / FC..FF = 1k
                           (reg_commonSz == 2'b01) ? 8'b11110000 :  // 00..0F / F0..FF = 4k
                           (reg_commonSz == 2'b10) ? 8'b11100000 :  // 00..1F / E0..FF = 8k
                           8'b11000000;                             // 00..3F / C0..FF =16k

    assign page = addr[15:8];
    assign commonPage = page & commonPageMask;
    assign cpuMask = ((reg_commonH && (commonPage == commonPageMask)) ||
                     (reg_commonL && (commonPage == 8'h00))) ? 2'b00 : systemMask;
    assign crBank = {2'b00, reg_cr[7:6]} & {2'b00, cpuMask};

    // Write registers
    always @(posedge clk) begin
        if (reset) begin
            reg_pcr[0] <= 8'h00;
            reg_pcr[1] <= 8'h00;
            reg_pcr[2] <= 8'h00;
            reg_pcr[3] <= 8'h00;
            reg_cr <= 8'h00;
            reg_cpu <= 1'b0;  // Default to Z80 mode
            reg_fsdir <= 1'b0;
            reg_exrom <= 1'b0;
            reg_game <= 1'b0;
            reg_d4080 <= 1'b0;
            reg_os <= 1'b0;   // Default to C128 mode
            reg_unused06 <= 2'b00;
            reg_vicbank <= 2'b00;
            reg_commonH <= 1'b0;
            reg_commonL <= 1'b0;
            reg_commonSz <= 2'b00;
            reg_p0hb <= 4'h0;
            reg_p0h <= 4'h0;
            reg_p0l <= 8'h00;
            reg_p1hb <= 4'h0;
            reg_p1h <= 4'h0;
            reg_p1l <= 8'h01;
        end else if (we && enable) begin
            if (cs_lr) begin
                case (addr[2:0])
                    3'b000: reg_cr <= din;
                    3'b001: reg_cr <= reg_pcr[0];
                    3'b010: reg_cr <= reg_pcr[1];
                    3'b011: reg_cr <= reg_pcr[2];
                    3'b100: reg_cr <= reg_pcr[3];
                endcase
            end else if (cs_io) begin
                case (addr[7:0])
                    8'h00: reg_cr <= din;
                    8'h01: reg_pcr[0] <= din;
                    8'h02: reg_pcr[1] <= din;
                    8'h03: reg_pcr[2] <= din;
                    8'h04: reg_pcr[3] <= din;
                    8'h05: begin
                        reg_cpu <= din[0];
                        reg_fsdir <= din[3];
                        reg_game <= din[4];
                        reg_exrom <= din[5];
                        reg_os <= din[6];
                        reg_d4080 <= din[7];
                    end
                    8'h06: begin
                        reg_commonSz <= din[1:0];
                        reg_commonL <= din[2];
                        reg_commonH <= din[3];
                        reg_unused06 <= din[5:4];
                        reg_vicbank <= din[7:6];
                    end
                    8'h07: begin
                        reg_p0l <= din;
                        reg_p0h <= reg_p0hb;
                    end
                    8'h08: reg_p0hb <= din[3:0];
                    8'h09: begin
                        reg_p1l <= din;
                        reg_p1h <= reg_p1hb;
                    end
                    8'h0A: reg_p1hb <= din[3:0];
                endcase
            end
        end
    end

    // Address translation
    always @(*) begin
        reg [1:0] bank;
        reg [15:8] tPage;

        bank = crBank[1:0];
        tPage = page;

        if (reg_cr[7:6] == 2'b00 && addr[15:12] == 4'h0 && reg_cpu == 1'b0 && we == 1'b0) begin
            // When reading from $00xxx in Z80 mode, translate to $0Dxxx. Buslogic will enable ROM
            bank = 2'b00;
            tPage = {4'hD, page[11:8]};
        end else if (page == 8'h01 && reg_os == 1'b0) begin
            bank = reg_p1h[1:0] & cpuMask;
            tPage = reg_p1l;
        end else if (page == 8'h00 && reg_os == 1'b0) begin
            bank = reg_p0h[1:0] & cpuMask;
            tPage = reg_p0l;
        end else if (crBank == reg_p1h && page == reg_p1l) begin
            bank = reg_p1h[1:0] & cpuMask;
            tPage = 8'h01;
        end else if (crBank == reg_p0h && page == reg_p0l) begin
            bank = reg_p0h[1:0] & cpuMask;
            tPage = 8'h00;
        end

        cpuBank = bank;

        case (addr[15:14])
            2'b11: rombank = reg_cr[5:4];
            2'b10: rombank = reg_cr[3:2];
            2'b01: rombank = {reg_cr[1], reg_cr[1]};
            2'b00: rombank = reg_cr[7:6];
        endcase

        tAddr = {tPage, addr[7:0]};
    end

    // Read registers
    always @(posedge clk) begin
        if (!we && (cs_io || cs_lr)) begin
            case (addr[7:0])
                8'h00: dout = reg_cr;       // mmu configuration register
                /*
                    bit 0:   $D000-DFFF, 0=IO , 1= as per bit 4 & 5
                    bit 1:   $4000-7FFF, 0=BASIC LO, 1=RAM bank as specified by bit 6&7
                    bit 2,3: $8000-BFFF, 00=BASIC HI ($8000-$AFFF) + Monitor ($8000-BFFF)
                                         01=Internal function rom ($8000-$BFFF)
                                         10=External function rom ($8000-$BFFF)
                                         11=RAM bank as specified by bit 6&7
                    bit 4,5: $C000-FFFF, 00=Screen editor ($C000-$CFFF), character rom ($D000-$DFFF), Kernal ($D000-$FFFF)
                                         01=Internal function rom ($C000-$DFFF)
                                         10=External function rom ($C000-$DFFF)
                                         11=RAM bank as specified by bit 6&7
                    bit 6,7: $0000-FFFF, 00=RAM bank 0
                                         01=RAM bank 1
                                         10=RAM bank 2
                                         11=RAM bank 3
                */
                8'h01: dout = reg_pcr[0];
                8'h02: dout = reg_pcr[1];
                8'h03: dout = reg_pcr[2];
                8'h04: dout = reg_pcr[3];
                8'h05: dout = {d4080, reg_os, exrom, game, fsdir, 2'b11, reg_cpu}; // 4080 key, C128/C64 rom, exrom, game, fsdir, 2'b11, cpu mode z80/8502
                8'h06: dout = {reg_vicbank, reg_unused06, reg_commonH, reg_commonL, reg_commonSz}; // common ram config
                8'h07: dout = reg_p0l;                  // zero page relocation low byte
                8'h08: dout = {4'hF, reg_p0h};          // zero page relocation high byte (bank bits)
                8'h09: dout = reg_p1l;                  // stack relocation low byte
                8'h0A: dout = {4'hF, reg_p1h};          // stack relocation high byte (bank bits)
                8'h0B: dout = {1'b0, sys256k, ~sys256k, 5'b00000}; // mmu8722 version and system ram size
                default: dout = 8'hFF;
            endcase
        end
    end

    // System outputs
    always @(*) begin
        vicBank = reg_vicbank & systemMask;
        c128_n = reg_os;
        z80_n = reg_cpu;
        iosel = reg_cr[0];
    end

endmodule