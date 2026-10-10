module Main(
    input wire clk,
    inout wire scl,
    inout wire sda,
    output wire pwm,
    output reg led1 = 1'b0
);

// =======================
// PWM TEST
// =======================
/*reg [6:0] duty_cycle = 7'd50;

PWM #(
    .total_ticks(100_000)
) pwm_test(
    .clk(clk),
    .duty_cycle(duty_cycle),
    .pwmOut(pwm)
);

reg[24:0] counter = 1'b0;

always @(posedge clk ) begin
    if (counter > 27_000_000) begin
        counter <= 1'b0;
        if (duty_cycle == 50) begin
            duty_cycle <= 7'd10;
        end else begin
            duty_cycle <= 7'd50;
        end
    end else begin
        counter <= counter + 1'b1;
    end
end*/

// =======================
// VCNL4040 TEST
// =======================

reg [24:0] start_counter = 0;
reg start = 1'b0;

wire [15:0] sensor_data;

VCNL4040 #(
    .ClockSpeed(100_000),
    .CLK_FREQ(27_000_000)
) sensor (
    .clk(clk),
    .start(start),
    .scl(scl),
    .sda(sda),
    .out(sensor_data)
);

always @(posedge clk) begin
    start <= 1'b0;

    if (start_counter >= 27_000_000 - 1) begin
        start_counter <= 0;
        start <= 1'b1;
    end else begin
        start_counter <= start_counter + 1'b1;
    end

    led1 <= (sensor_data > 16'd1) ? 1'b0 : 1'b1;
end

assign pwm = 1'b0;

endmodule
