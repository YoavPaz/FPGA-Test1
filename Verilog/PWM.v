// formula: HIGH = (DutyCycle/100) * TotalTicks

module PWM #(
    parameter total_ticks = 100_000
) (
    input wire clk,
    input wire [6:0] duty_cycle,
    output reg pwmOut = 0
);

    reg [31:0] counter = 0;

    always @(posedge clk ) begin
        if (counter >= total_ticks) begin
            counter <= 0;
        end else begin
            pwmOut = (counter < ((total_ticks * duty_cycle) / 100));
            counter <= counter + 1;
        end
    end
    
endmodule
