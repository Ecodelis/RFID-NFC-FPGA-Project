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
        .sda(sda)
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

    // Receive one byte from SDA (sampled on SCL rising edge)
    task receive_i2c_byte(output logic [7:0] data_out, input logic ack);
        data_out = 8'h00;
        for (int i = 0; i < 8; i++) begin
            @(posedge scl);
            data_out = {data_out[6:0], sda_in_tb};
        end
        $display("Received byte: %02h at time %0t", data_out, $time);

        send_ack(ack);
    endtask



    // Emulate slave sending one byte by driving SDA
    task send_i2c_byte(input logic [7:0] data_in);
        for (int i = 7; i >= 0; i--) begin
            @(negedge scl);  // Wait for SCL to go low
            sda_tb_en = 1;    // Enable testbench driver
            sda_tb_data = data_in[i]; // Drive current bit
            @(posedge scl);   // Let master sample the bit
        end
        
        // should be recieve ack
        //send_ack(ack);
    endtask


    // Emulate slave ACK/NACK response (ACK = 0, NACK = 1)
    task send_ack(input logic ack);
        // Hold SDA low during middle of SCL low for ACK/NACK
        @(negedge scl);     // Wait for SCL to go low
        delay_ns(5000);     // Wait for half of the low time
        sda_tb_en = 1;      // Drive ACK/NACK
        sda_tb_data = ack;  // ACK (Set to 0 for ACK, 1 for NACK)
        @(posedge scl); 
        @(negedge scl);     // Release SDA after SCL goes low
        delay_ns(5000);     
        sda_tb_en = 0;
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

        slave_addr    = 7'b0100100;  // PN532 = 0x24
        data_len_tx   = 2;
        write_or_read = 0; // write
        stop_bit      = 1;
        mode          = 0;

        #20 start = 1;
        #40 start = 0;

        wait (busy == 1);

        // === ACK for master write ===
        // Wait for first byte (slave address + write bit)
        receive_i2c_byte(data[0], 0); // send ACK after this byte

        // Wait for second byte (data)
        receive_i2c_byte(data[1], 0); // send ACK again

        wait (busy == 0);



        // === 2. Read Example ===
        data_tx[0] = 8'hDD;
        data_tx[1] = 8'h22;

        slave_addr    = 7'b1010101;
        data_len_tx   = 2;
        data_len_rx   = 2;
        write_or_read = 1; // read operation
        stop_bit      = 1;
        
        #20 start = 1;
        #40 start = 0;
        
        wait (busy == 1);
        wait_for_start();
        
        // Emulate slave sending two bytes:
        send_i2c_byte(8'hA5);
        send_ack(0); // ACK (drive 0)
        send_i2c_byte(8'h5A);
        send_ack(1); // NACK (drive 1) for last byte
        
        wait (busy == 0);
        
        $display("RX[0] = %02h, RX[1] = %02h", data_rx[0], data_rx[1]);
        if (ack_error)
            $display("ACK error occurred during I2C transmission");
        else
            $display("I2C transmission completed successfully");
        
        $stop;
    end

endmodule
