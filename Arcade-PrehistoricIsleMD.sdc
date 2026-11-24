derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# fx68k: microcode address paths settle over two clk_sys cycles (CPU enables are at least three cycles apart)
set_multicycle_path -start -setup -from [get_keepers {*fx68k:*|Ir[*]}] -to [get_keepers {*fx68k:*|microAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {*fx68k:*|Ir[*]}] -to [get_keepers {*fx68k:*|microAddr[*]}] 1
set_multicycle_path -start -setup -from [get_keepers {*fx68k:*|Ir[*]}] -to [get_keepers {*fx68k:*|nanoAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {*fx68k:*|Ir[*]}] -to [get_keepers {*fx68k:*|nanoAddr[*]}] 1

# SDRAM: clock at the SDRAM_CLK pin; command / address / data outputs meet the chip's setup 1.5 ns and hold 0.8 ns (+0.5 ns board)
create_generated_clock -name sdram_clk_pin -source [get_pins {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] [get_ports {SDRAM_CLK}]
set_output_delay -clock sdram_clk_pin -max  2.0 [get_ports {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQML SDRAM_DQMH SDRAM_nCS SDRAM_nCAS SDRAM_nRAS SDRAM_nWE SDRAM_CKE}]
set_output_delay -clock sdram_clk_pin -min -1.3 [get_ports {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQML SDRAM_DQMH SDRAM_nCS SDRAM_nCAS SDRAM_nRAS SDRAM_nWE SDRAM_CKE}]

# SDRAM read data: valid tAC 6.0 ns after SDRAM_CLK and held tOH 2.5 ns (+-0.5 ns board), sampled two clk_sys edges later (CL 2)
set_input_delay -clock sdram_clk_pin -max 6.5 [get_ports {SDRAM_DQ[*]}]
set_input_delay -clock sdram_clk_pin -min 2.0 [get_ports {SDRAM_DQ[*]}]
set_multicycle_path -setup -end -from [get_clocks {sdram_clk_pin}] -to [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] 2
