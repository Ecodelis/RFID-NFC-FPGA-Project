// File: PN532_FireLink_Bridge.sv
// Description: Top-level module for FireLink Bridge communication
//              between the DE0-Nano-SoC and PN532 NFC_V3 ELECHOUSE.
//              Uses I2C communication for RFID and NFC applications.
//
// Author: Marcus Fu
// Date: 2024-04-02

module PN532_FireLink_Bridge (
    input  logic CLOCK_50,   // 50 MHz clock

    // Encoder 2 pins with weak pull-up
    (* altera_attribute = "-name WEAK_PULL_UP_RESISTOR ON" *)
    input  logic enc2_a, enc2_b,      

    input  logic s1, s2,               // Pushbuttons
    output logic [7:0] leds,          // 7-seg LED enables
    output logic [3:0] ct,            // Digit cathodes
    output logic spkr,                // Buzzer output

    (* altera_attribute = "-name WEAK_PULL_UP_RESISTOR ON" *) inout tri sda, // serial data line
    (* altera_attribute = "-name WEAK_PULL_UP_RESISTOR ON" *) output logic scl // clock logic line

);

    // --- Internal Signals ---
    logic [1:0] digit;
    logic [3:0] disp_digit;
    logic [15:0] clk_div_count;
    logic [31:0] tone_freq = 0;
    logic onOff = 0;

    logic [7:0] enc2_count;
    logic enc2_cw, enc2_ccw;

    // --- I2C Master signals ---
    logic start;
    logic [6:0] slave_addr = 7'h24;  // Example PN532 I2C address
    logic [7:0] data_tx[0:31];
    logic [5:0] data_len_tx;
    logic [7:0] data_rx[0:63];
    logic [5:0] data_len_rx;
    logic write_or_read;
    logic stop_bit;
    logic mode;
    logic busy, ack_error;
    logic [1:0] scl_mid_tick_obs;

    // --- Module Instantiations ---
    decode2 decode2_0 (.digit(digit), .ct(ct));
    decode7 decode7_0 (.num(disp_digit), .leds(leds));

    encoder encoder_2 (
        .clk(CLOCK_50),
        .a(enc2_a),
        .b(enc2_b),
        .cw(enc2_cw),
        .ccw(enc2_ccw)
    );

    tonegen #(.FCLK(50000000)) tonegen_1 (
        .clk(CLOCK_50),
        .reset_n(reset_n),
        .freq(tone_freq),
        .onOff(onOff),
        .spkr(spkr)
    );

    enc2freq enc2freq_2 (
        .clk(CLOCK_50),
        .cw(enc2_cw),
        .ccw(enc2_ccw),
        .freq(tone_freq),
        .reset_n(reset_n)
    );

    // I2C Master instantiation
    I2C_Master #(
        .FPGA_CLK_FREQ(50_000_000),
        .I2C_FREQ(100_000),
        .TX_SIZE(32),
        .RX_SIZE(64)
    ) i2c_master_inst (
        .clk(CLOCK_50),
        .rst(reset_n),
        .start(start),
        .slave_addr(slave_addr),
        .data_tx(data_tx),
        .data_len_tx(data_len_tx),
        .data_rx(data_rx),
        .data_len_rx(data_len_rx),
        .write_read(write_or_read),
        .stop_bit(stop_bit),
        .mode(mode),
        .busy(busy),
        .ack_error(ack_error),
        .scl(scl),
        .sda(sda),
        .scl_mid_tick_obs(scl_mid_tick_obs)
    );

     
    // --- Pushbutton and Control Logic ---
    always_ff @(posedge CLOCK_50) begin
        clk_div_count <= clk_div_count + 1;

        // Pushbutton logic
        reset_n <= s1;

        onOff <= s2;

        // Edge detection for s2 (falling edge)
        s2_prev <= s2;

    end



    assign digit = clk_div_count[15:14];

    always_comb begin
        disp_digit = 4'b0000;
        case (digit)
            2'b00: disp_digit = tone_freq[7:4];
            2'b01: disp_digit = tone_freq[3:0];
            2'b10: disp_digit = tone_freq[15:12];
            2'b11: disp_digit = tone_freq[11:8];
            default: disp_digit = 4'b0000;
        endcase
    end




endmodule