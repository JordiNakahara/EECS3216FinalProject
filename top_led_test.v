// top_led_test.v  -- RAW ACCELEROMETER DEBUG VERSION
// 
// Bypasses all physics. Displays raw ADXL345 X-axis value directly:
//   - HEX3-HEX0 : raw signed decimal value from accelerometer (-512 to +511)
//   - HEX5      : shows "n" if data_valid has never pulsed (no comms)
//                 shows "-" if x_accel is negative
//                 blank if positive
//   - LEDR[9:0] : 10-bit raw magnitude of x_accel (unsigned, MSB on left)
//   - KEY[0]    : reset
//
// If the accelerometer is working, tilting the board left/right should
// change the HEX readout and shift the LED pattern.
// If HEX shows "----" and LEDs never change, SPI is not communicating.

module top_led_test (
    input        MAX10_CLK1_50,
    input  [1:0] KEY,

    output [9:0] LEDR,

    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5,

    output       GSENSOR_SCLK,
    output       GSENSOR_SDI,
    input        GSENSOR_SDO,
    output       GSENSOR_CS_N
);

    wire reset_n = KEY[0];

    // ---- Accelerometer ----
    wire signed [9:0] x_accel;
    wire              data_valid;

    accelerometer_spi accel_inst (
        .clk        (MAX10_CLK1_50),
        .reset_n    (reset_n),
        .sclk       (GSENSOR_SCLK),
        .cs_n       (GSENSOR_CS_N),
        .mosi       (GSENSOR_SDI),
        .miso       (GSENSOR_SDO),
        .x_accel    (x_accel),
        .data_valid (data_valid)
    );

    // ---- Latch data_valid so we know comms ever worked ----
    reg ever_valid;
    always @(posedge MAX10_CLK1_50 or negedge reset_n) begin
        if (!reset_n) ever_valid <= 1'b0;
        else if (data_valid) ever_valid <= 1'b1;
    end

    // ---- Show raw x_accel on LEDs as 10-bit magnitude ----
    // Show absolute value so we can see deflection regardless of sign
    wire [9:0] accel_mag = x_accel[9] ? (~x_accel + 10'd1) : x_accel;
    assign LEDR = accel_mag;

    // ---- Convert absolute value to 4 decimal digits ----
    wire [9:0] abs_val  = accel_mag;
    wire [3:0] d0 = abs_val % 10;
    wire [3:0] d1 = (abs_val / 10)  % 10;
    wire [3:0] d2 = (abs_val / 100) % 10;

    // ---- 7-segment decoder ----
    function [6:0] seg7;
        input [3:0] d;
        case (d)
            4'd0: seg7 = 7'b1000000;
            4'd1: seg7 = 7'b1111001;
            4'd2: seg7 = 7'b0100100;
            4'd3: seg7 = 7'b0110000;
            4'd4: seg7 = 7'b0011001;
            4'd5: seg7 = 7'b0010010;
            4'd6: seg7 = 7'b0000010;
            4'd7: seg7 = 7'b1111000;
            4'd8: seg7 = 7'b0000000;
            4'd9: seg7 = 7'b0010000;
            default: seg7 = 7'b1111111;
        endcase
    endfunction

    localparam SEG_BLANK = 7'b1111111;
    localparam SEG_DASH  = 7'b0111111; // minus sign
    localparam SEG_n     = 7'b0101011; // lowercase n (no comms indicator)
    localparam SEG_0     = 7'b1000000;

    assign HEX0 = seg7(d0);
    assign HEX1 = seg7(d1);
    assign HEX2 = seg7(d2);
    assign HEX3 = SEG_BLANK;           // hundreds never > 5 so leave blank
    assign HEX4 = x_accel[9] ? SEG_DASH  : SEG_BLANK; // sign
    assign HEX5 = ~ever_valid ? SEG_n : SEG_BLANK;     // 'n' = no comms yet

endmodule