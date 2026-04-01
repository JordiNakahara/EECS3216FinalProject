// ball_controller.v
// Ball physics driven by ADXL345 X-axis accelerometer data.
// Physics update rate = accel_valid pulse rate (~200 Hz at 5ms gap).
// Dead-zone applied so a flat board gives zero net force.

module ball_controller (
    input              clk,
    input              reset_n,

    input  signed [9:0] x_accel,
    input               accel_valid,

    output reg  [9:0]  ball_x,
    output      [8:0]  ball_y,
    output      [9:0]  plat_x,
    output      [8:0]  plat_y,
    output      [9:0]  safe_x,
    output      [9:0]  safe_w,
    output reg  [23:0] score,
    output reg         game_over
);

    // -----------------------------------------------------------------------
    // Layout constants
    // -----------------------------------------------------------------------
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

    // Dead-zone: ignore accel values smaller than this (covers board-level noise)
    localparam integer DEAD_ZONE = 15;

    // Static wire outputs
    assign ball_y = BALL_Y0[8:0];
    assign plat_x = PLAT_X0[9:0];
    assign plat_y = PLAT_Y0[8:0];
    assign safe_x = SAFE_X0[9:0];
    assign safe_w = SAFE_W_C[9:0];

    // -----------------------------------------------------------------------
    // Q10.4 signed fixed-point physics
    // -----------------------------------------------------------------------
    reg signed [15:0] ball_px;
    reg signed [15:0] ball_vx;

    // Apply dead-zone: treat small accel as zero
    wire signed [9:0] accel_dz =
        (x_accel >  $signed(DEAD_ZONE)) ? (x_accel - $signed(DEAD_ZONE)) :
        (x_accel < -$signed(DEAD_ZONE)) ? (x_accel + $signed(DEAD_ZONE)) :
        10'sd0;

    // Scale down: divide by 4 for comfortable speed
    wire signed [9:0] accel_s = accel_dz >>> 2;

    // Next-state combinational wires
    wire signed [15:0] vx_after_accel = ball_vx + {{6{accel_s[9]}}, accel_s};

    wire signed [15:0] vx_clamped =
        (vx_after_accel >  16'sd192) ?  16'sd192 :
        (vx_after_accel < -16'sd192) ? -16'sd192 :
         vx_after_accel;

    // Friction: vx * 7/8
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

    // -----------------------------------------------------------------------
    // Frame counter for scoring: count accel_valid pulses (~200/sec)
    // Award a point every 200 pulses the ball stays in the safe zone (~1/sec)
    // -----------------------------------------------------------------------
    localparam integer SCORE_PERIOD = 200;
    reg [7:0] pulse_cnt;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ball_px   <= $signed(BALL_X0 << 4);
            ball_vx   <= 16'sd0;
            ball_x    <= BALL_X0[9:0];
            score     <= 24'd0;
            game_over <= 1'b0;
            pulse_cnt <= 8'd0;
        end else begin

            if (accel_valid && !game_over) begin

                // ---- Physics ----
                ball_vx <= vx_final;
                ball_px <= px_final;
                ball_x  <= px_final[13:4];

                // ---- Scoring ----
                if (pulse_cnt == SCORE_PERIOD - 1) begin
                    pulse_cnt <= 8'd0;
                    if ((px_final[13:4] >= SAFE_XMIN[9:0]) &&
                        (px_final[13:4] <= SAFE_XMAX[9:0])) begin
                        score <= score + 24'd1;
                    end else begin
                        game_over <= 1'b1;
                    end
                end else begin
                    pulse_cnt <= pulse_cnt + 8'd1;
                end

            end
        end
    end

endmodule