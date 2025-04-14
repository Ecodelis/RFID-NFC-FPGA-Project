// File: i2c_master_PN532_tb.sv
// Description: Testbench for I2C Master with PN532 frame simulation
// Author: Marcus Fu
// Date: 2024-04-12

`timescale 1us / 1ns

module i2c_master_PN532_tb;

    // Testbench signals
    logic clk = 0;
    logic rst;
    logic start;
    logic [6:0] slave_addr;
    logic [7:0] data_tx[0:31];
    logic [5:0] data_len_tx;
    logic [7:0] data_rx[0:63];
    logic [5:0] data_len_rx;
    logic write_or_read, stop_bit, mode;
    logic busy, ack_error;
    logic scl;

    logic [7:0] data[0:7]; // 8 bytes
    logic ack_master;
    logic [1:0] scl_mid_tick_obs;
    wire scl_mid_tick_in_tb = scl_mid_tick_obs; // for observing scl_mid_tick (1 == LOW, 2 == HIGH)
    
    // SDA line (bidirectional) with pullup
    tri sda;
    pullup(sda);
    
    // Testbench driving control: enable and data value.
    logic sda_tb_en;
    logic sda_tb_data;
    assign sda = sda_tb_en ? sda_tb_data : 1'bz;
    wire sda_in_tb = sda;  // for observing SDA

    // Clock Generation: 50 MHz
    always #10 clk = ~clk;

    // Instantiate DUT
    I2C_Master #(
        .FPGA_CLK_FREQ(50_000_000),
        .I2C_FREQ(100_000),
        .TX_SIZE(32),
        .RX_SIZE(64)
    ) dut (
        .clk(clk),
        .rst(rst),
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

    // === TASKS === //
    // Delay for a precise time using $time
    task automatic delay_ns(input time delay_time);
        time t_start = $time;
        while ($time < t_start + delay_time) begin
            #1ns; // Yield time
        end
    endtask


    // Wait for START condition: SDA goes low while SCL is high
    task wait_for_start();
        @(posedge scl);
        wait (sda_in_tb === 0);
        $display("START condition detected at time %0t", $time);
    endtask

    // 1 for LOW, 2 for HIGH
    task wait_for_mid_tick(input logic height);
        if (height == 1) begin
            @(negedge scl);
            wait(scl_mid_tick_in_tb == 1);
            wait(scl_mid_tick_in_tb == 0);
        end else if (height == 2) begin
            @(posedge scl);
            wait(scl_mid_tick_in_tb == 2);
            wait(scl_mid_tick_in_tb == 0);
        end
    endtask

    // Receive one byte from SDA (sampled on SCL rising edge)
    task receive_i2c_byte(output logic [7:0] data_out, input logic ack_in);
        data_out = 8'h00;
        for (int i = 0; i < 8; i++) begin
            @(posedge scl);
            data_out = {data_out[6:0], sda_in_tb};
        end
        $display("Received byte: %02h at time %0t", data_out, $time);

        send_ack(ack_in);
    endtask



    // Emulate slave sending one byte by driving SDA
    task send_i2c_byte(input logic [7:0] data_in, output logic ack_out);
        for (int i = 7; i >= 0; i--) begin
            wait_for_mid_tick(1);
            sda_tb_en = 1;
            sda_tb_data = data_in[i];
        end

        $display("Sent byte: %02h at time %0t", data_in, $time);

        receive_ack(ack_out); // Call the task to get ACK from master
    endtask



    // Emulate slave ACK/NACK response (ACK = 0, NACK = 1)
    task send_ack(input logic ack_in);
        // Hold SDA low during middle of SCL low for ACK/NACK
        @(negedge scl);
        wait(scl_mid_tick_in_tb == 1);
        wait(scl_mid_tick_in_tb == 0);
        sda_tb_en = 1;      // Drive ACK/NACK
        sda_tb_data = ack_in;  // ACK (Set to 0 for ACK, 1 for NACK)
        wait_for_mid_tick(1);
        sda_tb_en = 0;
    endtask

    // Wait for ACK from master after sending a byte
    task receive_ack(output logic ack_bit);
        @(negedge scl);      // Start of ACK bit period
        sda_tb_en = 0;       // Release SDA so master can drive it

        wait_for_mid_tick(2);
        ack_bit = sda_in_tb; // Read ACK (0 = ACK, 1 = NACK)

        $display("Received %s from master at time %0t", 
                (ack_bit == 0) ? "ACK" : "NACK", $time);
    endtask


    // === MAIN TEST === //

    initial begin

        $display("Starting I2C Master Testbench...");
        // Initialize signals
        rst = 0;
        start = 0;
        sda_tb_en = 0; // Initially, testbench is not driving SDA
        
        #40 rst = 1;  // Release reset
        
        rst = 0;
        start = 0;
        sda_tb_en = 0; // Testbench initially doesn't drive SDA
        
        #40 rst = 1; // Release reset

        // === 1. Write Command Frame to PN532 ===
        data_tx[0] = 8'h00; // Preamble
        data_tx[1] = 8'h00;
        data_tx[2] = 8'hFF;
        data_tx[3] = 8'h02;
        data_tx[4] = 8'hFE;
        data_tx[5] = 8'hD4;
        data_tx[6] = 8'h02;
        data_tx[7] = 8'h00;


/*
        slave_addr    = 7'b0100100;  // PN532 = 0x24
        data_len_tx   = 3;
        write_or_read = 0; // write
        stop_bit      = 1;
        mode          = 0;

        #20 start = 1;
        #40 start = 0;

        wait (busy == 1);
        //wait_for_start();

        // === ACK for master write ===
        // Wait for first byte (slave address + write bit)
        receive_i2c_byte(data[0], 0);

        // Wait for second byte (data)
        receive_i2c_byte(data[1], 0);

        wait (busy == 0);
*/


        // === 2. Read Example ===

        /*
        data_tx[0] = 8'hDD; // example register address

        slave_addr    = 7'b0100100;
        data_len_tx   = 2;
        data_len_rx   = 2;
        write_or_read = 1; // read operation
        stop_bit      = 1;
        mode = 1;
        
        #20 start = 1;
        #40 start = 0;
        
        wait (busy == 1);
        //wait_for_start();

        // Master writing to slave register
        receive_i2c_byte(data[0], 0); // address
        receive_i2c_byte(data[1], 0); // preamble
        
        // Emulate slave sending two bytes:
        send_i2c_byte(8'b10101010, ack_master);
        send_i2c_byte(8'b00010001, ack_master);
        
        wait (busy == 0);

        */

        // === 3. PN532 Read Example ===


        
        
        $display("RX[0] = %02h, RX[1] = %02h", data_rx[0], data_rx[1]);
        if (ack_error)
            $display("ACK error occurred during I2C transmission");
        else
            $display("I2C transmission completed successfully");
        
        $stop;
    end

endmodule
