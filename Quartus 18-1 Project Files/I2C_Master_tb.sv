// File: i2c_master_PN532_tb.sv
// Description: 	Tests I2C master module with a special frame for the PN532
//	
// Author: Marcus Fu
// Date: 2024-04-12

`timescale 1ns/1ps

module i2c_master_PN532_tb;

    logic clk = 0;
    logic rst;
    logic start;
    logic [6:0] slave_addr;
    logic [7:0] data_in[0:31];
    logic [5:0] data_len;
    logic busy, ack_error;
    logic scl;
    tri   sda;

    // Clock generation
    always #10 clk = ~clk; // half period = 10ns, full clock is 20ns = 50MHz

    // Instantiate DUT
    I2C_Master #(
        .FPGA_CLK_FREQ(50_000_000), // 50 MHz
        .I2C_FREQ(100_000)          // 100 kHz
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .slave_addr(slave_addr),
        .data_in(data_in),
        .data_len(data_len),
        .busy(busy),
        .ack_error(ack_error),
        .scl(scl),
        .sda(sda)
    );

    // Pull-up SDA line
    assign sda = 1'bz;

    // Stimulus
    initial begin
        $display("Starting I2C Master Testbench...");
        rst = 0;
        #40;
        rst = 1;
        start = 0;


        // Prepare PN532 GetFirmwareVersion frame
        data_in[0] = 8'h00; // Preamble
        data_in[1] = 8'h00;
        data_in[2] = 8'hFF;
        data_in[3] = 8'h02; // LEN
        data_in[4] = 8'hFE; // LCS
        data_in[5] = 8'hD4; // TFI
        data_in[6] = 8'h02; // CMD: GetFirmwareVersion
        data_in[7] = 8'h00; // Postamble

        slave_addr = 6'b100110;  // PN532 I2C address = 0x24
        data_len   = 1;

        #20;
        start = 1;
        #10;
        start = 0;

        

        #400000 ;
        $stop;
        // Wait until transfer is complete
        wait (busy == 1);
        wait (busy == 0);

        if (ack_error)
            $display("ACK error occurred during I2C transmission");
        else
            $display("I2C transmission completed successfully");

        $stop;
    end

endmodule