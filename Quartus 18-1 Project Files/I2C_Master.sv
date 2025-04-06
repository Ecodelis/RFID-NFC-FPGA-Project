// File: i2c_master.sv
// Description: 	I2C master module. Controls read and write
//	
// Author: Marcus Fu
// Date: 2024-04-05

module i2c_master #(parameter CLK_DIV = 500)( // Default SCL: 100kHz for a 50 MHz clock
    input logic clk,                // Clock input
    input logic reset_n,            // Active-low Reset

    input logic start,              // Start signal to initiate I2C transaction
    input logic read_write,         // 0 = write, 1 = read
    input logic [6:0] addr,         // 7-bit slave address
    input logic [7:0] tx_data,      // Data to send
    output logic [7:0] rx_data,     // Data received
    output logic busy,              // Indicates if the I2C master is busy
    output logic done,

    inout wire sda,                 // SDA data line (bidirectional)
    output logic scl                // SCL clock line
);

//////////////////////////////////////////////////////////////////////////////////////////////////////
// Clock Divider
//    * The clock divider generates the SCL clock signal for I2C communication.
//////////////////////////////////////////////////////////////////////////////////////////////////////
    // Clock Divider Parameters
    logic [$clog2(CLK_DIV)-1:0] clk_cnt; // Clock divider counter: LOG2(CLK_DIV)-1 bits in size
    logic scl_tick;

    // Clock divider logic (For Standard / Fast I2C mode)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!reset_n) begin
            clk_cnt <= 0;
            scl_tick <= 0;
        end else begin
            if (clk_cnt == CLK_DIV - 1) begin
                clk_cnt <= 0;  // Reset the counter
                scl_tick <= 1;  // Generate SCL tick
            end else begin
                clk_cnt <= clk_cnt + 1; // Increment the counter
                scl_tick <= 0;  // No tick
            end
        end
    end

    // Use the scl_tick to generate the SCL clock signal
    assign scl = scl_tick; // SCL driven by the generated tick


//////////////////////////////////////////////////////////////////////////////////////////////////////
// Finite State Machine (FSM)
//    * The FSM controls the I2C communication process, including start, 
//      address sending, data writing/reading, and stop conditions.
//////////////////////////////////////////////////////////////////////////////////////////////////////
    
    // State Definitions
    typedef enum logic [2:0] {
        IDLE,
        START,
        SEND_ADDR,
        WRITE,
        READ,
        STOP,
        DONE
    } state_t;

    state_t state, next_state;

    // SDA signal control
    logic sda_out;  // Output data to SDA line
    logic sda_en;   // Enable SDA output
    assign sda = sda_en ? sda_out : 1'bz;

    logic scl_internal;
    assign scl = scl_internal;

    // SEND_ADDR Logic
    logic [7:0] bit_cnt; // Bit counter for data transfer
    logic [7:0] addr_with_rw; // Address + Read/Write bit


    // State transition logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!reset_n) begin
            state <= IDLE;
            addr_with_rw <= 0;
            bit_cnt <= 0;
            busy <= 0;
            done <= 0;
        end else begin
            if (scl_tick) begin
                state <= next_state;
            end
        end

        // Busy flag logic
        if (state == IDLE) begin
            busy <= 0; // Not busy in IDLE state
        end else if (state == START) begin
            busy <= 1; // Set busy flag when starting transaction
        end else if (state == DONE) begin
            busy <= 0; // Clear busy flag when done
        end

        // Start and Stop Conditions
        if (state == START) begin
            // START: SDA & SCL go LOW
            scl_internal <= 0;
            sda_en <= 1;
            sda_out <= 0;
        end else if (state == STOP) begin
            // STOP: SDA & SCL go HIGH
            scl_internal <= 1; // SCL high
            sda_en <= 1;
            sda_out <= 1; // SDA goes
        end else begin
            scl_internal <= scl_tick ? 1 : 0; // SCL driven by the generated tick
        end


        // Sending Slave Address (with read bit)
        if (state == SEND_ADDR) begin
            // Send slave address with read bit (R/W = 1)
            sda_en <= 1; // Enable SDA output
            sda_out <= addr[6]; // Send the MSB of the address
            if (scl_tick) begin
                // Shift the address bits
                addr <= addr << 1; // Shift the address left
                bit_cnt <= bit_cnt + 1;
            end
        end

        // Step 2: Start Reading Data
        if (state == READ) begin
            // Shift in data byte-by-byte from slave
            sda_en <= 0;  // SDA is now input (data comes from slave)
            if (scl_tick) begin
                shift_reg <= {shift_reg[6:0], sda}; // Shift in data bit by bit
                bit_cnt <= bit_cnt + 1;
            end

            // After receiving 8 bits (1 byte), send ACK (except for last byte)
            if (bit_cnt == 8) begin
                if (rx_len > 1) begin
                    // Send ACK (tell slave to continue sending)
                    sda_en <= 1;
                    sda_out <= 0; // ACK
                end else begin
                    // Send NACK (tell slave we're done)
                    sda_en <= 1;
                    sda_out <= 1; // NACK
                end
                rx_data <= shift_reg; // Store received byte
                bit_cnt <= 0; // Reset bit counter for next byte
            end
        end

        // Step 3: Generate STOP condition (after last byte)
        if (state == STOP) begin
            sda_en <= 1;
            sda_out <= 1; // SDA goes high during stop condition
            scl_internal <= 1; // SCL high during STOP
            if (scl_tick) begin
                done <= 1; // Transaction is done
            end
        end
    end

    // Next-state logic (Conditions needed to switch to next state) 
    always_comb begin
        next_state = state;

        case (state)
            IDLE: if (start) next_state = START;
            START: next_state = SEND_ADDR;
            SEND_ADDR: next_state = read_write ? READ : WRITE; // Slave address + R/W bit
            WRITE: next_state = STOP;
            READ: next_state = STOP;
            STOP: next_state = DONE;
            DONE: next_state = IDLE;
        endcase
    end





    






endmodule