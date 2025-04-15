// File: encoder.sv
// Description: Rotary encoder module. Used to count up when rotating CW and count down when rotating CCW
// Author: Marcus Fu
// Date: 2024-01-18

module encoder	( input logic clk,      // clock signal
                  input logic a,        // Rotary encoder signal a
                  input logic b,        // Rotary encoder signal b
                  output logic cw,      // Clockwise pulse
                  output logic ccw );   // Counter-clockwise pulse

    logic a_prev = 0; // stores the last state of signal a
	logic b_prev = 0; // stores the last state of signal b



    // B follows A when going CW
    // A follows B when going CCW

    always_ff @(posedge clk) begin

// a != prev_b
        if ((a != a_prev && b == a_prev) || (b != b_prev && b == a_prev)) begin // When going CW
            cw = 1'b1;
            ccw = 1'b0;
        end else if ((a != a_prev && a == b_prev) || (b != b_prev && a == b_prev)) begin // When going CCW
            cw = 1'b0;
            ccw = 1'b1;
        end else begin // When a_prev == b_prev
            cw = 1'b0;
            ccw = 1'b0;
        end

        {a_prev, b_prev} <= {a, b}; // store current values as previous values
    end


endmodule