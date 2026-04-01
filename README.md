# Ball Balancing Game — EECS 3216 Project
## Group: Jordi Nakahara, Ryan Kwan | Difficulty: B

---

## File Overview

| File | Description |
|---|---|
| `top_module.v` | Top-level: wires everything together |
| `vga_controller.v` | Provided VGA sync controller (do not modify) |
| `adxl345_interface.sv` | Working ADXL345 3-wire SPI + INT1 interface |
| `ball_controller.v` | Ball physics, safe-zone logic, scoring |
| `vga_renderer.v` | Pixel colour generator (what gets drawn) |
| `seg7_display.v` | 7-segment score & "Go" game-over display |
| `project.qsf` | Quartus pin assignments (DE10-Lite) |
| `project.sdc` | Timing constraints |

---

## How to Build in Quartus Prime Lite

1. Create a new Quartus project targeting **MAX10 10M50DAF484C7G**.
2. Add all `.v` files and `project.qsf` / `project.sdc`.
3. Generate the **ALTPLL** IP:
   - Tools → IP Catalog → Library → Basic Functions → Clocks, PLLs and Resets → PLL → **ALTPLL**
   - Save as `ip/pll.v`
   - Input clock: **50 MHz**, Output c0: **25.175 MHz**
   - Uncheck "Create areset" and "Create locked"
   - Check instantiation template `pll_inst.v` at the end
4. Set `top_module` as the top-level entity.
5. Compile → Program → Done.

---

## Gameplay

- **Tilt the board left/right** — the ball rolls in the direction of tilt.
- **Keep the ball on the green safe zone** — score increments each second it stays there.
- **Ball hits the wall or leaves the safe zone** — GAME OVER (red screen, "Go" on HEX5-HEX4).
- **Press KEY[0]** at any time to **reset** the game.

---

## Design Notes

### VGA Output (640×480 @ 60 Hz)
- `vga_controller.v` generates HSYNC, VSYNC, and pixel coordinates.
- `vga_renderer.v` outputs 4-bit RGB per channel based on current (row, col).
- Ball is drawn as a filled circle using squared-distance comparison (no sqrt needed).

### Accelerometer
- ADXL345 communicates via 3-wire SPI (`SDIO`) plus `INT1` data-ready interrupt.
- `adxl345_interface.sv` performs ADXL345 configuration then continuously reads X/Y/Z data.
- `top_module.v` uses the X-axis output for ball movement.

### Ball Physics (Fixed-Point)
- Position and velocity stored in Q10.4 fixed-point (lower 4 bits = fraction).
- Accelerometer X-axis value scaled (÷8) and added to velocity each sample.
- Friction applied (×0.875) each sample so ball slows naturally.
- Wall collision: ball reverses direction with half velocity (bounce + damping).

### Scoring
- Counted in `ball_controller.v` — increments once per VGA frame (~60 Hz) while
  ball centre is inside the safe zone (centre 100-px green region).
- Score displayed on HEX3–HEX0 as decimal.
- Game over freezes score and displays "Go" on HEX5–HEX4.

---

## Own Work vs External Sources

| Module | Source |
|---|---|
| `vga_controller.v` | Provided by lab (M. Hildebrand, 2018) |
| `top_module.v` | Own work |
| `accelerometer_spi.v` | Own work (based on ADXL345 datasheet SPI protocol) |
| `ball_controller.v` | Own work |
| `vga_renderer.v` | Own work |
| `seg7_display.v` | Own work |
