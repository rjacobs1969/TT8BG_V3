module HardCPUInterface (
    // Input signals
    input wire clk,                  // FPGA-generated clock signal
    input wire internal_reset,       // Internal active-high reset signal for FPGA logic
    input wire [15:0] address,       // Address bus (always input)
    input wire rw,                   // Read/Write signal from CPU
    input wire vp,                   // Vector Pull signal from CPU
    input wire emulate_6502,         // Emulate 6502 mode
    inout wire [7:0] data,           // Data bus (bidirectional)

    // Output signals
    output wire phi2,                // Phi2 signal from FPGA
    output reg reset,                // Active-low reset signal to CPU
    output reg irq, nmi, abt,        // Active-low interrupt signals to CPU (default to 1)
    output reg _re,                  // Read enable (active low)
    output reg _we,                  // Write enable (active low)
    output reg [7:0] bank_addr,      // Latched bank address
    output reg [7:0] internal_data_bus // Internal data bus output
);

    // Internal signals
    reg [7:0] data_out;              // Data output register
    reg data_dir;                    // Direction control: 1 = output to CPU, 0 = input from CPU
    reg [7:0] reset_counter;         // Counter to track 255 clock cycles

    // Continuous assignments
    assign data = data_dir ? data_out : 8'bz;  // Tri-state logic for bidirectional data bus
    assign phi2 = clk;                          // Phi2 is same as clock

    // Reset and interrupt handling
    always @(posedge clk or posedge internal_reset) begin
        if (internal_reset) begin
            reset <= 1'b0;                      // Assert reset (active-low)
            reset_counter <= 8'd255;            // Load counter with 255
            irq <= 1'b1;                        // Default inactive
            nmi <= 1'b1;                        // Default inactive
            abt <= 1'b1;                        // Default inactive
            internal_data_bus <= 8'b0;          // Reset internal data bus
        end else if (reset_counter > 0) begin
            reset_counter <= reset_counter - 1; // Decrement counter
        end else begin
            reset <= 1'b1;                      // Deassert reset (inactive)
        end
    end

    // Bank address latching
    always @(posedge clk or posedge internal_reset) begin
        if (internal_reset) begin
            bank_addr <= 8'b0;                  // Reset bank address
        end else if (!clk) begin
            bank_addr <= data;                  // Latch bank address
        end
    end

    // Read/Write control and data handling
    always @(posedge clk or posedge internal_reset) begin
        if (internal_reset) begin
            data_out <= 8'b0;                   // Reset data output
            data_dir <= 0;                      // Default to input mode
            _re <= 1;                           // Read disabled
            _we <= 1;                           // Write disabled
        end else if (rw && clk) begin           // Read operation
            data_dir <= 1;                      // Output mode: CPU reads from FPGA
            data_out <= 8'hEA;                  // Placeholder data to CPU (NOP)
            _re <= 0;                           // Read enabled
            _we <= 1;                           // Write disabled
        end else if (!rw && clk) begin          // Write operation
            data_dir <= 0;                      // Input mode: CPU writes to FPGA
            internal_data_bus <= data;          // Capture input data on internal bus
            _re <= 1;                           // Read disabled
            _we <= 0;                           // Write enabled
        end
    end

endmodule