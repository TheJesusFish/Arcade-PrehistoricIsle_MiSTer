// True dual-port RAM (altsyncram BIDIR_DUAL_PORT, unregistered outputs) with a clock enable on each port's input registers.

module dpram_cen #(parameter LEN = 8192, DATA_WIDTH = 8)
(
    input                       clock_a,
    input                       cen_a,
    input   [$clog2(LEN)-1:0]   address_a,
    input      [DATA_WIDTH-1:0] data_a,
    output     [DATA_WIDTH-1:0] q_a,
    input                       wren_a,

    input                       clock_b,
    input                       cen_b,
    input   [$clog2(LEN)-1:0]   address_b,
    input      [DATA_WIDTH-1:0] data_b,
    output     [DATA_WIDTH-1:0] q_b,
    input                       wren_b
);

altsyncram #(
    .address_reg_b                 ( "CLOCK1"                ),
    .clock_enable_input_a          ( "NORMAL"                ),
    .clock_enable_input_b          ( "NORMAL"                ),
    .clock_enable_output_a         ( "BYPASS"                ),
    .clock_enable_output_b         ( "BYPASS"                ),
    .indata_reg_b                  ( "CLOCK1"                ),
    .intended_device_family        ( "Cyclone V"             ),
    .lpm_type                      ( "altsyncram"            ),
    .numwords_a                    ( LEN                     ),
    .numwords_b                    ( LEN                     ),
    .operation_mode                ( "BIDIR_DUAL_PORT"       ),
    .outdata_aclr_a                ( "NONE"                  ),
    .outdata_aclr_b                ( "NONE"                  ),
    .outdata_reg_a                 ( "UNREGISTERED"          ),
    .outdata_reg_b                 ( "UNREGISTERED"          ),
    .power_up_uninitialized        ( "FALSE"                 ),
    .read_during_write_mode_port_a ( "NEW_DATA_NO_NBE_READ"  ),
    .read_during_write_mode_port_b ( "NEW_DATA_NO_NBE_READ"  ),
    .width_a                       ( DATA_WIDTH              ),
    .width_b                       ( DATA_WIDTH              ),
    .width_byteena_a               ( 1                       ),
    .width_byteena_b               ( 1                       ),
    .widthad_a                     ( $clog2(LEN)             ),
    .widthad_b                     ( $clog2(LEN)             ),
    .wrcontrol_wraddress_reg_b     ( "CLOCK1"                )
) ram (
    .clock0    ( clock_a   ),
    .clocken0  ( cen_a     ),
    .address_a ( address_a ),
    .data_a    ( data_a    ),
    .wren_a    ( wren_a    ),
    .q_a       ( q_a       ),

    .clock1    ( clock_b   ),
    .clocken1  ( cen_b     ),
    .address_b ( address_b ),
    .data_b    ( data_b    ),
    .wren_b    ( wren_b    ),
    .q_b       ( q_b       ),

    .aclr0          ( 1'b0 ),
    .aclr1          ( 1'b0 ),
    .addressstall_a ( 1'b0 ),
    .addressstall_b ( 1'b0 ),
    .byteena_a      ( 1'b1 ),
    .byteena_b      ( 1'b1 ),
    .clocken2       ( 1'b1 ),
    .clocken3       ( 1'b1 ),
    .rden_a         ( 1'b1 ),
    .rden_b         ( 1'b1 ),
    .eccstatus      (      )
);

endmodule
