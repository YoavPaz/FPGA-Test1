module VCNL4040 #(
    parameter I2C_SPEED = 100_000,
    parameter CLK_SPEED = 27_000_000
)(
    input wire clk,
    inout wire scl,
    inout wire sda,
    output reg [15:0] out
);

// STATES
localparam
    IDLE = 0,
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
    STOP = 13;

reg [3:0] state = IDLE;

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
reg [3:0] bit_counter = 0;

always @(posedge clk ) begin
    case (state)
        IDLE: begin
            scl_hold <= RELEASE;
            sda_hold <= RELEASE;
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
            if (bit_counter == 8) begin
                scl_hold <= RELEASE;
                state <= READ_ADDRESS_ACK_W;
                bit_counter <= 0;
            end else begin
                if (scl_hold == LOW) begin
                    scl_hold <= RELEASE;
                end else begin
                    scl_hold <= LOW;
                    sda_hold <= address_w[7 - bit_counter];
                    bit_counter <= bit_counter + 1'b1;
                end
            end
        end

        READ_ADDRESS_ACK_W: begin
            if (scl_hold == LOW) begin
                scl_hold <= RELEASE;
            end else begin
                if (sda == 1'b0) begin
                    scl_hold <= LOW;
                    state <= SEND_REGISTER;
                end else begin
                    scl_hold <= LOW;
                    state <= IDLE;
                end
            end
        end

        SEND_REGISTER: begin
            if (bit_counter == 8) begin
                scl_hold <= RELEASE;
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
            if (scl_hold == LOW) begin
                scl_hold <= RELEASE;
            end else begin
                if (sda == 1'b0) begin
                    scl_hold <= LOW;
                    state <= REPEATED_START;
                end else begin
                    scl_hold <= LOW;
                    state <= IDLE;
                end
            end
        end

        REPEATED_START: begin
            if (scl_hold == RELEASE) begin
                sda_hold <= LOW;
                bit_counter <= 0;
                state <= SEND_ADDRESS_R;
            end else begin
                scl_hold <= RELEASE;
            end
        end

        SEND_ADDRESS_R: begin
            if (bit_counter == 8) begin
                scl_hold <= RELEASE;
                state <= READ_ACK_ADDRESS_R;
                bit_counter <= 0;
            end else begin
                if (scl_hold == LOW) begin
                    scl_hold <= RELEASE;
                end else begin
                    scl_hold <= LOW;
                    sda_hold <= address_r[7 - bit_counter];
                    bit_counter <= bit_counter + 1'b1
                end
            end
        end

        READ_ACK_ADDRESS_R: begin
            if (scl_hold == LOW) begin
                scl_hold <= RELEASE;
            end else begin
                if (sda == 1'b0) begin
                    scl_hold <= LOW;
                    state <= READ_LOW_BITS;
                end else begin
                    scl_hold <= LOW;
                    state <= IDLE;
                end
            end
        end

        READ_LOW_BITS: begin
            
        end
    endcase
end
    
endmodule
