// accelerometer_spi.v
//
// ADXL345 SPI driver for DE10-Lite.
//
// SPI Mode 3: CPOL=1, CPHA=1
//   - SCLK idles HIGH
//   - MOSI shifts out on falling edge
//   - MISO sampled on rising edge
//
// Startup sequence:
//   1. 20 ms power-on delay
//   2. Write POWER_CTL  (0x2D) = 0x08  -> enables Measure mode
//   3. Write DATA_FORMAT(0x31) = 0x08  -> full resolution, +/-2g
//   4. Loop: read DATAX0+DATAX1 every 10 ms, output signed 10-bit result

module accelerometer_spi (
    input             clk,       // 50 MHz
    input             reset_n,   // async active-low reset
    output            sclk,      // to GSENSOR_SCLK  (idles high)
    output reg        cs_n,      // to GSENSOR_CS_N
    output            mosi,      // to GSENSOR_SDI
    input             miso,      // from GSENSOR_SDO
    output reg signed [9:0] x_accel,
    output reg        data_valid
);

    // ------------------------------------------------------------------
    // SCLK generation: 500 kHz  (50 MHz / 100)
    // ------------------------------------------------------------------
    localparam CLK_DIV = 50;
    reg [5:0] div_cnt;
    reg       sclk_r;   // raw internal SCLK, idles high

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            div_cnt <= 6'd0;
            sclk_r  <= 1'b1;
        end else begin
            if (div_cnt == CLK_DIV - 1) begin
                div_cnt <= 6'd0;
                sclk_r  <= ~sclk_r;
            end else
                div_cnt <= div_cnt + 6'd1;
        end
    end

    // Gate SCLK: idle high whenever CS is deasserted
    assign sclk = cs_n ? 1'b1 : sclk_r;

    // Edge strobes
    reg sclk_d;
    always @(posedge clk or negedge reset_n)
        if (!reset_n) sclk_d <= 1'b1;
        else          sclk_d <= sclk_r;

    wire fall = sclk_d  & ~sclk_r;   // falling edge -> shift MOSI
    wire rise = ~sclk_d & sclk_r;    // rising  edge -> sample MISO

    // ------------------------------------------------------------------
    // Shift register
    // ------------------------------------------------------------------
    reg [23:0] shreg_tx;  // transmit shift register (MSB first)
    reg [23:0] shreg_rx;  // receive shift register

    assign mosi = shreg_tx[23];  // always drive MSB

    // ------------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------------
    localparam S_STARTUP    = 3'd0;  // power-on delay
    localparam S_PWR_LOAD   = 3'd1;  // load & start POWER_CTL write
    localparam S_PWR_SHIFT  = 3'd2;  // clock 16 bits
    localparam S_FMT_LOAD   = 3'd3;  // load & start DATA_FORMAT write
    localparam S_FMT_SHIFT  = 3'd4;  // clock 16 bits
    localparam S_READ_LOAD  = 3'd5;  // load & start 24-bit read
    localparam S_READ_SHIFT = 3'd6;  // clock 24 bits
    localparam S_READ_PARSE = 3'd7;  // deassert CS, latch result, wait gap

    reg [2:0]  state;
    reg [4:0]  bit_cnt;   // counts bits clocked (0 = first)
    reg [19:0] wait_cnt;  // general-purpose wait counter

    // 20 ms at 50 MHz = 1,000,000
    localparam STARTUP_TICKS = 20'd1_000_000;
    // 10 ms between reads = 500,000
    localparam READ_GAP      = 20'd500_000;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state      <= S_STARTUP;
            cs_n       <= 1'b1;
            shreg_tx   <= 24'd0;
            shreg_rx   <= 24'd0;
            bit_cnt    <= 5'd0;
            wait_cnt   <= 20'd0;
            x_accel    <= 10'sd0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;  // default low each cycle

            case (state)

                // ----------------------------------------------------------
                // Wait 20 ms for ADXL345 power-on
                // ----------------------------------------------------------
                S_STARTUP: begin
                    if (wait_cnt == STARTUP_TICKS - 1) begin
                        wait_cnt <= 20'd0;
                        state    <= S_PWR_LOAD;
                    end else
                        wait_cnt <= wait_cnt + 20'd1;
                end

                // ----------------------------------------------------------
                // Write POWER_CTL: cmd=0x2D data=0x08  (16 bits total)
                // ----------------------------------------------------------
                S_PWR_LOAD: begin
                    shreg_tx <= {8'h2D, 8'h08, 8'h00}; // extra byte padded, we stop at 16
                    bit_cnt  <= 5'd0;
                    cs_n     <= 1'b0;
                    state    <= S_PWR_SHIFT;
                end

                S_PWR_SHIFT: begin
                    if (fall) begin
                        if (bit_cnt == 5'd15) begin
                            cs_n  <= 1'b1;
                            state <= S_FMT_LOAD;
                        end else begin
                            shreg_tx <= {shreg_tx[22:0], 1'b0};
                            bit_cnt  <= bit_cnt + 5'd1;
                        end
                    end
                end

                // ----------------------------------------------------------
                // Write DATA_FORMAT: cmd=0x31 data=0x08  (16 bits)
                // 0x08 = FULL_RES bit set, range = +/-2g
                // ----------------------------------------------------------
                S_FMT_LOAD: begin
                    shreg_tx <= {8'h31, 8'h08, 8'h00};
                    bit_cnt  <= 5'd0;
                    cs_n     <= 1'b0;
                    state    <= S_FMT_SHIFT;
                end

                S_FMT_SHIFT: begin
                    if (fall) begin
                        if (bit_cnt == 5'd15) begin
                            cs_n     <= 1'b1;
                            wait_cnt <= 20'd0;
                            state    <= S_READ_LOAD;
                        end else begin
                            shreg_tx <= {shreg_tx[22:0], 1'b0};
                            bit_cnt  <= bit_cnt + 5'd1;
                        end
                    end
                end

                // ----------------------------------------------------------
                // Read DATAX0 + DATAX1: 24 bits
                //   Byte 0 TX: 0xF2  (R/W=1, MB=1, addr=0x32)
                //   Byte 1 RX: DATAX0 (LSByte of X, bits[7:0])
                //   Byte 2 RX: DATAX1 (MSByte of X, bits[1:0] = data[9:8])
                // ----------------------------------------------------------
                S_READ_LOAD: begin
                    shreg_tx <= {8'hF2, 16'h0000};
                    shreg_rx <= 24'd0;
                    bit_cnt  <= 5'd0;
                    cs_n     <= 1'b0;
                    state    <= S_READ_SHIFT;
                end

                S_READ_SHIFT: begin
                    // Sample MISO on rising edge
                    if (rise)
                        shreg_rx <= {shreg_rx[22:0], miso};

                    // Advance on falling edge
                    if (fall) begin
                        if (bit_cnt == 5'd23) begin
                            cs_n  <= 1'b1;
                            state <= S_READ_PARSE;
                        end else begin
                            shreg_tx <= {shreg_tx[22:0], 1'b0};
                            bit_cnt  <= bit_cnt + 5'd1;
                        end
                    end
                end

                // ----------------------------------------------------------
                // Parse result, assert data_valid, wait READ_GAP
                //
                // After 24 clocks:
                //   shreg_rx[23:16] = first byte on MISO (during command)
                //   shreg_rx[15:8]  = DATAX0    = bits [7:0] of X
                //   shreg_rx[7:0]   = DATAX1    = bits [9:8] of X are [1:0] of this byte
                //
                // 10-bit signed value = { DATAX1[1:0], DATAX0[7:0] }
                //   (NOT shreg_rx[9:8] — those bits sit in the DATAX0 byte and duplicate LSBs)
                // ----------------------------------------------------------
                S_READ_PARSE: begin
                    if (wait_cnt == 20'd0) begin
                        // Latch on the very first cycle of this state
                        x_accel    <= $signed({shreg_rx[1:0], shreg_rx[15:8]});
                        data_valid <= 1'b1;
                    end
                    if (wait_cnt == READ_GAP - 1) begin
                        wait_cnt <= 20'd0;
                        state    <= S_READ_LOAD;
                    end else
                        wait_cnt <= wait_cnt + 20'd1;
                end

                default: state <= S_STARTUP;
            endcase
        end
    end

endmodule