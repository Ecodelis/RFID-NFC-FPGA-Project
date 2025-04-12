// File: Clock_Divider.sv
// Description: 	Clock divider module for generating a slower clock signal
//	
// Author: Marcus Fu
// Date: 2024-04-11

module i2c_master #(
    parameter FPGA_FREQ = 50_000_000, // Default FPGA clock: 50 MHz
    parameter REQ_FREQ = 100_000          // Required Frequency: 100 kHz   
)( // Default SCL: 100kHz for a 50 MHz clock
    input logic clk_in,         // Clock input
    input logic reset_n,        // Active-low Reset
    output logic clk_out        // New clock output
);

// Precompute the clock divider using parameters
localparam int CLK_DIV = FPGA_FREQ / REQ_FREQ ; // Computed at synthesis time (CYCLES)

logic [$clog2(CLK_DIV)-1:0] clk_cnt;

always_ff @(posedge clk_old) begin
    if (!reset_n) begin
        clk_cnt <= 0;
        clk_out <= 0;
    end else if (clk_cnt == CLK_DIV - 1) begin
            clk_cnt <= 0;
            clk_out <= ~clk_out; // Toggle clock
        end else begin
            clk_cnt <= clk_cnt + 1;
    end
end

endmodule