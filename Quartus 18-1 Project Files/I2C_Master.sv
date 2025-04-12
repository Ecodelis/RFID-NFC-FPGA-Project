// File: i2c_master.sv
// Description: 	I2C master module. Controls read and write
//	
// Author: Marcus Fu
// Date: 2024-04-05

module i2c_master #(
    // Clock divider -> 50 MHz / 100 kHz = 500
    parameter CLK_BIT_COUNT = 500   // Number of clock cycles for standard mode 100 kHz SCL
)( 
    input logic clk,                // Clock input
    input logic reset_n,            // Active-low Reset

    input logic start,              // Start signal to initiate I2C transaction
    input logic read_write,         // 0 = write, 1 = read
    input logic [6:0] addr,         // 7-bit slave address
    input logic [7:0] tx_data,      // Data to send
    input logic more_data,          // Indicates if there is more data to send
    output logic [7:0] rx_data,     // Data received
    output logic busy,              // Indicates if the I2C master is busy
    output logic done,              // Indicates if the I2C transaction is done

    inout wire sda,                 // SDA data line (bidirectional)
    output logic scl                // SCL clock line
);

//////////////////////////////////////////////////////////////////////////////////////////////////////
// Clock Divider
//    * The clock divider generates the SCL clock signal for I2C communication.
//////////////////////////////////////////////////////////////////////////////////////////////////////
    
    // Precompute the clock divider using parameters
    localparam int CLK_DIV = FPGA_CLK_FREQ / I2C_FREQ ; // Computed at synthesis time (CYCLES)

    // Clock Divider Parameters
    logic [$clog2(CLK_DIV)-1:0] scl_tick; // Clock divider counter: LOG2(CLK_DIV)-1 bits in size
    logic scl_internal; // Square wave (Drives SCL line)
    logic half_clk; // HIGH when in the middle of the SCL clock cycle

    // Clock divider logic
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            scl_internal <= 1; // Default SCL high
            scl_tick <= 0;
        end else if (state != IDLE) begin // if not IDLE begin clock divider
            scl_internal <= ~scl_internal;  // Toggle SCL line
            scl_tick <= (scl_tick == CLKS_PER_BIT - 1) ? 0 : scl_tick + 1; // tick counter
        else
            scl_tick <= 0;
        end
    end

    // Generate a tick in the middle of every scl clock cycle
    assign scl_mid_tick = (clk_cnt == CLKS_PER_BIT / 2);  

    assign scl = scl_internal; 


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
        DONE,             // Indicates if the I2C transaction is done
    } state_t;

    state_t state, next_state;

    // State transition logic
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic (Conditions needed to switch to next state) 
    always_comb begin
        next_state = state; // Default to current state

        case (state)
            IDLE: begin
                if (start) next_state = START;
                busy = 1; // Indicate that the I2C master is busy
                done = 0; 
                sda_en = 0;
            end
            START: begin
                    if (!scl_internal) next_state = SEND_ADDR;
                    sda_en = 1; // Enable SDA output
            end
            SEND_ADDR: begin
                    next_state = ADDR_ACK; // After sending the slave address, check for ACK
            end
            ADDR_ACK: begin
                    if (!sda_in) begin // Pulled Low = ACK
                        // Slave ACK received
                        next_state = read_write ? READ : WRITE;
                    end else begin
                        // No ACK (NACK)
                        next_state = STOP;
                    end
            end
            WRITE: begin
                    next_state = DATA_ACK; // After sending data, check for ACK
            end
            DATA_ACK: begin
                if (!sda_in) begin
                    // Slave ACK received
                    next_state = WRITE_NEXT; // Prepare for next byte
                end else begin
                    // No ACK (NACK)
                    next_state = STOP;
                end
            end
            WRITE_NEXT: begin
                if (more_data) begin
                    next_state = WRITE; // Send the next byte
                end else begin
                    next_state = STOP; // No more data to send
                end
            end
            READ: begin
                next_state = READ_NEXT; // Prepare to read the next byte
            end
            READ_NEXT: begin
                if (more_data) begin
                    next_state = READ; // Read the next byte
                end else begin
                    next_state = STOP; // No more data to read
                end
            end
            STOP: begin
                next_state = DONE,             // Indicates if the I2C transaction is done;
            end
            DONE: begin             // Indicates if the I2C transaction is done: begin
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE; // Default to IDLE state on unknown state
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
    logic sda_in; // Input data from SDA line
    logic sda_en;   // Enable SDA output (release or holds SDA)

    assign sda = sda_en ? sda_out : 1'bz; // Drive SDA when enabled, otherwise high-Z
    assign sda_in = sda; // Always read the SDA line

    // counters
    logic [2:0] bit_cnt; // 3-bit counter for 8 bits of data
    logic [7:0] addr_with_rw; // Address with read/write bit


    // Start and Stop (Asynchronous to SCL)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            addr_with_rw <= 0;
            bit_cnt <= 0;
            sda_out <= 1;       // Default SDA high
        end else if (scl_mid_tick) begin
            case (state)
                START: begin
                    sda_out <= 0;      // SDA goes low
                    addr_with_rw <= {addr, read_write}; // Prepare address with R/W bit
                end

                SEND_ADDR: begin
                    if (bit_cnt < 8) begin
                        sda_out <= addr_with_rw[bit_cnt]; // Send address MSB to LSB 
                        bit_cnt <= bit_cnt + 1; // Increment bit counter
                    end else begin
                        bit_cnt <= 0; // Reset bit counter for next byte
                    end
                end

                default: begin
                    // Default behavior for other states
                end
            endcase
        end
    end



    






endmodule