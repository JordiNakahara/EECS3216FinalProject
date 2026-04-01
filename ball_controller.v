// ball_controller.v
// Handles ball physics driven by accelerometer X-axis data.
// Ball rolls on a platform. Scoring counts VGA frames ball stays in safe zone.
// Game ends when the ball leaves the safe zone.

module ball_controller (
    input              clk,         // pixel clock (25 MHz)
    input              reset_n,     // active-low async reset

    // Accelerometer
    input  signed [9:0] x_accel,    // signed 10-bit X acceleration
    input               accel_valid, // pulses high for 1 clk when new data ready

    // Outputs for renderer
    output reg  [9:0]  ball_x,      // ball centre X (integer pixels)
    output      [8:0]  ball_y,      // ball centre Y - static constant
    output      [9:0]  plat_x,      // platform left X - static constant
    output      [8:0]  plat_y,      // platform top  Y - static constant
    output      [9:0]  safe_x,      // safe zone left X - static constant
    output      [9:0]  safe_w,      // safe zone width  - static constant
    output reg  [23:0] score,       // binary score (increments each frame in safe zone)
    output reg         game_over,   // held high once ball leaves safe zone
    output reg         game_win
);

    localparam integer PLAT_W    = 500;
    localparam integer PLAT_X0   = 70;
    localparam integer PLAT_Y0   = 380;
    localparam integer SAFE_W_C  = 100;
    localparam integer SAFE_X0   = PLAT_X0 + (PLAT_W - SAFE_W_C) / 2;
    localparam integer BALL_R    = 8;
    localparam integer BALL_Y0   = PLAT_Y0 - BALL_R;
    localparam integer BALL_XMIN = PLAT_X0 + BALL_R;
    localparam integer BALL_XMAX = PLAT_X0 + PLAT_W - BALL_R;
    localparam integer BALL_X0   = (BALL_XMIN + BALL_XMAX) / 2;
    localparam integer SAFE_XMIN = SAFE_X0;
    localparam integer SAFE_XMAX = SAFE_X0 + SAFE_W_C;

    assign ball_y = BALL_Y0[8:0];
    assign plat_x = PLAT_X0[9:0];
    assign plat_y = PLAT_Y0[8:0];
    assign safe_x = SAFE_X0[9:0];
    assign safe_w = SAFE_W_C[9:0];

    reg signed [15:0] ball_px;
    reg signed [15:0] ball_vx;

    // Increased sensitivity (was >>> 3)
    wire signed [9:0] accel_s = x_accel >>> 1;

    wire signed [15:0] vx_after_accel = ball_vx + {{6{accel_s[9]}}, accel_s};

    wire signed [15:0] vx_clamped =
        (vx_after_accel >  16'sd240) ?  16'sd240 :
        (vx_after_accel < -16'sd240) ? -16'sd240 :
         vx_after_accel;

    wire signed [15:0] vx_friction = vx_clamped - (vx_clamped >>> 3);
    wire signed [15:0] px_next = ball_px + vx_friction;

    wire wall_left  = (px_next >>> 4) <= $signed(16'd0 + BALL_XMIN);
    wire wall_right = (px_next >>> 4) >= $signed(16'd0 + BALL_XMAX);

    wire signed [15:0] px_final =
        wall_left  ? $signed(BALL_XMIN << 4) :
        wall_right ? $signed(BALL_XMAX << 4) :
        px_next;

    wire signed [15:0] vx_final =
        (wall_left || wall_right) ? -(vx_friction >>> 1) :
        vx_friction;

    localparam integer FRAME_PERIOD = 420000;
    reg [18:0] frame_cnt;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ball_px   <= $signed(BALL_X0 << 4);
            ball_vx   <= 16'sd0;
            ball_x    <= BALL_X0[9:0];
            score     <= 24'd0;
            game_over <= 1'b0;
            game_win  <= 1'b0;
            frame_cnt <= 19'd0;
        end else begin

            if (accel_valid && !game_over && !game_win) begin
                ball_vx <= vx_final;
                ball_px <= px_final;
                ball_x  <= px_final[13:4];
            end

            if (frame_cnt == FRAME_PERIOD - 1) begin
                frame_cnt <= 19'd0;
                if (!game_over && !game_win) begin
                    if ((ball_x >= SAFE_XMIN[9:0]) && (ball_x <= SAFE_XMAX[9:0])) begin
                        if (score == 24'd9999) begin
                            game_win <= 1'b1;
                        end else begin
                            score <= score + 24'd1;
                        end
                    end else begin
                        game_over <= 1'b1;
                    end
                end
            end else begin
                frame_cnt <= frame_cnt + 19'd1;
            end

        end
    end

endmodule