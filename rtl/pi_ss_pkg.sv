// Save-state record layouts shared by the board and the sequencer; a new field takes its bits from a reserved field.
package pi_ss_pkg;

// chunk 0 (global), one 64-bit word
typedef struct packed {
    logic  [3:0] rsv;
    logic  [5:0] c4;            // Z80 clock counter
    logic  [3:0] c6;            // pixel clock counter
    logic  [8:0] hc;
    logic  [8:0] vc;
    logic [31:0] ssp;
} ss_global_t;

// chunk 8 (board registers), two 64-bit words
typedef struct packed {
    logic  [7:0] rsv1;
    logic  [7:0] opl_sel;       // YM3812 selected register
    logic [24:0] rsv0;
    logic  [7:0] sound_data;    // YM3812 data latch
    logic        sound_addr;    // YM3812 address latch
    logic        upd_reset;
    logic        int_ack;
    logic        ipl2_n;
    logic        p1_invert;
    logic        flip_screen;
    logic        z80_nmi_n;
    logic  [7:0] sound_latch;
    logic [15:0] bg_scroll_x;
    logic [15:0] bg_scroll_y;
    logic [15:0] fg_scroll_x;
    logic [15:0] fg_scroll_y;
} ss_regs_t;

endpackage
