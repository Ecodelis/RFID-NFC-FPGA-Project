// File: i2c_master_PN532_tb.sv
// Description: 	Slave test for the PN532 sim
//	
// Author: Marcus Fu
// Date: 2024-04-12

module I2C_Slave (
    input logic clk,
    input logic rst,
    input logic scl,
    inout logic sda,
    input logic [6:0] slave_addr,
    input logic [7:0] data_in[0:31],
    input logic [5:0] data_len,
    output logic ack_error
);
    // Internal signals to track communication
    reg [7:0] received_data;
    reg [3:0] bit_count;
    reg ack; // ACK flag

    // Pull-up SDA line for non-driven states (tri-state)
    assign sda = (ack) ? 1'b0 : 1'bz;  // Drive SDA low for ACK, high-impedance for other states

    // I2C Slave logic
    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            bit_count <= 0;
            ack <= 1'b1;  // Default to sending ACK
            ack_error <= 0;
        end else begin
            // Simulate receiving data (this is simplified)
            if (bit_count < 8) begin
                received_data[bit_count] <= sda; // Capture incoming data on SDA
                bit_count <= bit_count + 1;
            end else begin
                // After receiving 8 bits, send ACK
                ack <= 1'b0; // Drive SDA low for ACK
                // Add logic for error handling if necessary
                ack_error <= 0; // Reset error flag
            end
        end
    end
endmodule
