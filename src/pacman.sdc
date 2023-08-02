//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.9 Beta-2
//Created Time: 2023-08-01 17:20:38
create_clock -name clk_osc -period 37 -waveform {0 18} [get_ports {clk}]
