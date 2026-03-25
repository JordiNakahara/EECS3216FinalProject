// ball_controller.v
// Handles ball physics driven by accelerometer X-axis data.
// Ball rolls on a platform rectangle. Scoring counts frames ball stays in safe zone.
// Outputs ball position, platform position, safe zone, score, and game-over flag.

module ball_controller (
    input             clk,          // pixel clock (25 MHz)
    input             reset_n,      // active-low reset

    // Accelerometer
    input signed [9:0] x_accel,     // signed X acceleration
    input              accel_valid,  // pulse when new accel data available

    // Outputs for renderer
    output reg [9:0]  ball_x,       // ball centre X
    output reg [8:0]  ball_y,       // ball centre Y
    output reg [9:0]  plat_x,       // platform left edge X
    output reg [8:0]  plat_y,       // platform top edge Y
    output reg [9:0]  safe_x,       // safe zone left X
    output reg [9:0]  safe_w,       // safe zone width
    output reg [23:0] score,        // BCD-like frame counter (simple binary here)
    output reg        game_over     // asserted when ball leaves safe zone
);

    // ---- Layout constants (640x480 display) ----
    localparam PLAT_W   = 500;   // platform width  (pixels)
    localparam PLAT_H   = 10;    // platform height (pixels)
    localparam PLAT_X0  = 70;    // platform left X (centred)
    localparam PLAT_Y0  = 380;   // platform top  Y

    localparam SAFE_W   = 100;   // safe zone width
    localparam SAFE_X0  = PLAT_X0 + (PLAT_W - SAFE_W) / 2; // centred on platform

    localparam BALL_R   = 8;     // ball radius (pixels)
    localparam BALL_Y0  = PLAT_Y0 - BALL_R; // ball rests on platform top

    // Ball X range: left wall = PLAT_X0+BALL_R, right wall = PLAT_X0+PLAT_W-BALL_R
    localparam BALL_XMIN = PLAT_X0 + BALL_R;
    localparam BALL_XMAX = PLAT_X0 + PLAT_W - BALL_R;

    // Safe zone x range for ball centre
    localparam SAFE_XMIN = SAFE_X0;
    localparam SAFE_XMAX = SAFE_X0 + SAFE_W;

    // ---- Ball velocity (fixed-point: lower 4 bits = fraction) ----
    reg signed [13:0] ball_vx;   // Q10.4 fixed-point velocity
    reg signed [13:0] ball_px;   // Q10.4 fixed-point position

    // ---- Score frame divider (count every ~60 pixel-clock frames) ----
    // VGA frame = 800*525 = 420000 pixel clocks ~ 420k cycles at 25MHz
    localparam FRAME_PERIOD = 420000;
    reg [18:0] frame_cnt;

    // ---- Acceleration scale: shift accel right by 3 (divide by 8) ----
    // This gives gentle rolling feel
    wire signed [9:0] accel_scaled = x_accel >>> 3;

    // ---- Initialise constants ----
    initial begin
        ball_x   = (BALL_XMIN + BALL_XMAX) / 2;
        ball_y   = BALL_Y0;
        ball_px  = ball_x << 4;
        ball_vx  = 0;
        plat_x   = PLAT_X0;
        plat_y   = PLAT_Y0;
        safe_x   = SAFE_X0;
        safe_w   = SAFE_W;
        score    = 0;
        game_over = 0;
        frame_cnt = 0;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ball_x    <= (BALL_XMIN + BALL_XMAX) / 2;
            ball_y    <= BALL_Y0;
            ball_px   <= ((BALL_XMIN + BALL_XMAX) / 2) << 4;
            ball_vx   <= 0;
            score     <= 0;
            game_over <= 0;
            frame_cnt <= 0;
        end else begin

            // ------ Update ball physics on new accelerometer reading ------
            if (accel_valid && !game_over) begin
                // Apply acceleration (add scaled accel to velocity)
                ball_vx <= ball_vx + {{4{accel_scaled[9]}}, accel_scaled};

                // Clamp velocity to +-15 (Q10.4 = +-240 raw)
                if (ball_vx > 14'd240)  ball_vx <= 14'd240;
                if (ball_vx < -14'd240) ball_vx <= -14'd240;

                // Apply friction (multiply by ~0.9 each tick)
                ball_vx <= (ball_vx * 14'd14) >>> 4; // * 14/16 ≈ 0.875

                // Update position
                ball_px <= ball_px + ball_vx;

                // Wall collision (bounce with damping)
                if ((ball_px >>> 4) <= BALL_XMIN) begin
                    ball_px <= BALL_XMIN << 4;
                    ball_vx <= -(ball_vx >>> 1); // reverse, halve speed
                end
                if ((ball_px >>> 4) >= BALL_XMAX) begin
                    ball_px <= BALL_XMAX << 4;
                    ball_vx <= -(ball_vx >>> 1);
                end

                // Update integer position output
                ball_x <= ball_px[13:4];
            end

            // ------ Score counter (increment each frame ball is in safe zone) ------
            frame_cnt <= frame_cnt + 1;
            if (frame_cnt == FRAME_PERIOD) begin
                frame_cnt <= 0;
                if (!game_over) begin
                    // Check if ball centre is within safe zone
                    if ((ball_x >= SAFE_XMIN) && (ball_x <= SAFE_XMAX)) begin
                        score <= score + 1;
                    end else begin
                        // Ball left safe zone – game over
                        game_over <= 1;
                    end
                end
            end

        end
    end

    // Static assignments
    always @(*) begin
        ball_y = BALL_Y0;
        plat_x = PLAT_X0;
        plat_y = PLAT_Y0;
        safe_x = SAFE_X0;
        safe_w = SAFE_W;
    end

endmodule
