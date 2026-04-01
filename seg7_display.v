// seg7_display.v
// Drives the 6 x 7-segment displays on the DE10-Lite.
// Displays the score as decimal digits on HEX3-HEX0.
// Displays "Go" on HEX5-HEX4 when game_over is high.
// Displays "Hi" on HEX5-HEX4 when game_win is high (9999 victory).
// Active-low segments.

module seg7_display (
    input      [23:0] score,      // binary score value (displayed in decimal)
    input             game_over,
    input             game_win,
    output reg [6:0]  hex0,       // rightmost digit (ones)
    output reg [6:0]  hex1,
    output reg [6:0]  hex2,
    output reg [6:0]  hex3,
    output reg [6:0]  hex4,
    output reg [6:0]  hex5
);

    // ---- BCD conversion (simple combinational divide) ----
    wire [3:0] d0 = score % 10;
    wire [3:0] d1 = (score / 10)    % 10;
    wire [3:0] d2 = (score / 100)   % 10;
    wire [3:0] d3 = (score / 1000)  % 10;

    // ---- 7-segment decoder (active low) ----
    function [6:0] seg7;
        input [3:0] digit;
        case (digit)
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
            default: seg7 = 7'b1111111; // blank
        endcase
    endfunction

    // Special characters (active low)
    // "G" = 0b0000010  -> segments a,b,c,d,f = on  -> 7'b0000010  -- use 6: 0b0000010
    // "o" = 0b0100011  (small o: c,d,e,g)
    // "-" = 0b0111111  (just segment g)
    // Blank = 7'b1111111
    localparam SEG_G     = 7'b0000010; // G
    localparam SEG_O     = 7'b0100011; // o
    localparam SEG_BLANK = 7'b1111111;
    // "H" and "i" — [6:0] = gfedcba, active low (matches digit decoder)
    localparam SEG_H     = 7'b0001001; // H: b,c,e,f,g on
    localparam SEG_i     = 7'b1111101; // minimal i: b on only

    always @(*) begin
        if (game_win) begin
            hex5 = SEG_H;
            hex4 = SEG_i;
            hex3 = seg7(d3);
            hex2 = seg7(d2);
            hex1 = seg7(d1);
            hex0 = seg7(d0);
        end else if (game_over) begin
            hex5 = SEG_G;
            hex4 = SEG_O;
            hex3 = SEG_BLANK;
            hex2 = SEG_BLANK;
            hex1 = SEG_BLANK;
            hex0 = SEG_BLANK;
        end else begin
            hex5 = SEG_BLANK;
            hex4 = SEG_BLANK;
            hex3 = seg7(d3);
            hex2 = seg7(d2);
            hex1 = seg7(d1);
            hex0 = seg7(d0);
        end
    end

endmodule
