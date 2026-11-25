// Save states for this board: 68000 / Z80 / YM3812 sequencer and the state chunks streamed to DDR3.
import system_consts::*;
import pi_ss_pkg::*;

// RAM chunk: one RAM word per save-state access
module ss_ram_chunk #(parameter AW = 10, DW = 16, SS_IDX = 0)
(
    input               clk,
    ssbus_if.slave      ssbus,
    output              active,
    output [AW-1:0]     addr,
    output [DW-1:0]     wdata,
    output              we,
    input  [DW-1:0]     q
);

assign active = ssbus.access(SS_IDX);
assign addr   = ssbus.addr[AW-1:0];
assign wdata  = ssbus.data[DW-1:0];
assign we     = active & ssbus.write;

reg read_delay = 0;

always @(posedge clk) begin
    ssbus.setup(SS_IDX, 32'(2**AW), (DW == 16) ? 1 : 0);
    if (active) begin
        if (ssbus.write) begin
            ssbus.write_ack(SS_IDX);
        end else if (ssbus.read) begin
            if (read_delay) ssbus.read_response(SS_IDX, 64'(q));
            read_delay <= 1;
        end
    end else begin
        read_delay <= 0;
    end
end

endmodule

// Register chunk: 64-bit words captured from the board and restored to it
module ss_reg_chunk #(parameter WORDS = 1, SS_IDX = 0)
(
    input                       clk,
    ssbus_if.slave              ssbus,
    input      [64*WORDS-1:0]   din,
    output reg [64*WORDS-1:0]   dout,
    output reg                  written
);

wire [7:0] wi = ssbus.addr[7:0];

always @(posedge clk) begin
    ssbus.setup(SS_IDX, WORDS, 3);
    written <= 0;
    if (ssbus.access(SS_IDX)) begin
        if (ssbus.write) begin
            if (wi < WORDS) dout[wi*64 +: 64] <= ssbus.data;
            written <= 1;
            ssbus.write_ack(SS_IDX);
        end else if (ssbus.read) begin
            ssbus.read_response(SS_IDX, (wi < WORDS) ? din[wi*64 +: 64] : 64'd0);
        end
    end
end

endmodule

// Save / restore sequencer
module pi_ss
(
    input              clk,
    input              reset,

    // requests from the save-state UI
    input              save_req,
    input              load_req,
    input        [1:0] slot,
    output             busy,
    output reg         saved,          // pulse: a save is complete in DDR3
    output reg   [1:0] slot_used,      // slot taken at the last request
    output reg         pos_reject,     // pulse: restore refused, its video line does not exist in this refresh mode

    // DDR3 for the state stream
    ddr_if.to_host     ddr,

    // 68000 bus
    input       [23:1] cpu_a,
    input              cpu_as_n,
    input              cpu_uds_n,
    input              cpu_lds_n,
    input              cpu_rw,
    input        [2:0] cpu_fc,
    input       [15:0] cpu_dout,
    input              cpu_cen,
    output             cpu_run,
    output             cpu_irq7,
    output             cpu_reset,
    output             cpu_hit,
    output reg  [15:0] cpu_din,

    // Z80
    input              z80_m1_n,
    input        [7:0] z80_di,
    input              z80_nmi_n,
    input              z80_int_n,
    input              z80_cen,
    input              z80_mreq_n,
    input      [211:0] z80_reg,
    output             z80_run,
    output             z80_reset,
    output             z80_dirset,
    output     [211:0] z80_dir,
    output reg         z80_nmi_set,

    // YM3812 inputs as seen by the chip, and the register replay that drives them during a restore
    input              opl_write,
    input              opl_a0,
    input        [7:0] opl_din,
    output             opl_replay,
    output reg         opl_r_a0,
    output reg   [7:0] opl_r_din,
    output reg         opl_r_write,
    output             snd_reset,

    // video position and Z80 clock phase
    input        [8:0] vc,
    input        [8:0] hc,
    input        [8:0] vtotal,
    input        [3:0] c6,
    input        [5:0] c4,
    output reg         c4_load,
    output       [5:0] c4_val,

    // board registers (opl_sel of regs_in is filled in here)
    input  ss_regs_t   regs_in,
    output ss_regs_t   regs_out,
    output reg         regs_load,

    // RAM chunks
    output             wram_active,
    output      [12:0] wram_addr,
    output      [15:0] wram_wdata,
    output             wram_we,
    input       [15:0] wram_q,

    output             spr_active,
    output       [9:0] spr_addr,
    output      [15:0] spr_wdata,
    output             spr_we,
    input       [15:0] spr_q,

    output             txt_active,
    output       [9:0] txt_addr,
    output      [15:0] txt_wdata,
    output             txt_we,
    input       [15:0] txt_q,

    output             fg_active,
    output      [12:0] fg_addr,
    output      [15:0] fg_wdata,
    output             fg_we,
    input       [15:0] fg_q,

    output             pal_active,
    output       [9:0] pal_addr,
    output      [15:0] pal_wdata,
    output             pal_we,
    input       [15:0] pal_q,

    output             zram_active,
    output      [10:0] zram_addr,
    output       [7:0] zram_wdata,
    output             zram_we,
    input        [7:0] zram_q
);

// chunk indices
localparam SSIDX_GLOBAL = 0, SSIDX_WRAM = 1, SSIDX_SPR = 2, SSIDX_TXT = 3, SSIDX_FG = 4, SSIDX_PAL = 5,
           SSIDX_ZRAM = 6, SSIDX_ZREG = 7, SSIDX_REGS = 8, SSIDX_OPL = 9;

///////////////////////////////////////////////////////////////////////////////
// state stream

reg  ss_write = 0, ss_read = 0;
wire ss_busy;

ssbus_if ssbus();
ssbus_if ssb[10]();

ssbus_mux #(.COUNT(10)) ssmux (
    .clk,
    .slave(ssbus),
    .masters(ssb)
);

// DDR3: the sequencer's own slot-header accesses (a), then the state stream (b)
ddr_if ddr_aux(), ddr_str();

ddr_mux ddr_mux (
    .clk,
    .x(ddr),
    .a(ddr_aux),
    .b(ddr_str)
);

reg         aux_acq = 0, aux_rd = 0, aux_wr = 0;
reg  [31:0] aux_addr;
reg   [7:0] aux_be;

assign ddr_aux.acquire    = aux_acq;
assign ddr_aux.addr       = aux_addr;
assign ddr_aux.wdata      = 64'd0;
assign ddr_aux.read       = aux_rd;
assign ddr_aux.write      = aux_wr;
assign ddr_aux.burstcnt   = 8'd1;
assign ddr_aux.byteenable = aux_be;

wire [31:0] slot_base = SS_DDR_BASE + { 8'd0, slot_used, 22'd0 };

save_state_data save_state_data (
    .clk,
    .reset,
    .ddr(ddr_str),
    .read_start(ss_read),
    .write_start(ss_write),
    .index(slot_used),
    .busy(ss_busy),
    .ssbus(ssbus)
);

// global chunk: SSP, video position at the SSP write, Z80 clock phase
reg  [31:0] ssp_saved;
reg   [8:0] pos_vc, pos_hc;
reg   [3:0] pos_c6;
reg   [5:0] pos_c4;
wire [63:0] global_out;
wire        global_written;
ss_global_t global_in, global_rd;

always_comb begin
    global_in     = '0;
    global_in.c4  = pos_c4;
    global_in.c6  = pos_c6;
    global_in.hc  = pos_hc;
    global_in.vc  = pos_vc;
    global_in.ssp = ssp_saved;
end
assign global_rd = global_out;

ss_reg_chunk #(.WORDS(1), .SS_IDX(SSIDX_GLOBAL)) global_chunk (
    .clk, .ssbus(ssb[0]),
    .din(global_in),
    .dout(global_out),
    .written(global_written)
);

ss_ram_chunk #(.AW(13), .DW(16), .SS_IDX(SSIDX_WRAM)) wram_chunk (
    .clk, .ssbus(ssb[1]), .active(wram_active), .addr(wram_addr), .wdata(wram_wdata), .we(wram_we), .q(wram_q));
ss_ram_chunk #(.AW(10), .DW(16), .SS_IDX(SSIDX_SPR)) spr_chunk (
    .clk, .ssbus(ssb[2]), .active(spr_active), .addr(spr_addr), .wdata(spr_wdata), .we(spr_we), .q(spr_q));
ss_ram_chunk #(.AW(10), .DW(16), .SS_IDX(SSIDX_TXT)) txt_chunk (
    .clk, .ssbus(ssb[3]), .active(txt_active), .addr(txt_addr), .wdata(txt_wdata), .we(txt_we), .q(txt_q));
ss_ram_chunk #(.AW(13), .DW(16), .SS_IDX(SSIDX_FG)) fg_chunk (
    .clk, .ssbus(ssb[4]), .active(fg_active), .addr(fg_addr), .wdata(fg_wdata), .we(fg_we), .q(fg_q));
ss_ram_chunk #(.AW(10), .DW(16), .SS_IDX(SSIDX_PAL)) pal_chunk (
    .clk, .ssbus(ssb[5]), .active(pal_active), .addr(pal_addr), .wdata(pal_wdata), .we(pal_we), .q(pal_q));
ss_ram_chunk #(.AW(11), .DW(8), .SS_IDX(SSIDX_ZRAM)) zram_chunk (
    .clk, .ssbus(ssb[6]), .active(zram_active), .addr(zram_addr), .wdata(zram_wdata), .we(zram_we), .q(zram_q));

// Z80 registers (T80 REG / DIR layout)
wire [255:0] zreg_out;
ss_reg_chunk #(.WORDS(4), .SS_IDX(SSIDX_ZREG)) zreg_chunk (
    .clk, .ssbus(ssb[7]), .din({ 44'd0, z80_reg }), .dout(zreg_out), .written());
assign z80_dir = zreg_out[211:0];

// YM3812 selected register
reg  [7:0] opl_sel = 0;

// board registers
ss_regs_t   regs_save;
wire [127:0] regs_dout;

always_comb begin
    regs_save         = regs_in;
    regs_save.opl_sel = opl_sel;
end
assign regs_out = regs_dout;

ss_reg_chunk #(.WORDS(2), .SS_IDX(SSIDX_REGS)) regs_chunk (
    .clk, .ssbus(ssb[8]), .din(regs_save), .dout(regs_dout), .written());

///////////////////////////////////////////////////////////////////////////////
// YM3812 register shadow (the 256 register values)

reg  [7:0] opl_shadow[256];
reg  [7:0] opl_rd_addr;
reg  [7:0] opl_rd_q;

wire        opl_chunk_active = ssb[9].access(SSIDX_OPL);
wire  [7:0] opl_chunk_addr   = ssb[9].addr[7:0];
reg         opl_read_delay = 0;

// shadow write: the chip's own register writes, or the chunk during a restore
wire        shadow_we   = opl_chunk_active ? ssb[9].write : (opl_write & opl_a0 & ~(opl_sel == 8'h04 & opl_din[7]));
wire  [7:0] shadow_addr = opl_chunk_active ? opl_chunk_addr : opl_sel;
wire  [7:0] shadow_data = opl_chunk_active ? ssb[9].data[7:0] : opl_din;

always @(posedge clk) begin
    if (shadow_we) opl_shadow[shadow_addr] <= shadow_data;
    opl_rd_q <= opl_shadow[opl_chunk_active ? opl_chunk_addr : opl_rd_addr];
end

// shadow entries written since the last game reset, which zeroes the chip's registers and its selected register
reg [255:0] opl_valid = '0;
reg         opl_rd_valid;
always @(posedge clk) begin
    if (reset) begin
        opl_sel   <= 0;
        opl_valid <= '0;
    end else begin
        if (opl_write & ~opl_a0) opl_sel <= opl_din;
        if (shadow_we) opl_valid[shadow_addr] <= 1'b1;
    end
    opl_rd_valid <= opl_valid[opl_chunk_active ? opl_chunk_addr : opl_rd_addr];
end
wire  [7:0] opl_rd_val = opl_rd_valid ? opl_rd_q : 8'd0;

always @(posedge clk) begin
    ssb[9].setup(SSIDX_OPL, 32'd256, 0);
    if (opl_chunk_active) begin
        if (ssb[9].write) begin
            ssb[9].write_ack(SSIDX_OPL);
        end else if (ssb[9].read) begin
            if (opl_read_delay) ssb[9].read_response(SSIDX_OPL, { 56'd0, opl_rd_val });
            opl_read_delay <= 1;
        end
    end else begin
        opl_read_delay <= 0;
    end
end

///////////////////////////////////////////////////////////////////////////////
// 68000 handler at $FF0000: saves the registers on the stack, writes the SSP to $FF0000, restores them and returns

logic [15:0] handler[16] = '{
    16'h48e7, 16'hfffe,            // movem.l d0-d7/a0-a6,-(a7)
    16'h4e6e,                      // move.l usp,a6
    16'h2f0e,                      // move.l a6,-(a7)
    16'h4df9, 16'h00ff, 16'h0000,  // lea $ff0000,a6 (restore entry point $ff0008)
    16'h2c8f,                      // move.l a7,(a6)
    16'h2c5f,                      // move.l (a7)+,a6
    16'h4e66,                      // move.l a6,usp
    16'h4cdf, 16'h7fff,            // movem.l (a7)+,d0-d7/a0-a6
    16'h4e73,                      // rte
    16'h0000, 16'h0000, 16'h0000
};

///////////////////////////////////////////////////////////////////////////////
// sequencer

typedef enum logic [4:0] {
    ST_IDLE,
    ST_S_Z80,       // 68000 held; Z80 runs to a safe opcode fetch
    ST_S_IRQ,       // 68000 runs with interrupt level 7 until it acknowledges it
    ST_S_HANDLER,   // 68000 runs the handler until the SSP write
    ST_S_WRITE,     // 68000 held; state written to DDR3
    ST_S_SYNC,      // wait for the video position recorded at the SSP write
    ST_EXIT,        // 68000 runs the handler tail; ends at the first fetch outside it
    ST_R_READ,      // everything held; state read from DDR3
    ST_R_LOAD,      // board registers loaded; Z80 and sound chips in reset
    ST_R_OPL,       // YM3812 registers replayed
    ST_R_Z80,       // Z80 registers loaded
    ST_R_RESET,     // 68000 reset with the saved SSP and the handler as PC
    ST_R_HANDLER,   // 68000 runs the handler tail until the SSP write
    ST_R_SYNC,      // wait for the saved video position
    ST_S_MARK,      // 68000 held; slot size word cleared so an interrupted save reads as an empty slot
    ST_R_CHECK,     // game runs; slot header and global word read, restore refused if the saved line is not in this mode
    ST_S_Z80T,      // 68000 held; Z80 takes one more clock edge (it commits the last instruction's write), then held in T2
    ST_R_Z80T       // Z80 takes two clock edges from reset, to T2 of the restored opcode fetch
} st_t;

st_t st = ST_IDLE;

reg  [15:0] cnt;
reg   [9:0] opl_idx;
reg         got_state;
reg         aux_ph = 0, aux_n = 0;
ss_global_t chk_glob;

assign chk_glob = ddr_aux.rdata;
reg         nmi_saved_low;
reg         z80_prefix = 0;
reg         z80_after_ei = 0;
reg         z80_m1_n_l = 1;
reg         cpu_ds_n_l = 1;

wire [23:0] byte_addr  = { cpu_a, 1'b0 };
wire        in_handler = cpu_a[23:5] == 19'h7f800;
wire        at_vector  = byte_addr == 24'h00007c || byte_addr == 24'h00007e;
wire        at_reset   = byte_addr[23:3] == 21'd0;
wire        override   = st == ST_S_HANDLER || st == ST_S_MARK || st == ST_S_WRITE || st == ST_S_SYNC || st == ST_EXIT ||
                         st == ST_R_RESET || st == ST_R_HANDLER || st == ST_R_SYNC;
wire        serve_rst  = st == ST_R_RESET || st == ST_R_HANDLER;

assign cpu_hit = override && !cpu_as_n && cpu_rw && (in_handler || at_vector || (serve_rst && at_reset));

always @(*) begin
    if (in_handler)     cpu_din = handler[cpu_a[4:1]];
    else if (at_vector) cpu_din = cpu_a[1] ? 16'h0000 : 16'h00ff;
    else case (cpu_a[2:1])
        2'd0: cpu_din = ssp_saved[31:16];
        2'd1: cpu_din = ssp_saved[15:0];
        2'd2: cpu_din = 16'h00ff;
        default: cpu_din = 16'h0008;
    endcase
end

// bus events: first clock with a data strobe asserted
wire cpu_ds_n   = cpu_uds_n & cpu_lds_n;
wire ds_start   = cpu_ds_n_l & ~cpu_ds_n & ~cpu_as_n;
wire iack7      = ds_start && cpu_fc == 3'b111 && cpu_a[3:1] == 3'b111;
wire ssp_wr_hi  = ds_start && !cpu_rw && byte_addr == 24'hff0000;
wire ssp_wr_lo  = ds_start && !cpu_rw && byte_addr == 24'hff0002;
wire fetch_out  = ds_start && cpu_rw && cpu_fc[1:0] == 2'b10 && !in_handler;

// Z80 safe point: start of an opcode fetch that is not part of a prefixed instruction or right after EI, with no interrupt about to be taken
// Z80 HALT state not saved: the sound program (one ROM for all five sets) never executes HALT
wire z80_m1_fall = z80_m1_n_l & ~z80_m1_n;
wire z80_safe    = z80_m1_fall && !z80_prefix && !z80_after_ei && z80_nmi_n && !(~z80_int_n && z80_reg[210]);
wire pos_match   = vc == pos_vc && hc == pos_hc && c6 == pos_c6;
wire pos_gone    = pos_vc > vtotal;

always @(posedge clk) begin
    z80_m1_n_l <= z80_m1_n;
    cpu_ds_n_l <= cpu_ds_n;
    if (~z80_m1_n_l & z80_m1_n) begin
        z80_prefix   <= z80_di == 8'hdd || z80_di == 8'hfd || z80_di == 8'hcb || z80_di == 8'hed;
        z80_after_ei <= z80_di == 8'hfb;
    end
end

always @(posedge clk) begin
    ss_write    <= 0;
    ss_read     <= 0;
    regs_load   <= 0;
    c4_load     <= 0;
    z80_nmi_set <= 0;
    opl_r_write <= 0;
    saved       <= 0;
    pos_reject  <= 0;
    if (global_written) got_state <= 1;

    if (reset) begin
        st <= ST_IDLE;
        nmi_saved_low <= 0;
        aux_acq <= 0;
        aux_rd <= 0;
        aux_wr <= 0;
        aux_ph <= 0;
        aux_n <= 0;
    end else case (st)
        ST_IDLE: begin
            cnt <= 0;
            aux_ph <= 0;
            aux_n <= 0;
            if (save_req) begin
                slot_used <= slot;
                st <= ST_S_Z80;
            end else if (load_req) begin
                slot_used <= slot;
                aux_acq <= 1;
                st <= ST_R_CHECK;
            end
        end

        // save
        ST_S_Z80: if (z80_safe) st <= ST_S_Z80T;

        ST_S_Z80T: begin
            if (z80_cen) cnt <= cnt + 1'd1;
            if (cnt == 16'd1) begin
                cnt <= 0;
                // an interrupt acknowledge (no MREQ in T1) is not a fetch: run on to the next safe one
                st <= z80_mreq_n ? ST_S_Z80 : ST_S_IRQ;
            end
        end

        ST_S_IRQ: if (iack7) st <= ST_S_HANDLER;

        ST_S_HANDLER: begin
            if (ssp_wr_hi) ssp_saved[31:16] <= cpu_dout;
            if (ssp_wr_lo) begin
                ssp_saved[15:0] <= cpu_dout;
                pos_vc <= vc;
                pos_hc <= hc;
                pos_c6 <= c6;
                pos_c4 <= c4;
                aux_acq <= 1;
                st <= ST_S_MARK;
            end
        end

        // size word (bytes 4-7) cleared, change counter (bytes 0-3) kept; the stream writes the full header last
        ST_S_MARK: if (!ddr_aux.busy) begin
            if (!aux_ph) begin
                aux_addr <= slot_base;
                aux_be <= 8'hf0;
                aux_wr <= 1;
                aux_ph <= 1;
            end else begin
                aux_wr <= 0;
                aux_ph <= 0;
                ss_write <= 1;
                cnt <= 0;
                st <= ST_S_WRITE;
            end
        end

        ST_S_WRITE: begin
            cnt <= cnt + 1'd1;
            if (ss_busy) aux_acq <= 0;
            if (cnt > 16'd4 && !ss_busy && !ss_write) begin
                saved <= 1;
                st <= ST_S_SYNC;
            end
        end

        ST_S_SYNC: if (pos_match || pos_gone) st <= ST_EXIT;

        ST_EXIT: if (fetch_out) begin
            if (nmi_saved_low) z80_nmi_set <= 1;
            nmi_saved_low <= 0;
            st <= ST_IDLE;
        end

        // restore: slot header (size word) and the global chunk word (base + 16) read before anything is held
        ST_R_CHECK: begin
            if (!ddr_aux.busy) aux_rd <= 0;
            if (!aux_ph) begin
                if (!ddr_aux.busy) begin
                    aux_addr <= slot_base + (aux_n ? 32'd16 : 32'd0);
                    aux_be <= 8'hff;
                    aux_rd <= 1;
                    aux_ph <= 1;
                end
            end else if (ddr_aux.rdata_ready) begin
                aux_rd <= 0;
                aux_ph <= 0;
                aux_n <= 1;
                if (!aux_n) begin
                    // empty slot: nothing to restore
                    if (ddr_aux.rdata[63:32] == 32'd0) begin
                        aux_acq <= 0;
                        st <= ST_IDLE;
                    end
                end else if (chk_glob.vc > vtotal) begin
                    aux_acq <= 0;
                    pos_reject <= 1;
                    st <= ST_IDLE;
                end else begin
                    got_state <= 0;
                    ss_read <= 1;
                    cnt <= 0;
                    st <= ST_R_READ;
                end
            end
        end

        ST_R_READ: begin
            cnt <= cnt + 1'd1;
            if (ss_busy) aux_acq <= 0;
            if (cnt > 16'd4 && !ss_busy && !ss_read) begin
                cnt <= 0;
                if (got_state) begin
                    pos_vc <= global_rd.vc;
                    pos_hc <= global_rd.hc;
                    pos_c6 <= global_rd.c6;
                    pos_c4 <= global_rd.c4;
                    ssp_saved <= global_rd.ssp;
                    regs_load <= 1;
                    st <= ST_R_LOAD;
                end else begin
                    st <= ST_IDLE;
                end
            end
        end

        // 2048 clocks: the YM3812 reset must last 18 operator cycles (72 cycles of its 4 MHz enable) to clear every slot
        ST_R_LOAD: begin
            nmi_saved_low <= ~regs_out.z80_nmi_n;
            cnt <= cnt + 1'd1;
            if (cnt == 16'd2047) begin
                cnt <= 0;
                opl_idx <= 0;
                st <= ST_R_OPL;
            end
        end

        // per register: select (cnt 0-3), data (cnt 8-11), then let the chip update its slots
        ST_R_OPL: begin
            cnt <= cnt + 1'd1;
            opl_rd_addr <= opl_order(opl_idx[7:0]);
            if (cnt < 16'd4) begin
                opl_r_a0 <= 0;
                opl_r_din <= (opl_idx == 10'd256) ? regs_out.opl_sel : opl_order(opl_idx[7:0]);
                opl_r_write <= 1;
            end else if (cnt >= 16'd8 && cnt < 16'd12 && opl_idx != 10'd256) begin
                opl_r_a0 <= 1;
                opl_r_din <= opl_rd_val;
                opl_r_write <= 1;
            end else if (cnt == 16'd2000) begin
                cnt <= 0;
                if (opl_idx == 10'd256) st <= ST_R_Z80;
                opl_idx <= opl_idx + 1'd1;
            end
        end

        ST_R_Z80: begin
            cnt <= cnt + 1'd1;
            if (cnt == 16'd31) begin
                cnt <= 0;
                st <= ST_R_Z80T;
            end
        end

        ST_R_Z80T: begin
            if (z80_cen) cnt <= cnt + 1'd1;
            if (cnt == 16'd2) begin
                cnt <= 0;
                st <= ST_R_RESET;
            end
        end

        ST_R_RESET: if (cpu_cen) begin
            cnt <= cnt + 1'd1;
            if (cnt == 16'd63) st <= ST_R_HANDLER;
        end

        ST_R_HANDLER: if (ssp_wr_lo) st <= ST_R_SYNC;

        ST_R_SYNC: if (pos_match || pos_gone) begin
            c4_load <= 1;
            st <= ST_EXIT;
        end

        default: st <= ST_IDLE;
    endcase
end

// replay order: every register except the timer control, then the timer control (register 4)
function [7:0] opl_order(input [7:0] i);
    opl_order = (i == 8'hff) ? 8'h04 : (i >= 8'h04) ? i + 8'd1 : i;
endfunction

assign busy       = st != ST_IDLE && st != ST_R_CHECK;
assign cpu_run    = st == ST_S_IRQ || st == ST_S_HANDLER || st == ST_EXIT || st == ST_R_RESET || st == ST_R_HANDLER;
assign cpu_irq7   = st == ST_S_IRQ;
assign cpu_reset  = st == ST_R_RESET;
assign z80_run    = st == ST_S_Z80 || st == ST_S_Z80T || st == ST_R_Z80T || st == ST_IDLE;
assign z80_reset  = st == ST_R_LOAD || st == ST_R_OPL;
assign z80_dirset = st == ST_R_Z80 && cnt < 16'd16;
assign snd_reset  = st == ST_R_LOAD;
assign opl_replay = st == ST_R_OPL;
assign c4_val     = pos_c4;

endmodule
