// vga_renderer.v
// Generates RGB pixel colours for each (row, col) coordinate output by vga_controller.
// Draws:
//   - Black background
//   - Grey platform rectangle
//   - Green safe zone (outlined)
//   - White ball (filled circle)
//   - Red "GAME OVER" flash (red screen tint) when game_over is asserted

module vga_renderer (
    input             pixel_clk,
    input             disp_ena,
    input      [31:0] row,
    input      [31:0] col,

    // Game state
    input      [9:0]  ball_x,
    input      [8:0]  ball_y,
    input      [9:0]  plat_x,
    input      [8:0]  plat_y,
    input      [9:0]  safe_x,
    input      [9:0]  safe_w,
    input             game_over,
    input             splash_active,

    // VGA colour outputs (4-bit per channel for DE10-Lite)
    output reg [3:0]  vga_r,
    output reg [3:0]  vga_g,
    output reg [3:0]  vga_b
);

    // ---- Layout constants (must match ball_controller.v) ----
    localparam PLAT_W  = 500;
    localparam PLAT_H  = 10;
    localparam BALL_R  = 8;

    // ---- Region detection (combinational) ----
    // Ball: filled circle  (col - ball_x)^2 + (row - ball_y)^2 <= R^2
    // Use squared distance, no sqrt needed. R=8 -> R^2=64
    wire signed [11:0] dx = $signed({1'b0, col[9:0]}) - $signed({1'b0, ball_x});
    wire signed [10:0] dy = $signed({1'b0, row[8:0]}) - $signed({1'b0, ball_y});
    wire [22:0] dist_sq = dx*dx + dy*dy;
    wire in_ball = (dist_sq <= (BALL_R * BALL_R));

    // Platform rectangle
    wire in_platform = (col >= plat_x) &&
                       (col <  plat_x + PLAT_W) &&
                       (row >= plat_y) &&
                       (row <  plat_y + PLAT_H);

    // Safe zone (just the top 2-pixel outline + filled lightly)
    wire in_safe_zone = (col >= safe_x) &&
                        (col <  safe_x + safe_w) &&
                        (row >= plat_y) &&
                        (row <  plat_y + PLAT_H);

    // Safe zone vertical boundary lines (for visibility on screen above platform)
    wire safe_left_line  = (col == safe_x)              && (row >= 200) && (row < plat_y);
    wire safe_right_line = (col == safe_x + safe_w - 1) && (row >= 200) && (row < plat_y);

    // Splash UI: border + "button" rectangle in centre.
    wire splash_border = (((col >= 80) && (col <= 560)) &&
                          ((row == 120) || (row == 360))) ||
                         (((row >= 120) && (row <= 360)) &&
                          ((col == 80) || (col == 560)));
    wire splash_button = (col >= 250) && (col < 390) && (row >= 220) && (row < 260);
    wire splash_button_inner = (col >= 258) && (col < 382) && (row >= 228) && (row < 252);

    always @(posedge pixel_clk) begin
        if (!disp_ena) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else if (splash_active) begin
            // Blue splash screen shown until KEY[1] is pressed.
            vga_r <= 4'h0;
            vga_g <= 4'h1;
            vga_b <= 4'h5;

            if (splash_border) begin
                vga_r <= 4'hA;
                vga_g <= 4'hA;
                vga_b <= 4'hF;
            end

            if (splash_button) begin
                vga_r <= 4'hF;
                vga_g <= 4'hB;
                vga_b <= 4'h0;
            end

            if (splash_button_inner) begin
                vga_r <= 4'hF;
                vga_g <= 4'hF;
                vga_b <= 4'h0;
            end
        end else if (game_over) begin
            // Pulsing red screen for game over
            vga_r <= 4'hF;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else begin
            // Default: black background
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;

            // Draw safe-zone vertical guide lines (green dashed)
            if (safe_left_line || safe_right_line) begin
                vga_r <= 4'h0;
                vga_g <= 4'hA;
                vga_b <= 4'h0;
            end

            // Draw platform (mid-grey)
            if (in_platform) begin
                vga_r <= 4'h8;
                vga_g <= 4'h8;
                vga_b <= 4'h8;
            end

            // Overlay safe zone on platform (bright green)
            if (in_safe_zone) begin
                vga_r <= 4'h0;
                vga_g <= 4'hF;
                vga_b <= 4'h2;
            end

            // Draw ball on top (white)
            if (in_ball) begin
                vga_r <= 4'hF;
                vga_g <= 4'hF;
                vga_b <= 4'hF;
            end
        end
    end

endmodule
