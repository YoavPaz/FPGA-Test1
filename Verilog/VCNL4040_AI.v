module VCNL4040 #(
    parameter integer ClockSpeed = 100_000,
    parameter integer CLK_FREQ = 27_000_000
) (
    input  wire        clk,
    input  wire        start,
    inout  wire        scl,
    inout  wire        sda,
    output reg  [15:0] out = 16'b0
);

localparam [3:0]
    IDLE          = 4'd0,
    START         = 4'd1,
    TX_BYTE       = 4'd2,
    CHECK_ACK     = 4'd3,
    REPEATED_START= 4'd4,
    RX_BYTE       = 4'd5,
    SEND_ACK      = 4'd6,
    SEND_NACK     = 4'd7,
    STOP          = 4'd8;

localparam RELEASE = 1'b0;
localparam LOW     = 1'b1;

localparam integer DIVIDER_RAW = CLK_FREQ / (3 * ClockSpeed);
localparam integer DIVIDER =
    (DIVIDER_RAW > 0) ? DIVIDER_RAW : 1;
localparam integer COUNTER_WIDTH =
    (DIVIDER > 1) ? $clog2(DIVIDER) : 1;

reg [COUNTER_WIDTH-1:0] clk_counter = 0;
reg tick = 0;

reg [3:0] state = IDLE;
reg [1:0] phase = 0;
reg [3:0] bit_counter = 0;

// byte_index:
// 0 = slave write address
// 1 = register command
// 2 = configuration low byte
// 3 = configuration high byte
// 4 = slave read address

reg [2:0] byte_index = 0;
reg [7:0] tx_byte = 8'hC0;

reg [7:0] low_byte = 0;
reg [7:0] high_byte = 0;

reg sda_hold = RELEASE;
reg scl_hold = RELEASE;

reg start_pending = 0;
reg initialized = 0;
reg op_init = 0;
reg transaction_ok = 0;
reg rx_high = 0;

// Open-drain I2C: pull LOW or release.
// External pull-up resistors are required unless already
// provided by the sensor breakout board.
assign scl = scl_hold ? 1'b0 : 1'bz;
assign sda = sda_hold ? 1'b0 : 1'bz;

// Generate the internal timing tick and retain start requests.
always @(posedge clk) begin
    if (clk_counter >= DIVIDER - 1) begin
        clk_counter <= 0;
        tick <= 1'b1;
    end else begin
        clk_counter <= clk_counter + 1'b1;
        tick <= 1'b0;
    end

    if (start)
        start_pending <= 1'b1;
    else if (tick && state == IDLE && start_pending)
        start_pending <= 1'b0;
end

always @(posedge clk) begin
    if (tick) begin
        case (state)

            IDLE: begin
                scl_hold <= RELEASE;
                sda_hold <= RELEASE;
                phase <= 0;
                bit_counter <= 0;

                if (start_pending) begin
                    op_init <= !initialized;
                    transaction_ok <= 1'b1;
                    byte_index <= 0;
                    tx_byte <= 8'hC0;
                    low_byte <= 0;
                    high_byte <= 0;
                    state <= START;
                end
            end

            // START: SDA falls while SCL is released HIGH.
            START: begin
                case (phase)
                    0: begin
                        sda_hold <= RELEASE;
                        scl_hold <= RELEASE;
                        phase <= 1;
                    end

                    1: begin
                        sda_hold <= LOW;
                        phase <= 2;
                    end

                    2: begin
                        scl_hold <= LOW;
                        phase <= 0;
                        bit_counter <= 0;
                        tx_byte <= 8'hC0;
                        byte_index <= 0;
                        state <= TX_BYTE;
                    end
                endcase
            end

            // Send the current byte, MSB first.
            // IMPORTANT: invert the bit because sda_hold=1
            // means pull SDA LOW, while sda_hold=0 releases it.
            TX_BYTE: begin
                case (phase)
                    0: begin
                        sda_hold <= ~tx_byte[7-bit_counter];
                        phase <= 1;
                    end

                    1: begin
                        scl_hold <= RELEASE;
                        phase <= 2;
                    end

                    2: begin
                        scl_hold <= LOW;
                        phase <= 0;

                        if (bit_counter == 7) begin
                            bit_counter <= 0;
                            state <= CHECK_ACK;
                        end else begin
                            bit_counter <= bit_counter + 1'b1;
                        end
                    end
                endcase
            end

            // Release SDA for the ninth clock and check ACK.
            CHECK_ACK: begin
                case (phase)
                    0: begin
                        sda_hold <= RELEASE;
                        phase <= 1;
                    end

                    1: begin
                        scl_hold <= RELEASE;
                        phase <= 2;
                    end

                    2: begin
                        scl_hold <= LOW;
                        phase <= 0;

                        if (sda == 1'b0) begin
                            // Slave acknowledged the byte.
                            case (byte_index)

                                0: begin
                                    byte_index <= 1;
                                    tx_byte <= op_init
                                             ? 8'h03  // PS configuration
                                             : 8'h08; // proximity data
                                    state <= TX_BYTE;
                                end

                                1: begin
                                    if (op_init) begin
                                        // Write both configuration bytes.
                                        byte_index <= 2;
                                        tx_byte <= 8'h00;
                                        state <= TX_BYTE;
                                    end else begin
                                        // Select read direction.
                                        state <= REPEATED_START;
                                    end
                                end

                                2: begin
                                    byte_index <= 3;
                                    tx_byte <= 8'h00;
                                    state <= TX_BYTE;
                                end

                                3: begin
                                    // Configuration write completed.
                                    state <= STOP;
                                end

                                4: begin
                                    // Read address acknowledged.
                                    rx_high <= 1'b0;
                                    state <= RX_BYTE;
                                end

                                default: begin
                                    transaction_ok <= 1'b0;
                                    state <= STOP;
                                end

                            endcase
                        end else begin
                            // NACK: end this transaction without
                            // replacing the last valid output.
                            transaction_ok <= 1'b0;
                            state <= STOP;
                        end
                    end
                endcase
            end

            // Repeated START before reading the data register.
            REPEATED_START: begin
                case (phase)
                    0: begin
                        sda_hold <= RELEASE;
                        scl_hold <= LOW;
                        phase <= 1;
                    end

                    1: begin
                        scl_hold <= RELEASE;
                        phase <= 2;
                    end

                    2: begin
                        sda_hold <= LOW;
                        phase <= 3;
                    end

                    3: begin
                        scl_hold <= LOW;
                        phase <= 0;
                        bit_counter <= 0;
                        byte_index <= 4;
                        tx_byte <= 8'hC1;
                        state <= TX_BYTE;
                    end
                endcase
            end

            // Read one byte, MSB first.
            RX_BYTE: begin
                case (phase)
                    0: begin
                        sda_hold <= RELEASE;
                        phase <= 1;
                    end

                    1: begin
                        scl_hold <= RELEASE;
                        phase <= 2;
                    end

                    2: begin
                        if (rx_high)
                            high_byte[7-bit_counter] <= sda;
                        else
                            low_byte[7-bit_counter] <= sda;

                        scl_hold <= LOW;
                        phase <= 0;

                        if (bit_counter == 7) begin
                            bit_counter <= 0;

                            if (rx_high)
                                state <= SEND_NACK;
                            else
                                state <= SEND_ACK;
                        end else begin
                            bit_counter <= bit_counter + 1'b1;
                        end
                    end
                endcase
            end

            // ACK the first byte so the sensor sends the second.
            SEND_ACK: begin
                case (phase)
                    0: begin
                        sda_hold <= LOW;
                        phase <= 1;
                    end

                    1: begin
                        scl_hold <= RELEASE;
                        phase <= 2;
                    end

                    2: begin
                        scl_hold <= LOW;
                        sda_hold <= RELEASE;
                        phase <= 0;
                        rx_high <= 1'b1;
                        state <= RX_BYTE;
                    end
                endcase
            end

            // NACK the final byte to end the read.
            SEND_NACK: begin
                case (phase)
                    0: begin
                        sda_hold <= RELEASE;
                        phase <= 1;
                    end

                    1: begin
                        scl_hold <= RELEASE;
                        phase <= 2;
                    end

                    2: begin
                        scl_hold <= LOW;
                        phase <= 0;
                        state <= STOP;
                    end
                endcase
            end

            // STOP: SDA rises while SCL is released HIGH.
            STOP: begin
                case (phase)
                    0: begin
                        scl_hold <= LOW;
                        sda_hold <= LOW;
                        phase <= 1;
                    end

                    1: begin
                        scl_hold <= RELEASE;
                        phase <= 2;
                    end

                    2: begin
                        sda_hold <= RELEASE;
                        phase <= 0;
                        bit_counter <= 0;

                        if (transaction_ok) begin
                            if (op_init)
                                initialized <= 1'b1;
                            else
                                out <= {high_byte, low_byte};
                        end

                        state <= IDLE;
                    end
                endcase
            end

            default: begin
                state <= IDLE;
                phase <= 0;
                bit_counter <= 0;
                sda_hold <= RELEASE;
                scl_hold <= RELEASE;
                transaction_ok <= 1'b0;
            end

        endcase
    end
end

endmodule
