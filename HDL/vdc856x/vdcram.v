`timescale 1 ps / 1 ps

module vdcram
#(
parameter DATA_WIDTH    = 8,
parameter ADDRESS_WIDTH = 16
)
(
input                           clk,
input                           rd,
input                           we,
input      [ADDRESS_WIDTH-1:0]  addr,
input      [DATA_WIDTH-1:0]     dai,
output     [DATA_WIDTH-1:0]     dao,

// Port B signals
input                           clk_b,
input                           rd_b,
input                           we_b,
input      [ADDRESS_WIDTH-1:0]  addr_b,
input      [DATA_WIDTH-1:0]     dai_b,
output     [DATA_WIDTH-1:0]     dao_b
);

altsyncram	altsyncram_component (
		.address_a (addr),
		.address_b (addr_b),
		.clock0 (clk),
		.clock1 (clk_b),
		.data_a (dai),
		.data_b (dai_b),
		.rden_a (rd),
		.rden_b (rd_b),
		.wren_a (we),
		.wren_b (we_b),
		.q_a (dao),
		.q_b (dao_b),
		.aclr0 (1'b0),
		.aclr1 (1'b0),
		.addressstall_a (1'b0),
		.addressstall_b (1'b0),
		.byteena_a (1'b1),
		.byteena_b (1'b1),
		.clocken0 (1'b1),
		.clocken1 (1'b1),
		.clocken2 (1'b1),
		.clocken3 (1'b1),
		.eccstatus ());

defparam
altsyncram_component.byte_size = 8,
altsyncram_component.clock_enable_input_a = "BYPASS",
altsyncram_component.clock_enable_input_b = "BYPASS",
altsyncram_component.clock_enable_output_a = "BYPASS",
altsyncram_component.clock_enable_output_b = "BYPASS",
altsyncram_component.intended_device_family = "Cyclone V",
altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO,INSTANCE_NAME=VDC",
altsyncram_component.lpm_type = "altsyncram",
altsyncram_component.numwords_a = 2**ADDRESS_WIDTH,
altsyncram_component.numwords_b = 2**ADDRESS_WIDTH,
altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
altsyncram_component.outdata_aclr_a = "NONE",
altsyncram_component.outdata_aclr_b = "NONE",
altsyncram_component.outdata_reg_a = "UNREGISTERED",
altsyncram_component.outdata_reg_b = "UNREGISTERED",
altsyncram_component.power_up_uninitialized = "FALSE",
altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
altsyncram_component.widthad_a = ADDRESS_WIDTH,
altsyncram_component.widthad_b = ADDRESS_WIDTH,
altsyncram_component.width_a = DATA_WIDTH,
altsyncram_component.width_b = DATA_WIDTH;

endmodule
