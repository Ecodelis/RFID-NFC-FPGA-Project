module tonegen
    #( parameter FCLK ) // clock frequency, Hz
     ( input logic [31:0] freq, // frequency to output on speaker
       input logic onOff, // 1 -> generate output, 0 -> no output
       output logic spkr, // speaker output
       input logic reset_n, clk); // reset and clock

    logic [63:0] counter = 0; // counter for the cycles per output

    always_ff @(posedge clk) begin

        if (reset_n == 0) begin // If reset is LOW
            counter <= 0;
            spkr <= 0;
            
        end else if (onOff == 0) begin // If speaker on/off is LOW
            counter <= 0;
            spkr <= 0;

        end else begin // If there is no reset or off signal, activate sound
            if (counter * (freq << 1) >= FCLK) begin
                counter <= 0;
                spkr <= ~spkr; // toggle speaker output
            end else begin // counter + freq*2
                counter <= counter + 1;
            end

        end

    end

endmodule

