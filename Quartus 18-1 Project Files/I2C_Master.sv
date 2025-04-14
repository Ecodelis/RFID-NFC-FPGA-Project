// File: i2c_master.sv
// Description: 	I2C master module. Controls read and write
// Author: Marcus Fu
// Date: 2024-04-05

// when reading use data_len_tx to write # of bytes. After
// sending required, instead of stopping, if write_read == READ
// go to read mode where u sample and ack until NACK and then issue stop
// implement time out if never send ACK after waiting some time (50ms)



module I2C_Master #(
    parameter FPGA_CLK_FREQ = 50_000_000, // Default FPGA clock: 50 MHz
    parameter I2C_FREQ = 100_000,         // Default I2C Standard Mode clock: 100 kHz
    parameter TX_SIZE = 32, 
    parameter RX_SIZE = 64
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        start,              // Trigger transmission
    input  logic [6:0]  slave_addr,         // 7-bit I2C address
    input  logic [7:0]  data_tx [TX_SIZE],  // Up to 32 Byte array to send
    input  logic [5:0]  data_len_tx,        // Number of bytes to send
    output logic [7:0]  data_rx [RX_SIZE],  // Up to 64 bytes to recieve
    input  logic [5:0]  data_len_rx,        // Number of bytes to recieve

    input logic         write_read,         // write/read operation bit (0/1)
    input logic         stop_bit,           // Goes back to IDLE without a stop bit if 0
    input logic         mode,               // I2C MODE

    output logic        busy,               // High while sending
    output logic        ack_error,          // High if any byte not ACK'd
    output logic        scl,          
    inout  tri          sda,                // Tri-state SDA line

    output logic [1:0] scl_mid_tick_obs     // Obersving point for mtick

);


    // --- I2C Modes ---
    typedef enum logic {
        NORMAL,
        PN532        // Sent with write_read = 1. If ACK is sent after address byte polling, initiate re-start into read
    } I2CMODE_t;

    I2CMODE_t I2CMODE;

    // --- write or read register ---
    typedef enum logic {
        WRITE,
        READ
    } write_read_t;

    write_read_t write_read_reg, I2C_write_read_mode;

    // --- States ---
    typedef enum logic [2:0] {
        IDLE, 
        START, 
        SEND_BIT, 
        CHECK_ACK, 
        STOP
    } state_t;

    // --- Internal Signals ---
    state_t state, next_state;
    logic [7:0] shift_reg;
    logic [3:0] bit_cnt, byte_idx_tx, byte_idx_rx;
    logic sda_out, sda_en;
    logic scl_internal;

    // --- Assign output signals ---
    assign scl = scl_internal;
    assign sda = sda_en ? sda_out : 1'bz;

    // --- SCL Clock Generator ---
    localparam int CLK_DIV = FPGA_CLK_FREQ / I2C_FREQ;
    localparam int CLK_DIV_HALF = CLK_DIV / 2;
    logic [$clog2(CLK_DIV)-1:0] scl_tick;

    // --- SCL Mid-Tick States ---
    typedef enum logic [1:0] {
        OFF,    // No Assertion
        LOW,    // SCL is low
        HIGH    // SCL is high
    } scl_mid_tick_t;

    scl_mid_tick_t scl_mid_tick;

    assign scl_mid_tick = 
    ((scl_tick == CLK_DIV_HALF - 1) && scl_internal == 0) ? LOW : 
    ((scl_tick == CLK_DIV_HALF - 1) && scl_internal == 1) ? HIGH : OFF;

    assign scl_mid_tick_obs = scl_mid_tick;

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            scl_tick     <= 0;
            scl_internal <= 1;
        end else if (state != IDLE) begin
            scl_internal <= (scl_tick == CLK_DIV - 1) ? ~scl_internal : scl_internal;
            scl_tick     <= (scl_tick == CLK_DIV - 1) ? 0 : scl_tick + 1;
        end else begin
            scl_tick     <= 0;
            scl_internal <= 1;
        end
    end

    // --- State Register ---
    always_ff @(posedge clk or posedge rst) begin
        if (!rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // --- Next State Logic ---
    always_comb begin
        next_state = state;
        case (state)
            IDLE:       
                if (start)  next_state = START;
            START:      
                if (sda_out == 0 && scl_internal == 0)   
                    next_state = SEND_BIT;
            SEND_BIT:   
                if (scl_mid_tick == HIGH)    
                    if (bit_cnt == 0)  
                        next_state = CHECK_ACK;
            CHECK_ACK:  
                if (scl_mid_tick == HIGH) begin
                    if (sda == 0 && byte_idx_tx < data_len_tx && I2C_write_read_mode == WRITE)
                        next_state = SEND_BIT;
                    else if (sda == 0 && byte_idx_rx == 0 && I2C_write_read_mode == READ)
                        next_state = START; // Re-start bit 
                    else if (sda == 0 && byte_idx_rx < data_len_rx && I2C_write_read_mode == READ)
                        next_state = SEND_BIT; // After re-start bit, actually move to reading
                    else if (stop_bit)
                        next_state = STOP;
                    else 
                        next_state = IDLE;
                end
            STOP:       if (busy == 0 && sda_out == 1) next_state = IDLE;
            default:    if (scl_mid_tick == HIGH) next_state = IDLE;
        endcase
    end

    // --- Control Logic ---
    always_ff @(posedge clk or posedge rst) begin
        if (!rst) begin
            busy        <= 0;
            ack_error   <= 0;
            byte_idx_tx <= 0;
            byte_idx_rx <= 0;
            sda_out     <= 1;
            sda_en      <= 0;
            bit_cnt     <= 8;
            shift_reg   <= 0;
        end 
            case (state)
                IDLE: begin
                    busy        <= 0;
                    ack_error   <= 0;
                    byte_idx_tx <= 0;
                    byte_idx_rx <= 0;
                    sda_en      <= 0;
                    sda_out     <= 1;
                    write_read_reg <= WRITE; // default value
                    I2C_write_read_mode <= WRITE; // default value
                end

                START: begin
                    if (scl_mid_tick == HIGH) begin
                        busy    <= 1;
                        sda_en  <= 1;
                        sda_out <= 0; // pull SDA low

                        // Prepare ADDR Write
                        if (I2C_write_read_mode == WRITE) begin
                        shift_reg <= {slave_addr, write_read}; // 7-bit addr + write = 0, read = 1
                        write_read_reg <= write_read_t'(write_read); // store write or read operation bit
                        bit_cnt   <= 8;
                        end
                    end
                end

                SEND_BIT: begin
                    if (scl_mid_tick == LOW) begin
                        if (I2C_write_read_mode == WRITE) begin
                            sda_en <= 1;

                            // send bits
                            if (bit_cnt > 0) begin
                                sda_out <= shift_reg[bit_cnt - 1];
                                bit_cnt <= bit_cnt - 1;
                            end
                        end else if (I2C_write_read_mode == READ) begin
                            sda_en <= 0;

                            // recieve bits
                            if (bit_cnt > 0) begin
                                shift_reg[bit_cnt - 1] <= sda; // sample bits
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                CHECK_ACK: begin
                    if (scl_mid_tick == LOW) begin
                        
                        if (I2C_write_read_mode == WRITE) begin
                            sda_en <= 0; // Release SDA for ACK from slave

                            // Uncomment to pass ACK in testbench
                            //sda_en <= 1;
                            //sda_out <= 0;

                            // Comment line below to pass ACK in testbench
                            if (sda === 1'b1) ack_error <= 1;

                            byte_idx_tx <= byte_idx_tx + 1; // Initial: Start at byte 2

                            // Prepare next byte to send if there is any
                            if (byte_idx_tx < data_len_tx) begin
                                shift_reg <= data_tx[byte_idx_tx];
                                bit_cnt   <= 8;

                                // On the last byte, switch to read mode
                                if (byte_idx_tx + 1 >= data_len_tx && write_read_reg == READ) begin
                                    I2C_write_read_mode <= READ;

                                    // Prepare for reading
                                    shift_reg <= 0;
                                    byte_idx_rx <= 0;
                                end

                            end
                            

                        end else if (I2C_write_read_mode == READ) begin
                            // ...
                            // read code here (master controls ack)
                            // ...

                            if (byte_idx_rx < data_len_rx) begin
                                data_rx[byte_idx_rx] <= shift_reg;
                                bit_cnt   <= 8;
                                byte_idx_rx <= byte_idx_rx + 1; // Increment index of data_tx

                                sda_en <= 1;
                                sda_out <= 0; // ACK
                            end 

                        end else ack_error <= 1; // kinda useless

                    end
                end

                STOP: begin
                    // Pulls low and then high to simualte stop bit
                    if (scl_mid_tick == LOW && busy == 1) begin
                        sda_en  <= 1;
                        sda_out <= 0;
                    end else if (scl_mid_tick == HIGH) begin
                        sda_en  <= 1;
                        sda_out <= 1; // Send stop (SDA goes high while SCL is high)
                        busy <= 0;
                    end
                end
            endcase
        end

endmodule
