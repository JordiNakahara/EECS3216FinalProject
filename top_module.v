// top_module.v
// Ball-Balancing Game - EECS 3216 Project
// Group: Jordi Nakahara, Ryan Kwan
// Difficulty: B
//
// Description:
//   Tilt the DE10-Lite board to control a ball on a platform displayed via VGA.
//   The on-board ADXL345 accelerometer provides X-axis data.
//   A "safe zone" is drawn on the platform; the player scores points for keeping
//   the ball inside. The game ends when the ball leaves the safe zone.
//
// Top-level connections on DE10-Lite:
//   MAX10_CLK1_50  -> clk (50 MHz)
//   KEY[0]         -> reset_n (active low reset)
//   VGA_R/G/B      -> vga_r/g/b
//   VGA_HS/VS      -> hsync/vsync
//   GSENSOR_SCLK   -> accel_sclk
//   GSENSOR_SDIO   -> accel_data (3-wire bidirectional)
//   GSENSOR_CS_N   -> accel_cs_n
//   GSENSOR_INT    -> accel_data_ready interrupt
//   HEX0..HEX5     -> hex0..hex5

module top_module (
    input        MAX10_CLK1_50,   // 50 MHz system clock
    input  [1:0] KEY,             // KEY[0] = reset (active low)

    // VGA
    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B,
    output       VGA_HS,
    output       VGA_VS,

    // ADXL345 Accelerometer (3-wire SPI + interrupt)
    output       GSENSOR_SCLK,
    inout        GSENSOR_SDIO,
    output       GSENSOR_CS_N,
    input        GSENSOR_INT,

    // 7-segment displays
    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5
);

    // ---- Reset ----
    wire reset_n = KEY[0];   // active-low from push button

    // ---- PLL: 50 MHz -> 25.175 MHz pixel clock ----
    wire pixel_clk;
    pll pll_inst (
        .inclk0 (MAX10_CLK1_50),
        .c0     (pixel_clk)
    );

    // ---- VGA Controller ----
    wire        hsync, vsync, disp_ena;
    wire [31:0] vga_col, vga_row;

    vga_controller vga_ctrl (
        .pixel_clk (pixel_clk),
        .reset_n   (reset_n),
        .h_sync    (VGA_HS),
        .v_sync    (VGA_VS),
        .disp_ena  (disp_ena),
        .column    (vga_col),
        .row       (vga_row)
    );

    // ---- Accelerometer Interface (working module from DE10-Lite_Accelerometer) ----
    wire [9:0] x_accel_u;
    wire [9:0] y_accel_u;
    wire [9:0] z_accel_u;
    wire       accel_valid;
    wire signed [9:0] x_accel = x_accel_u;

    adxl345_interface accel_inst (
        .i_clk       (MAX10_CLK1_50),
        .i_rst_n     (reset_n),
        .o_data_x    (x_accel_u),
        .o_data_y    (y_accel_u),
        .o_data_z    (z_accel_u),
        .o_data_valid(accel_valid),
        .o_sclk      (GSENSOR_SCLK),
        .io_sdio     (GSENSOR_SDIO),
        .o_cs_n      (GSENSOR_CS_N),
        .i_int1      (GSENSOR_INT)
    );

    // ---- Startup splash gate ----
    // KEY[1] is active-low: game starts after first press.
    wire start_btn_n = KEY[1];
    reg  game_started;
    wire game_reset_n = reset_n && game_started;

    always @(posedge pixel_clk or negedge reset_n) begin
        if (!reset_n) begin
            game_started <= 1'b0;
        end else if (!start_btn_n) begin
            game_started <= 1'b1;
        end
    end

    // ---- Ball / Game Logic ----
    wire [9:0]  ball_x, plat_x, safe_x, safe_w_out;
    wire [8:0]  ball_y, plat_y;
    wire [23:0] score;
    wire        game_over;
    wire        game_win;

    ball_controller ball_ctrl (
        .clk        (pixel_clk),
        .reset_n    (game_reset_n),
        .x_accel    (x_accel),
        .accel_valid(accel_valid),
        .ball_x     (ball_x),
        .ball_y     (ball_y),
        .plat_x     (plat_x),
        .plat_y     (plat_y),
        .safe_x     (safe_x),
        .safe_w     (safe_w_out),
        .score      (score),
        .game_over  (game_over),
        .game_win   (game_win)
    );

    // ---- VGA Renderer ----
    vga_renderer renderer (
        .pixel_clk (pixel_clk),
        .disp_ena  (disp_ena),
        .row       (vga_row),
        .col       (vga_col),
        .ball_x    (ball_x),
        .ball_y    (ball_y),
        .plat_x    (plat_x),
        .plat_y    (plat_y),
        .safe_x    (safe_x),
        .safe_w    (safe_w_out),
        .game_over (game_over),
        .game_win  (game_win),
        .splash_active(!game_started),
        .vga_r     (VGA_R),
        .vga_g     (VGA_G),
        .vga_b     (VGA_B)
    );

    // ---- 7-Segment Score Display ----
    seg7_display score_disp (
        .score     (score),
        .game_over (game_over),
        .game_win  (game_win),
        .hex0      (HEX0),
        .hex1      (HEX1),
        .hex2      (HEX2),
        .hex3      (HEX3),
        .hex4      (HEX4),
        .hex5      (HEX5)
    );

endmodule
