// File: enc2freq.sv
// Description: Cycles through the notes in the C Major scale 
//              (262 Hz, 295 Hz, 328 Hz, 349 Hz, 393 Hz, 437 Hz, 491 Hz, 524 Hz)
// Author: Marcus Fu
// Date: 2024-02-03

module enc2freq
    ( input logic cw, ccw, // outputs from lab 2 encoder module
    output logic [31:0] freq, // desired frequency
    input logic reset_n, clk); // reset and clock

    logic [2:0] cw_pulse_count = 3'd000; // Counts the number of CW pulses
    logic [2:0] ccw_pulse_count = 3'b000; // Counts the number of CCW pulses
    logic [3:0] bcd_count = 4'b0000; // BCD count 

    always_ff @(posedge clk) begin

        if (reset_n == 0) begin
            bcd_count <= 4'b0000; // Reset count
            cw_pulse_count <= 0;
            ccw_pulse_count <= 0;
        end else begin

            // Counting Up
            if (cw) begin 
                if (cw_pulse_count < 3) begin
                    cw_pulse_count <= cw_pulse_count + 1;
                end else begin
                    cw_pulse_count <= 0; // Reset when 4 pulses are counted
                    if (bcd_count < 4'b1000) begin // If count < 8
                        bcd_count <= bcd_count + 4'b0001; // Increment +1
                    end
                end
            end

            // Counting Down
            if (ccw) begin
                if (ccw_pulse_count < 3) begin
                    ccw_pulse_count <= ccw_pulse_count + 1;
                end else begin
                    ccw_pulse_count <= 0; // Reset when 4 pulses are counted
                    if (bcd_count > 4'b0000) begin // If count > 0
                        bcd_count <= bcd_count - 4'b0001; // Decrement -1
                        end
                    end
                end
        end
    end



    always_comb begin
        case (bcd_count)
            4'b0001: freq = 262; // 262 Hz
            4'b0010: freq = 295; // 295 Hz
            4'b0011: freq = 328; // 328 Hz
            4'b0100: freq = 349; // 349 Hz
            4'b0101: freq = 393; // 393 Hz
            4'b0110: freq = 437; // 437 Hz
            4'b0111: freq = 491; // 491 Hz
            4'b1000: freq = 524; // 524 Hz
            default: freq = 0;   // Default case, if bcd_count is out of range
        endcase
    end

endmodule