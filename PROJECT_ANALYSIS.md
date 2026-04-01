# Digital Design Analysis — EECS 3216 Ball-Balancing Game

This document summarizes the FPGA architecture, **digital building blocks** used across the RTL, and **how the source files interact**. The design targets the **Intel MAX10** on the **DE10-Lite** board with **VGA** video and an **ADXL345** accelerometer over **3-wire SPI**.

---

## 1. High-level architecture

Data and control flow:

1. **50 MHz board clock** drives the **PLL** (pixel clock), the **accelerometer interface**, and all SPI-related sequencers.
2. **VGA** timing runs on **pixel_clk** (~25.175 MHz): `vga_controller` produces sync, blanking, and **(column, row)**.
3. **ADXL345** produces **X/Y/Z** samples; only **X** is used for gameplay. `o_data_valid` pulses when a new sample is ready (aligned with the accelerometer’s interrupt-driven read path).
4. **ball_controller** integrates tilt into **ball motion** (fixed-point physics), **score**, **game_over**, and **game_win**.
5. **vga_renderer** is a **combinational pixel pipeline** registered on `pixel_clk`: it maps game state + coordinates to **12-bit RGB**.
6. **seg7_display** converts **binary score → decimal digits** and drives **7-segment patterns** (muxed by game state).
7. **top_module** adds a **splash gate** (`KEY[1]`) so gameplay reset is `reset_n && game_started`.

```
MAX10_CLK1_50 ─┬─► pll ─► pixel_clk ─► vga_controller ─► (disp_ena, row, col)
               │                              │
               │                              └──────────────► vga_renderer ─► VGA_RGB
               │
               └─► adxl345_interface ─► x_accel, accel_valid ─► ball_controller
                                                      │
pixel_clk ──────────────────────────────────────────┘
KEY[0], KEY[1] ─► reset / splash gating ─► ball_controller (reset_n effective)
ball_controller ─► ball position, score, game_over, game_win ─► vga_renderer, seg7_display
```

---

## 2. File roles and interactions

| File | Role | Instantiates / called by |
|------|------|---------------------------|
| `top_module.v` | Top-level: PLL, wiring, **splash FSM register**, clock-domain usage | `pll`, `vga_controller`, `adxl345_interface`, `ball_controller`, `vga_renderer`, `seg7_display` |
| `ip/pll.v` (generated) | **ALTPLL**: 50 MHz → ~25.175 MHz pixel clock | `top_module` |
| `vga_controller.v` | **VGA timing FSM/counters**: HSYNC, VSYNC, `disp_ena`, pixel coordinates | `top_module` |
| `adxl345_interface.sv` | **SPI master + config/read sequencers**, ROMs for addresses | `top_module`; embeds `config_rom`, `read_rom`, `spi_controller`, `spi_clock_generator` |
| `ball_controller.v` | **Game physics**, scoring timer, win/lose flags | `top_module` |
| `vga_renderer.v` | **Pixel RGB** from geometry + mode flags | `top_module` |
| `seg7_display.v` | **BCD + 7-segment decode**, mode mux | `top_module` |
| `accelerometer_spi.v` | Alternate 4-wire-style SPI path (MOSI/MISO) | **Not referenced** in `project.qsf` / `top_module`; treat as **legacy or alternate IP** unless added to the project |
| `project.sdc` | **Timing constraints** (clocks, I/O) | Quartus |
| `project.qsf` / `EECS3216FinalProject.qsf` | File list and pin assignments | Quartus |

---

## 3. Digital design features (by category)

### 3.1 Flip-flops, registers, and synchronous design

- **`vga_controller`**: `h_count`, `v_count`, `h_sync`, `v_sync`, `disp_ena`, `column`, `row` — all updated on **posedge `pixel_clk`** (synchronous reset when `reset_n == 0`).
- **`ball_controller`**: `ball_px`, `ball_vx`, `ball_x`, `score`, `game_over`, `game_win`, `frame_cnt` — **async reset** (`negedge reset_n`), **posedge `clk`** (pixel clock). Physics updates gated by `accel_valid`.
- **`top_module`**: `game_started` — registered on **posedge `pixel_clk`**, async clear via `KEY[0]`.
- **`vga_renderer`**: `vga_r/g/b` — **output registers** clocked by `pixel_clk` (pipeline stage for RGB).
- **`adxl345_interface` / `spi_controller` / `spi_clock_generator`**: extensive use of **`always_ff @ (posedge i_clk)`** for registers, chip select, shift path, and divided SPI clock.
- **`seg7_display`**: **purely combinational** (`always @(*)`) — no registers inside the module (outputs are re-registered at I/O pads or driven directly depending on synthesis).

### 3.2 Counters

- **Line and frame counters** (`vga_controller`): horizontal counter wraps at `h_period`; vertical increments at end of line. Implements standard **640×480** timing.
- **Frame-based score tick** (`ball_controller`): `frame_cnt` counts to `FRAME_PERIOD - 1` to approximate **one “tick” per frame** for scoring / safe-zone check (~60 Hz relative to pixel clock rate).
- **SPI bit / half-cycle timing** (`spi_controller`, `spi_clock_generator`): `sclk_count` and `count` dividers to pace **SPI** relative to **50 MHz**.

### 3.3 Finite state machines (FSMs)

- **`adxl345_interface`**: Two top-level states — **IDLE** vs **TRANSFER** — plus **config phase** vs **run/read phase** (driven by `config_done`, `data_ready`, `reading_data`). This is a **controller FSM** for multi-register init and burst reads.
- **`spi_controller`**: Implicit state from **`o_cs_n`**, `sclk_enable`, and handshake with `spi_done` / `i_spi_go` — behaves as a **bit-serial transaction controller**.
- **`accelerometer_spi.v`** (if used elsewhere): explicit **one-hot-ish** `state` enum-style values (IDLE, INIT, CS_LOW, SHIFT, …).

### 3.4 Multiplexers (MUX) and priority encoders (implicit)

Multiplexing appears as **priority `if / else if`** chains and **ternary operators**:

- **`vga_renderer`**: Priority: **blank** → **splash** → **victory (`game_win`)** → **game over** → **normal play**. Each branch selects one of several **pixel color policies** — behaviorally a **large MUX tree** on `(row, col)` and flags.
- **`ball_controller`**: **Clamping MUX** on velocity (`vx_clamped`), **wall bounce MUX** on position/velocity (`px_final`, `vx_final`).
- **`seg7_display`**: **Mode MUX**: `game_win` → “Hi” + digits; `game_over` → “Go”; else **decimal score** on HEX3–HEX0.

### 3.5 Decoders and encoders

- **Binary-to-BCD (implicit “encoder”)**: `seg7_display` uses **modulo and division** (`score % 10`, `score / 10`, …) to extract decimal digits — not a ROM-based BCD converter, but functionally **binary → decimal digit extraction**.
- **7-segment decoder**: `function seg7(digit)` is a **4-to-7 decoder** (4-bit BCD → 7 segment lines, **active low**).
- **Address ROMs (“look-up = decoder”)**:
  - `config_rom`: index `config_count` → **register address** + **init data byte**.
  - `read_rom`: index `read_count` → **ADXL345 read address** for X/Y/Z bytes.

### 3.6 Arithmetic and comparators

- **Signed arithmetic** (`ball_controller`): `ball_vx`, `ball_px`, acceleration sign extension `{{6{accel_s[9]}}, accel_s}`, **saturation** and **arithmetic shift** (`>>>`, `>>>` for friction).
- **Comparators**: wall tests, **safe zone** `ball_x` vs `SAFE_XMIN/MAX`, **score == 9999** for win.
- **Geometry** (`vga_renderer`): **distance-squared** for circle (`dx*dx + dy*dy <= R*R`) — compares against constant **64** for `R=8`.

### 3.7 Fixed-point representation

- **Q-format** (documented in README): position/velocity use **fractional bits** in `ball_px` / `ball_vx` (e.g. `px_final[13:4]` maps to integer pixel `ball_x`). This is **fixed-point scaling**, not floating-point.

### 3.8 PLL (clock generation)

- **`pll` (ALTPLL)**: Synthesizes **pixel clock** from **50 MHz** reference. This is the primary **frequency synthesis** block for VGA timing closure.

### 3.9 Clock domains and CDC (crossing)

- **Two related clocks**: **50 MHz** (`MAX10_CLK1_50`) for SPI/accel; **pixel_clk** for VGA and ball position display path.
- **Important**: `x_accel` and `accel_valid` are generated in the **50 MHz** domain but consumed in **`ball_controller` clocked by `pixel_clk`**. This is a **clock-domain crossing (CDC)** on multi-bit data + a single-bit valid. For a course project this often works if sampling is slow enough and timing is constrained, but formally it would merit **synchronizers** or a **FIFO** for robustness.
- **Score / game flags** produced in `pixel_clk` feed **combinational** `seg7_display` — same domain as ball controller.

### 3.10 Tristate and bidirectional I/O

- **`spi_controller`**: `assign io_sdio = (sdio_enable) ? sdio : 1'bz;` — classic **SPI bidirectional data** on one pin (**3-wire** mode).

### 3.11 Shift registers and serializers

- **`spi_controller`**: `sdio_buffer` acts as a **16-bit shift register** for command/data; bits clocked out/in on **rise/fall** edges of the divided SPI clock.

### 3.12 Edge detection and divided clock

- **`spi_clock_generator`**: Divides `i_clk` to produce `o_clk_slow` and **one-cycle** `o_rise_edge` / `o_fall_edge` pulses — used to sample/shift SPI bits. This is **edge-qualified timing**, not an analog filter.

### 3.13 “Filters” (signal conditioning)

- There is **no explicit digital FIR/IIR filter** in RTL for the accelerometer samples.
- **Friction** (`vx_friction = vx_clamped - (vx_clamped >>> 3)`) behaves like **exponential damping** on velocity — a simple **IIR-like recurrence** in fixed-point form.
- **Scaling**: `accel_s = x_accel >>> 1` is a **coarse gain reduction** (arithmetic shift), not a classical low-pass filter.

### 3.14 POR / startup behavior (system-level)

- The design includes a **splash screen** gated by **`KEY[1]`** so users wait for monitor sync before play — a **human-facing** fix for analog/display latency, implemented with a **sticky register** (`game_started`).

---

## 4. Module-specific notes

### 4.1 `vga_controller.v`

- **Non-modifiable** lab IP (per README).
- Encodes **horizontal/vertical sync timing** in a **synchronous counter FSM**.
- **`disp_ena`** forces **blanking** outside the active 640×480 window — renderer should not rely on pixels when low (your renderer zeros RGB when `!disp_ena`).

### 4.2 `adxl345_interface.sv`

- **Hierarchical**: `config_rom`, `read_rom`, `spi_controller`, `spi_clock_generator`.
- **Interrupt-driven reads**: `data_ready = i_int1` triggers SPI reads of X/Y/Z register pairs when configuration is done.
- **Data packing**: `o_data_x` / `y` / `z` are **concatenated** from `data_buffer` bytes (left-justified 10-bit format per ADXL345 setup).

### 4.3 `ball_controller.v`

- Core **game loop**: on `accel_valid`, update velocity/position with **walls** and **friction**.
- **Scoring**: once per **frame period** (counter match), increment score if ball center in safe zone; else **game_over**; at **9999** transition to **game_win** without incrementing further.

### 4.4 `vga_renderer.v`

- Mostly **combinational region tests** (platform rectangle, safe zone, circle) **registered** at output.
- **Modes**: splash / victory / game-over / playfield — **priority multiplexing** of color.

### 4.5 `seg7_display.v`

- **Combinational** path from `score` to segments.
- **Special glyphs** (“Go”, “Hi”) via **custom 7-bit patterns** alongside the numeric decoder.

### 4.6 `accelerometer_spi.v` (standalone file)

- Implements a **different SPI style** (separate MOSI/MISO, internal SPI clock divider). **Not wired** in the current top-level / QSF snippet — document as **optional** or **superseded** by `adxl345_interface.sv`.

---

## 5. Synthesis and timing

- **`project.sdc`** should declare **clock** constraints for `MAX10_CLK1_50` and **generated** `pixel_clk`, plus I/O delays as needed. Review constraints after any top-level change.
- **PLL output** frequency must match **VGA mode** (25.175 MHz for standard 640×480 @ 60 Hz with the given timing parameters).

---

## 6. Summary table of primitives

| Feature | Where it appears |
|--------|-------------------|
| D flip-flops / registers | `vga_controller`, `ball_controller`, `top_module` (splash), SPI stack, `vga_renderer` RGB |
| Counters | H/V counters; `frame_cnt`; SPI dividers |
| FSMs | ADXL345 + SPI control |
| MUX / priority select | Renderer modes; physics clamps; `seg7_display` |
| Decoders | 4→7 segment function; ROM address → data |
| ROM / lookup tables | `config_rom`, `read_rom` |
| Arithmetic | Signed add, sat, shifts; fixed-point |
| PLL | `ip/pll.v` |
| Tristate | `io_sdio` in SPI |
| Shift register | SPI `sdio_buffer` |
| CDC | `accel_valid` + `x_accel` from 50 MHz → `pixel_clk` domain |

---

*Generated as a structural analysis of the RTL in this repository; behavior should be verified on hardware and with post-fit timing reports.*
