module VCNL4040 #(
    parameter I2C_SPEED = 100_000,
    parameter CLK_SPEED = 27_000_000
)(
    input wire clk,
    inout wire scl,
    inout wire sda,
    input wire btn1,
    output reg [15:0] out
);

// STATES
localparam
    IDLE = 0,
    BEFORE_START = 17,
    START = 1,
    SEND_ADDRESS_W = 2,
    READ_ADDRESS_ACK_W = 3,
    SEND_REGISTER = 4,
    READ_REGISTER_ACK = 5,
    REPEATED_START = 6,
    SEND_ADDRESS_R = 7,
    READ_ACK_ADDRESS_R = 8,
    READ_LOW_BITS = 9,
    SEND_ACK = 10,
    READ_HIGH_BITS = 11,
    SEND_NACK = 12,
    STOP = 13,
    STOP_PREPARE = 18,
    STOP_RELEASE_SCL = 19,
    STOP_RELEASE_SDA = 20,
    REPEATED_START_LOW = 14,
    REPEATED_START_RELEASE_SCL = 15,
    REPEATED_START_CONDITION = 16;

reg [4:0] state = IDLE;

// ACK/NACK
localparam 
   ACK = 0,
   NACK = 1;

localparam
    LOW = 0,
    RELEASE = 1;

reg scl_hold = RELEASE;
reg sda_hold = RELEASE;

assign scl = (!scl_hold) ? 1'b0 : 1'bz;
assign sda = (!sda_hold) ? 1'b0 : 1'bz;

reg [7:0] address_w = {7'h60, 1'b0};
reg [7:0] address_r = {7'h60, 1'b1};
reg [7:0] register_w = 8'h08;
reg [7:0] data_low = 8'd0;
reg [7:0] data_high = 8'd0;
reg [3:0] bit_counter = 0;
reg [1:0] ack_phase = 0;

localparam integer HALF_PERIOD = CLK_SPEED / (2 * I2C_SPEED);

reg [31:0] clk_counter = 0;
reg tick = 0;

reg btn_sync0 = 1'b1;
reg btn_sync1 = 1'b1;
reg btn_prev  = 1'b1;

wire button_press = btn_prev && !btn_sync1;
reg start_pending = 1'b0;

always @(posedge clk) begin
    btn_sync0 <= btn1;
    btn_sync1 <= btn_sync0;
    btn_prev  <= btn_sync1;
end

always @(posedge clk) begin
    if (clk_counter >= HALF_PERIOD - 1) begin
        clk_counter <= 0;
        tick <= 1'b1;
    end else begin
        clk_counter <= clk_counter + 1'b1;
        tick <= 1'b0;
    end
end

reg ack_received = 1'b0;

always @(posedge clk ) begin
    if (button_press && state == IDLE && !start_pending)
        start_pending <= 1'b1;

    if (tick) begin
        case (state)
            IDLE: begin
                scl_hold <= RELEASE;
                sda_hold <= RELEASE;

                if (start_pending) begin
                    start_pending <= 1'b0;
                    bit_counter <= 0;
                    state <= BEFORE_START;
                end
            end

            BEFORE_START: begin
                if (scl_hold == RELEASE && sda_hold == RELEASE) begin
                    state <= START;
                end else begin
                    scl_hold = RELEASE;
                    sda_hold = RELEASE;
                end
            end

            START: begin
                if (sda_hold == LOW) begin
                    state <= SEND_ADDRESS_W;
                end else begin
                    scl_hold <= RELEASE;
                    sda_hold <= LOW;
                end
            end

            SEND_ADDRESS_W: begin
                if (scl_hold == LOW) begin
                    scl_hold <= RELEASE;
                end else if (bit_counter == 8) begin
                    scl_hold <= LOW;
                    sda_hold <= RELEASE;
                    state <= READ_ADDRESS_ACK_W;
                    bit_counter <= 0;
                    ack_phase <= 0;
                end else begin
                    scl_hold <= LOW;
                    sda_hold <= address_w[7 - bit_counter];
                    bit_counter <= bit_counter + 1'b1;
                end
            end

            READ_ADDRESS_ACK_W: begin
                case (ack_phase)
                    0: begin
                        // Keep SCL low and release SDA.
                        scl_hold <= LOW;
                        sda_hold <= RELEASE;
                        ack_phase <= 1;
                    end

                    1: begin
                        // Raise SCL to start the ACK clock.
                        scl_hold <= RELEASE;
                        ack_phase <= 2;
                    end

                    2: begin
                        // SCL is high: sample the sensor's ACK.
                        ack_received <= (sda == 1'b0);
                        scl_hold <= LOW;
                        ack_phase <= 0;

                        if (sda == 1'b0)
                            state <= SEND_REGISTER;
                        else
                            state <= IDLE;
                    end

                    default: ack_phase <= 0;
                endcase
            end

            SEND_REGISTER: begin
                if (bit_counter == 8) begin
                    scl_hold <= LOW;
                    sda_hold <= RELEASE;
                    ack_phase <= 0;
                    state <= READ_REGISTER_ACK;
                    bit_counter <= 0;
                end else begin
                    if (scl_hold == LOW) begin
                        scl_hold <= RELEASE;
                    end else begin
                        scl_hold <= LOW;
                        sda_hold <= register_w[7 - bit_counter];
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
            end

            READ_REGISTER_ACK: begin
                case (ack_phase)
                    0: begin
                        // SCL is already LOW.
                        sda_hold <= RELEASE;
                        scl_hold <= RELEASE;
                        ack_phase <= 1;
                    end

                    1: begin
                        // SCL is HIGH. Sample the sensor's ACK.
                        if (sda == 1'b0) begin
                            ack_phase <= 2;
                        end else begin
                            ack_phase <= 2;
                        end
                    end

                    2: begin
                        // End the ACK clock.
                        scl_hold <= LOW;
                        ack_phase <= 0;

                        if (sda == 1'b0) begin
                            state <= REPEATED_START;
                        end else begin
                            state <= IDLE;
                        end
                    end

                    default: begin
                        ack_phase <= 0;
                    end
                endcase
            end

            REPEATED_START: begin
                // First, pull SCL low and release SDA
                scl_hold <= LOW;
                sda_hold <= RELEASE;
                state <= REPEATED_START_RELEASE_SCL;
            end

            REPEATED_START_RELEASE_SCL: begin
                // Release SCL while SDA remains released
                scl_hold <= RELEASE;
                state <= REPEATED_START_CONDITION;
            end

            REPEATED_START_CONDITION: begin
                // SDA falls while SCL is high: repeated START
                sda_hold <= LOW;
                bit_counter <= 0;
                state <= SEND_ADDRESS_R;
            end

            SEND_ADDRESS_R: begin
                if (bit_counter == 8) begin
                    scl_hold <= LOW;
                    sda_hold <= RELEASE;
                    ack_phase <= 0;
                    state <= READ_ACK_ADDRESS_R;
                    bit_counter <= 0;
                end else begin
                    if (scl_hold == LOW) begin
                        scl_hold <= RELEASE;
                    end else begin
                        scl_hold <= LOW;
                        sda_hold <= address_r[7 - bit_counter];
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
            end

            READ_ACK_ADDRESS_R: begin
                case (ack_phase)
                    0: begin
                        // SCL is already LOW.
                        sda_hold <= RELEASE;
                        scl_hold <= RELEASE;
                        ack_phase <= 1;
                    end

                    1: begin
                        // SCL is HIGH. Sample the sensor's ACK.
                        if (sda == 1'b0) begin
                            ack_phase <= 2;
                        end else begin
                            ack_phase <= 2;
                        end
                    end

                    2: begin
                        // End the ACK clock.
                        scl_hold <= LOW;
                        ack_phase <= 0;

                        if (sda == 1'b0) begin
                            bit_counter <= 0;
                            state <= READ_LOW_BITS;
                        end else begin
                            state <= IDLE;
                        end
                    end

                    default: begin
                        ack_phase <= 0;
                    end
                endcase
            end

            READ_LOW_BITS: begin
                sda_hold <= RELEASE;

                if (bit_counter == 8) begin
                    bit_counter <= 0;
                    scl_hold <= LOW;
                    state <= SEND_ACK;
                end else begin
                    if (scl_hold == LOW) begin
                        scl_hold <= RELEASE;
                    end else begin
                        data_low[7 - bit_counter] <= sda;
                        scl_hold <= LOW;
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
            end

            SEND_ACK: begin
                sda_hold <= LOW;

                if (scl_hold == LOW) begin
                    scl_hold <= RELEASE;
                end else begin
                    scl_hold <= LOW;
                    sda_hold <= RELEASE; 
                    bit_counter <= 0;
                    state <= READ_HIGH_BITS;
                end
            end

            READ_HIGH_BITS: begin
                sda_hold <= RELEASE;

                if (bit_counter == 8) begin
                    bit_counter <= 0;
                    scl_hold <= LOW;
                    state <= SEND_NACK;
                end else begin
                    if (scl_hold == LOW) begin
                        scl_hold <= RELEASE;
                    end else begin
                        data_high[7 - bit_counter] <= sda;
                        sda_hold <= LOW;
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
            end

            SEND_NACK: begin
                sda_hold <= RELEASE;

                if (scl_hold == LOW) begin
                    scl_hold <= RELEASE;
                end else begin
                    scl_hold <= LOW;
                    bit_counter <= 0;
                    state <= STOP;
                end
            end

            STOP: begin
                scl_hold <= LOW;
                sda_hold <= LOW;
                state <= STOP_RELEASE_SCL;
            end

            STOP_RELEASE_SCL: begin
                scl_hold <= RELEASE;
                state <= STOP_RELEASE_SDA;
            end

            STOP_RELEASE_SDA: begin
                sda_hold <= RELEASE;
                state <= IDLE;

                out <= {data_high, data_low};
            end
        endcase
    end
end
    
endmodule
