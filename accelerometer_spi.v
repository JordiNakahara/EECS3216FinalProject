// accelerometer_spi.v
// Interfaces with the ADXL345 accelerometer on the DE10-Lite via SPI
// Reads X-axis data continuously and outputs as signed 10-bit value

module accelerometer_spi (
    input         clk,          // 50 MHz system clock
    input         reset_n,      // active-low reset
    // SPI pins (connect to GSENSOR_* on DE10-Lite)
    output        sclk,         // SPI clock (~1 MHz)
    output        cs_n,         // chip select (active low)
    output        mosi,         // master out slave in
    input         miso,         // master in slave out
    // Result
    output reg signed [9:0] x_accel,  // signed 10-bit X acceleration
    output reg        data_valid       // pulses high for 1 clk when x_accel updated
);

    // ----- SPI clock divider: 50 MHz / 50 = 1 MHz -----
    localparam CLK_DIV = 25;
    reg [4:0]  clk_cnt;
    reg        spi_clk;
    reg        spi_clk_prev;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clk_cnt <= 0; spi_clk <= 0;
        end else begin
            if (clk_cnt == CLK_DIV - 1) begin
                clk_cnt <= 0;
                spi_clk <= ~spi_clk;
            end else clk_cnt <= clk_cnt + 1;
        end
    end

    assign sclk = spi_clk;

    // ----- State machine -----
    // ADXL345: SPI transaction = 16-bit command + 8-bit data (read) = 24 bits
    // To read DATAX0 (0x32) and DATAX1 (0x33) we use multibyte read:
    //   Command byte: R/W=1, MB=1, addr=6'h32  -> 8'hF2
    //   Then read 2 bytes (DATAX0, DATAX1)
    // Total bits: 8 (cmd) + 16 (data) = 24

    localparam IDLE      = 3'd0,
               INIT      = 3'd1,
               CS_LOW    = 3'd2,
               SHIFT     = 3'd3,
               CS_HIGH   = 3'd4,
               DONE      = 3'd5;

    reg [2:0]  state;
    reg [4:0]  bit_cnt;      // 0..23
    reg [23:0] shift_out;    // bits to send
    reg [23:0] shift_in;     // bits received
    reg        cs_reg;
    reg        mosi_reg;

    // Init: write POWER_CTL register (0x2D) = 0x08 (measure mode)
    // Command: R/W=0, MB=0, addr=6'h2D -> 8'h2D, data=8'h08
    // We do one init write, then loop reading X continuously.
    reg        init_done;
    reg [15:0] init_data;    // 16-bit: cmd + data

    // Delay counter between transactions
    reg [15:0] delay_cnt;
    localparam DELAY = 1000; // ~1ms between reads at 50MHz/CLK_DIV

    assign cs_n  = cs_reg;
    assign mosi  = mosi_reg;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state      <= INIT;
            cs_reg     <= 1;
            mosi_reg   <= 0;
            bit_cnt    <= 0;
            shift_out  <= 0;
            shift_in   <= 0;
            init_done  <= 0;
            data_valid <= 0;
            x_accel    <= 0;
            delay_cnt  <= 0;
            spi_clk_prev <= 0;
        end else begin
            spi_clk_prev <= spi_clk;
            data_valid   <= 0;

            case (state)
                INIT: begin
                    // Prepare POWER_CTL write
                    shift_out <= {8'h2D, 8'h08, 8'h00}; // cmd, data, dummy
                    bit_cnt   <= 0;
                    delay_cnt <= 0;
                    state     <= CS_LOW;
                end

                CS_LOW: begin
                    cs_reg <= 0;
                    state  <= SHIFT;
                end

                SHIFT: begin
                    // Drive MOSI on falling edge of spi_clk
                    if (spi_clk_prev && !spi_clk) begin // falling edge
                        mosi_reg  <= shift_out[23];
                        shift_out <= {shift_out[22:0], 1'b0};
                    end
                    // Sample MISO on rising edge
                    if (!spi_clk_prev && spi_clk) begin // rising edge
                        shift_in <= {shift_in[22:0], miso};
                        if (bit_cnt == 23) begin
                            state <= CS_HIGH;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                CS_HIGH: begin
                    cs_reg <= 1;
                    if (!init_done) begin
                        init_done <= 1;
                        state     <= DONE;
                    end else begin
                        // Parse X-axis: DATAX0 in shift_in[15:8], DATAX1 in shift_in[7:0]
                        // 10-bit value: bits[1:0] of DATAX1 are MSBs, full byte DATAX0
                        x_accel    <= {shift_in[1:0], shift_in[15:8]};
                        data_valid <= 1;
                        state      <= DONE;
                    end
                end

                DONE: begin
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt == DELAY) begin
                        delay_cnt <= 0;
                        // Set up multibyte read of DATAX0+DATAX1
                        shift_out <= {8'hF2, 16'h0000}; // R/W=1, MB=1, addr=0x32
                        bit_cnt   <= 0;
                        state     <= CS_LOW;
                    end
                end

                default: state <= INIT;
            endcase
        end
    end

endmodule
