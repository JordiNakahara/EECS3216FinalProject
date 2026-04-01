// ADXL345 Accelerometer Interface for DE10-Lite (3-wire SPI)
// Adapted from the known working DE10-Lite_Accelerometer project.

// ADXL345 register addresses
parameter THRESH_TAP     = 6'h1D;
parameter OFSX           = 6'h1E;
parameter OFSY           = 6'h1F;
parameter OFSZ           = 6'h20;
parameter DUR            = 6'h21;
parameter LATENT         = 6'h22;
parameter WINDOW         = 6'h23;
parameter THRESH_ACT     = 6'h24;
parameter THRESH_INACT   = 6'h25;
parameter TIME_INACT     = 6'h26;
parameter ACT_INACT_CTL  = 6'h27;
parameter THRESH_FF      = 6'h28;
parameter TIME_FF        = 6'h29;
parameter TAP_AXES       = 6'h2A;
parameter ACT_TAP_STATUS = 6'h2B;
parameter BW_RATE        = 6'h2C;
parameter POWER_CTL      = 6'h2D;
parameter INT_ENABLE     = 6'h2E;
parameter INT_MAP        = 6'h2F;
parameter INT_SOURCE     = 6'h30;
parameter DATA_FORMAT    = 6'h31;
parameter DATAX0         = 6'h32;
parameter DATAX1         = 6'h33;
parameter DATAY0         = 6'h34;
parameter DATAY1         = 6'h35;
parameter DATAZ0         = 6'h36;
parameter DATAZ1         = 6'h37;
parameter FIFO_CTL       = 6'h38;
parameter FIFO_STATUS    = 6'h39;

// Initialization values
parameter INIT_BW_RATE     = 8'b00000101; // 800 Hz sample rate mode
parameter INIT_POWER_CTL   = 8'b00001000; // Enable measurement mode
parameter INIT_DATA_FORMAT = 8'b01000100; // Enable 3-wire SPI and left-justified data
parameter INIT_INT_ENABLE  = 8'b10000000; // Enable Data-Ready interrupts
parameter INIT_INT_MAP     = 8'b01111111; // Send only Data-Ready to INT1 pin
parameter INIT_OFSX        = 8'b00000101; // X-Offset
parameter INIT_OFSY        = 8'b00000100; // Y-Offset
parameter INIT_OFSZ        = 8'b00001000; // Z-Offset

parameter READ  = 1'b1;
parameter WRITE = 1'b0;

module adxl345_interface (
  input              i_clk,
  input              i_rst_n,
  output logic [9:0] o_data_x,
  output logic [9:0] o_data_y,
  output logic [9:0] o_data_z,
  output logic       o_data_valid,
  output logic       o_sclk,
  inout wire         io_sdio,
  output logic       o_cs_n,
  input              i_int1
  );

  localparam CONFIG_COUNT = 3'd7;
  localparam READ_COUNT   = 3'd5;
  localparam ONE          = 3'd1;
  localparam ZEROS        = 8'd0;
  localparam IDLE         = 1'b0;
  localparam TRANSFER     = 1'b1;

  logic        spi_go;
  logic        read_write_n;
  logic [15:0] spi_input_data;
  logic [2:0]  config_count;
  logic [2:0]  read_count;
  logic        reading_data;
  logic        config_done;
  logic        spi_state;
  logic [5:0]  config_address;
  logic [7:0]  config_value;
  logic [5:0]  read_address;
  logic        spi_data_valid;
  logic        spi_idle;
  logic [7:0]  spi_output_data;
  logic        data_ready;

  logic [5:0][7:0] data_buffer;

  assign data_ready = i_int1;
  assign o_data_x = {data_buffer[4],data_buffer[5][7:6]};
  assign o_data_y = {data_buffer[2],data_buffer[3][7:6]};
  assign o_data_z = {data_buffer[0],data_buffer[1][7:6]};
  assign spi_input_data[15:14] = {read_write_n, 1'b0};

  config_rom     cr   (.i_address(config_count), .o_config_address(config_address), .o_config_value(config_value));
  read_rom       rr   (.i_address(read_count), .o_read_address(read_address));
  spi_controller spic (.i_clk, .i_rst_n, .o_data_valid(spi_data_valid), .i_spi_go(spi_go), .i_read_write_n(read_write_n),
                       .o_idle(spi_idle), .i_data(spi_input_data), .o_data(spi_output_data), .o_sclk, .io_sdio, .o_cs_n);

  always_ff @ (posedge i_clk) begin : SpiControl
    if (~i_rst_n) begin
      config_count <= CONFIG_COUNT;
      read_count <= READ_COUNT;
      spi_go <= '0;
      spi_state <= IDLE;
      data_buffer <= '0;
      o_data_valid <= '0;
      config_done <= '0;
      reading_data <= '0;
    end else begin
      case (spi_state)
        IDLE : begin
          o_data_valid <= '0;
          if (config_done) begin : RunMode
            if (data_ready | reading_data) begin
              spi_input_data[13:0] <= {read_address, ZEROS};
              read_write_n <= READ;
              spi_go <= '1;
              spi_state <= TRANSFER;
            end
          end : RunMode
          else begin : ConfigMode
            spi_input_data[13:0] <= {config_address, config_value};
            read_write_n <= WRITE;
            spi_go <= '1;
            if (~|config_count) begin
              config_done <= '1;
            end else begin
              config_count <= config_count - ONE;
            end
            spi_state <= TRANSFER;
          end : ConfigMode
        end
        TRANSFER : begin
          spi_go <= '0;
          if (spi_data_valid) begin
            data_buffer[read_count] <= spi_output_data;
            if (~|read_count) begin
              o_data_valid <= '1;
              reading_data <= '0;
              read_count <= READ_COUNT;
            end else begin
              read_count <= read_count - ONE;
              reading_data <= '1;
            end
          end
          if (~spi_go & spi_idle) begin
            spi_state <= IDLE;
          end
        end
      endcase
    end
  end
endmodule

module config_rom (
  input        [2:0] i_address,
  output logic [5:0] o_config_address,
  output logic [7:0] o_config_value
  );
  logic [7:0] CONFIG_VALUE [7:0];
  logic [5:0] CONFIG_ADDRESS [7:0];

  assign CONFIG_VALUE[7]   = INIT_OFSX;
  assign CONFIG_VALUE[6]   = INIT_OFSY;
  assign CONFIG_VALUE[5]   = INIT_OFSZ;
  assign CONFIG_VALUE[4]   = INIT_BW_RATE;
  assign CONFIG_VALUE[3]   = INIT_INT_MAP;
  assign CONFIG_VALUE[2]   = INIT_INT_ENABLE;
  assign CONFIG_VALUE[1]   = INIT_DATA_FORMAT;
  assign CONFIG_VALUE[0]   = INIT_POWER_CTL;
  assign CONFIG_ADDRESS[7] = OFSX;
  assign CONFIG_ADDRESS[6] = OFSY;
  assign CONFIG_ADDRESS[5] = OFSZ;
  assign CONFIG_ADDRESS[4] = BW_RATE;
  assign CONFIG_ADDRESS[3] = INT_MAP;
  assign CONFIG_ADDRESS[2] = INT_ENABLE;
  assign CONFIG_ADDRESS[1] = DATA_FORMAT;
  assign CONFIG_ADDRESS[0] = POWER_CTL;

  assign o_config_address = CONFIG_ADDRESS[i_address];
  assign o_config_value   = CONFIG_VALUE[i_address];
endmodule

module read_rom (
  input        [2:0] i_address,
  output logic [5:0] o_read_address
  );
  logic [5:0] READ_ADDRESS [5:0];

  assign READ_ADDRESS[5] = DATAX0;
  assign READ_ADDRESS[4] = DATAX1;
  assign READ_ADDRESS[3] = DATAY0;
  assign READ_ADDRESS[2] = DATAY1;
  assign READ_ADDRESS[1] = DATAZ0;
  assign READ_ADDRESS[0] = DATAZ1;

  assign o_read_address = READ_ADDRESS[i_address];
endmodule

module spi_controller (
  input              i_clk,
  input              i_rst_n,
  output logic       o_data_valid,
  input              i_spi_go,
  input              i_read_write_n,
  output logic       o_idle,
  input [15:0]       i_data,
  output logic [7:0] o_data,
  output logic       o_sclk,
  inout wire         io_sdio,
  output logic       o_cs_n
  );

  localparam MAX_SCLK_COUNT = 4'd15;
  localparam ONE            = 4'd1;

  logic [15:0] sdio_buffer;
  logic [3:0]  sclk_count;
  logic        sclk_enable;
  logic        sdio_enable;
  logic        spi_done;
  logic        sdio;
  logic        read_write_n;
  logic        rise_edge;
  logic        fall_edge;
  logic        sclk;

  assign o_sclk  = (sclk_enable) ? sclk : '1;
  assign io_sdio = (sdio_enable) ? sdio : 1'bz;
  assign o_data  = sdio_buffer[7:0];
  assign o_idle  = o_cs_n;

  spi_clock_generator spicg (.i_clk, .i_rst_n, .o_rise_edge(rise_edge), .o_fall_edge(fall_edge), .o_clk_slow(sclk));

  always_ff @ (posedge i_clk) begin : ChipSelect
    if (~i_rst_n) begin
      o_cs_n <= '1;
    end else begin
      if (spi_done) begin
        o_cs_n <= '1;
      end else if (i_spi_go) begin
        o_cs_n <= '0;
        read_write_n <= i_read_write_n;
      end
    end
  end

  always_ff @ (posedge i_clk) begin : SclkEnable
    if (~o_cs_n) begin
      if (sclk) begin
        sclk_enable <= '1;
      end
    end else begin
      sclk_enable <= '0;
    end
  end

  always_ff @ (posedge i_clk) begin : SpiDoneDataValid
    if (~|sclk_count & rise_edge) begin
      spi_done <= '1;
      o_data_valid <= read_write_n;
    end else begin
      spi_done <= '0;
      o_data_valid <= '0;
    end
  end

  always_ff @ (posedge i_clk) begin : SclkCount
    if (sclk_enable) begin
      if (rise_edge) begin
        sclk_count <= sclk_count - ONE;
      end
    end else begin
      sclk_count <= MAX_SCLK_COUNT;
    end
  end

  always_ff @ (posedge i_clk) begin : TransferData
    if (~o_cs_n) begin
      if ((sclk_count > 7) | (~read_write_n)) begin
        sdio_enable <= '1;
        if (fall_edge) begin
          sdio <= sdio_buffer[sclk_count];
        end
      end else begin
        sdio_enable <= '0;
        if (rise_edge) begin
          sdio_buffer[sclk_count] <= io_sdio;
        end
      end
    end else begin
      sdio_enable <= '0;
      if (i_spi_go) begin
        sdio_buffer <= i_data;
      end
    end
  end
endmodule

module spi_clock_generator (
  input        i_clk,
  input        i_rst_n,
  output logic o_rise_edge,
  output logic o_fall_edge,
  output logic o_clk_slow
  );

  localparam MAX_COUNT = 5'd24;
  localparam ONE = 5'd1;

  logic [4:0] count;
  logic clk_slow;

  always_ff @ (posedge i_clk) begin : CreateClk
    if (~i_rst_n) begin
      o_rise_edge <= '0;
      o_fall_edge <= '0;
      count <= '0;
      clk_slow <= '1;
    end else begin
      count <= count + ONE;
      o_rise_edge <= '0;
      o_fall_edge <= '0;
      if (count == MAX_COUNT) begin
        o_rise_edge <= ~clk_slow;
        o_fall_edge <= clk_slow;
        count <= '0;
        clk_slow <= ~clk_slow;
      end
    end
  end

  always_ff @ (posedge i_clk) begin : DelayClk
    if (~i_rst_n) begin
      o_clk_slow <= '0;
    end else begin
      o_clk_slow <= clk_slow;
    end
  end
endmodule
