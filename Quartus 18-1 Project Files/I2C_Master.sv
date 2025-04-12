// File: i2c_master.sv
// Description: 	I2C master module. Controls read and write
//	
// Author: Marcus Fu
// Date: 2024-04-05

module i2c_master #(
    parameter FPGA_CLK_FREQ = 50_000_000, // Default FPGA clock: 50 MHz
    parameter I2C_FREQ = 100_000          // Default I2C Standard Mode clock: 100 kHz
)( // Default SCL: 100kHz for a 50 MHz clock
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
    
    // Precompute the clock divider using parameters
    localparam int CLK_DIV = FPGA_CLK_FREQ / (I2C_FREQ * 2); // Computed at synthesis time

    // Clock Divider Parameters
    logic [$clog2(CLK_DIV)-1:0] clk_cnt; // Clock divider counter: LOG2(CLK_DIV)-1 bits in size
    logic scl_tick; // when clock ticks, scl_tick is high for one clock cycle
    logic scl_internal; // Square wave (Drives SCL line)

    // Clock divider logic
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clk_cnt <= 0;
            scl_internal <= 1; // Default SCL high
            scl_tick <= 0;
        end else if (clk_cnt == CLK_DIV - 1) begin
            clk_cnt <= 0;
            scl_internal <= ~scl_internal;  // Toggle clock
            scl_tick <= 1;                  // Generate a tick
        end else begin
            clk_cnt <= clk_cnt + 1;
            scl_tick <= 0;
        end
    end

    // Use the scl_tick to generate the SCL clock signal
    assign scl = scl_internal; // SCL driven by the generated tick


//////////////////////////////////////////////////////////////////////////////////////////////////////
// Finite State Machine (FSM)
//    * The FSM controls the I2C communication process, including start, 
//      address sending, data writing/reading, and stop conditions.
//////////////////////////////////////////////////////////////////////////////////////////////////////
    
    // State Definitions
    typedef enum logic [3:0] { // Updated to 4 bits to accommodate additional states
        IDLE,
        START,
        SEND_ADDR,
        ADDR_ACK,    // Check for ACK/NACK after sending the address
        WRITE,
        DATA_ACK,    // Check for ACK/NACK after sending a data byte
        WRITE_NEXT,  // Handle multi-byte writes
        READ,
        READ_NEXT,   // Handle multi-byte reads
        STOP,
        DONE
    } state_t;

    state_t state, next_state;

    // State transition logic
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
        end else begin
            if (scl_tick) begin
                state <= next_state;
            end
        end
    end

    // Next-state logic (Conditions needed to switch to next state) 
    always_comb begin
        next_state = state; // Default to current state

        case (state)
            IDLE: begin
                if (start) next_state = START;

                busy = 1; // Indicate that the I2C master is busy
                done = 0; // Reset done signal
            end
            START: begin
                next_state = SEND_ADDR;

                sda_en = 1; // Enable SDA output
            end
            SEND_ADDR: begin
                next_state = read_write ? READ : WRITE; // Slave address + R/W bit
            end
            WRITE: begin
                next_state = STOP;
            end
            READ: begin
                next_state = STOP;
            end
            STOP: begin
                next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end


//////////////////////////////////////////////////////////////////////////////////////////////////////
// State Logic
//    * Each state of the FSM is responsible for specific actions in the I2C protocol.
//
//////////////////////////////////////////////////////////////////////////////////////////////////////

    // SDA signal control
    logic sda_out;  // Output data to SDA line
    logic sda_en;   // Enable SDA output (release or holds SDA)

    // SDA Driver
    always_ff @(negedge scl_internal or negedge reset_n) begin
        if (!reset_n) begin
            sda <= 0; // Default SDA low
        end else begin
            sda <= sda_en ? sda_out : 1'bz; // Drive SDA when enabled
        end
    end


    // Start and Stop (Asynchronous to SCL)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            addr_with_rw <= 0;
            bit_cnt <= 0;
            done <= 0;
            sda_out <= 1;       // Default SDA high
            sda_en <= 0;        // Release SDA
        end else if (scl_tick) begin
        case (state)
            START: begin
                sda_out <= 0;      // SDA goes low
            end

            SEND_ADDR: begin
                
            end

            default: begin
                // Default behavior for other states
            end
        endcase
    end

    end



    






endmodule