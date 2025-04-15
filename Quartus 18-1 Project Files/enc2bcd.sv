// File: enc2bcd.sv
// Description: Counts up or down every 4 pulses of CW or CCW. Also limits count
//              from 00 to 99 in decimal
// Author: Marcus Fu
// Date: 2024-01-18

module enc2bcd (input logic clk, cw, ccw, output logic [7:0] bcd_count) ;

    logic [2:0] cw_pulse_count = 3'd000; // Counts the number of CW pulses
    logic [2:0] ccw_pulse_count = 3'b000; // Counts the number of CCW pulses
    logic cw_pulse = 1'b0; // Clockwise pulse
    logic ccw_pulse = 1'b0; // Counter-clockwise pulse


    
    always_ff @(posedge clk) begin

        if (cw) begin // If detected
            if (cw_pulse_count <= 3) begin
                cw_pulse_count = cw_pulse_count + 1;
            end else begin
                cw_pulse_count = 0;
                cw_pulse = 1;
            end
        end

        if (cw_pulse) begin
            cw_pulse = 0;
            cw_pulse_count = 0; // Reset count for next pulse
            

                if (bcd_count[3:0] < 4'b1000) begin // if count < 8, do the following:
                    bcd_count[3:0] = bcd_count[3:0] + 4'b0001; // inc +1
                end else
                bcd_count = bcd_count; // stay at 8
        end

        // FOR COUNTING DOWN
        if (ccw) begin
            if (ccw_pulse_count <= 3) begin
                ccw_pulse_count = ccw_pulse_count + 1;
            end else begin
                ccw_pulse_count = 0;
                ccw_pulse = 1;
            end
        end

        if (ccw_pulse) begin
            ccw_pulse = 0;
            ccw_pulse_count = 0; // Reset count for next pulse

                if (bcd_count[3:0] > 0) begin // if count > 0, do the following:
                    bcd_count[3:0] = bcd_count[3:0] - 4'b0001; // inc -1
                end else
                bcd_count = bcd_count; // stay at 99

        end
    end

endmodule