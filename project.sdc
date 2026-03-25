# project.sdc - Timing Constraints
# EECS 3216 Ball Balancing Game

# 50 MHz system clock
create_clock -name {MAX10_CLK1_50} -period 20.000 -waveform {0.000 10.000} [get_ports {MAX10_CLK1_50}]

# 25.175 MHz pixel clock from PLL
derive_pll_clocks

# Derive clock uncertainty
derive_clock_uncertainty
