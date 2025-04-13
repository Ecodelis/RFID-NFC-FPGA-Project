// File: i2c_master.sv
// Description: 	I2C master module. Controls read and write
// Author: Marcus Fu
// Date: 2024-04-05

module I2C_Master #(
    parameter FPGA_CLK_FREQ = 50_000_000, // Default FPGA clock: 50 MHz
    parameter I2C_FREQ = 100_000          // Default I2C Standard Mode clock: 100 kHz
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        start,           // Trigger transmission
    input  logic [6:0]  slave_addr,      // 7-bit I2C address
    input  logic [7:0]  data_in[32],     // Byte array to send
    input  logic [5:0]  data_len,        // Number of bytes
    output logic        busy,            // High while sending
    output logic        ack_error,       // High if any byte not ACK'd
    output logic        scl,
    inout  tri          sda              // Tri-state SDA line
);

    // --- States ---
    typedef enum logic [2:0] {
        IDLE, START, SEND_BIT, CHECK_ACK, STOP
    } state_t;

    // --- Internal Signals ---
    state_t state, next_state;
    logic [7:0] shift_reg;
    logic [3:0] bit_cnt, byte_idx;
    logic sda_out, sda_en;
    logic scl_internal;

    // Assign output signals
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
            IDLE:       if (start)             next_state = START;
            START:      if (sda_out == 0 && scl_internal == 0)   
                            next_state = SEND_BIT;
            SEND_BIT:   if (scl_mid_tick == HIGH)    if (bit_cnt == 0)  next_state = CHECK_ACK;
            CHECK_ACK:  if (scl_mid_tick == HIGH) begin
                            if (sda == 0 && byte_idx < data_len)
                                next_state = SEND_BIT;
                            else  
                                next_state = STOP;
                        end
            STOP:       if ((scl_mid_tick == HIGH) && sda_out == 1) next_state = IDLE;
            default:    if (scl_mid_tick == HIGH) next_state = IDLE;
        endcase
    end

    // --- Control Logic ---
    always_ff @(posedge clk or posedge rst) begin
        if (!rst) begin
            busy       <= 0;
            ack_error  <= 0;
            byte_idx   <= 0;
            sda_out    <= 1;
            sda_en     <= 0;
            bit_cnt    <= 8;
            shift_reg  <= 0;
        end 
            case (state)
                IDLE: begin
                    busy      <= 0;
                    ack_error <= 0;
                    byte_idx  <= 0;
                    sda_en    <= 0;
                    sda_out   <= 1;
                end

                START: begin
                    if (scl_mid_tick == LOW) begin
                        busy    <= 1;
                        sda_en  <= 1;
                        sda_out <= 0; // Pull SDA low

                        shift_reg <= {slave_addr, 1'b0}; // 7-bit addr + write bit
                        bit_cnt   <= 8;
                    end
                end

                SEND_BIT: begin
                    if (scl_mid_tick == LOW) begin
                        if (bit_cnt > 1) sda_out <= shift_reg[bit_cnt - 1];
                        if (bit_cnt > 0) bit_cnt <= bit_cnt - 1;
                    end
                end

                CHECK_ACK: begin
                    if (scl_mid_tick == LOW) begin
                        sda_en <= 0; // Release SDA for ACK from slave

                        // Uncomment to pass ACK in testbench
                        //sda_end <= 1;
                        //sda_out <= 0;
                        
                        if (sda === 1'b1) ack_error <= 1;
                        byte_idx <= byte_idx + 1;

                        // Prepare next byte to send if there is any
                        if (byte_idx < data_len) begin
                            shift_reg <= data_in[byte_idx];
                            bit_cnt   <= 8;
                        end

                    end
                end

                STOP: begin
                    if (scl_mid_tick == HIGH) begin
                        sda_en  <= 1;
                        sda_out <= 1; // Send stop (SDA goes high while SCL is high)
                    end
                end
            endcase
        end

endmodule
