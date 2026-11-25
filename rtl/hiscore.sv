// High scores: hiscore.dat entries (download index 3); table restored from / saved to NVRAM (index 4) in 68000 work RAM.

module hiscore #(parameter MAX_ENTRIES = 8, ENTRIES_INDEX = 3, TABLE_INDEX = 4)
(
    input             clk,
    input             reset,

    // downloads and uploads
    input             ioctl_download,
    input             ioctl_upload,
    input             ioctl_wr,
    input      [15:0] ioctl_index,
    input      [26:0] ioctl_addr,
    input       [7:0] ioctl_dout,
    output      [7:0] ioctl_din,

    // frame tick, OSD save controls
    input             vblank,
    input             autosave,
    input             osd_open,
    input             save_now,
    output reg        upload_req,
    output            has_entries,

    // work RAM port (16 KB, byte offset bit 0 selects the low byte)
    input             ram_ok,
    input             ram_free,
    output     [12:0] ram_addr,
    output      [7:0] ram_wdata,
    output            ram_we_h,
    output            ram_we_l,
    input      [15:0] ram_q
);

///////////////////////////////////////////////////////////////////////////////
// entries: address[4], length[2], first byte, last byte (big endian)

reg  [13:0] e_off   [MAX_ENTRIES];
reg  [15:0] e_len   [MAX_ENTRIES];
reg   [7:0] e_first [MAX_ENTRIES];
reg   [7:0] e_last  [MAX_ENTRIES];
reg   [3:0] n_entries = 0;

wire        dl_entries = ioctl_download && ioctl_index == ENTRIES_INDEX;
wire        dl_table   = ioctl_download && ioctl_index == TABLE_INDEX;
wire  [3:0] dl_e       = ioctl_addr[6:3];

always @(posedge clk) begin
    if (dl_entries && ioctl_wr && ioctl_addr < MAX_ENTRIES * 8) begin
        case (ioctl_addr[2:0])
            3'd2: e_off[dl_e][13:8] <= ioctl_dout[5:0];
            3'd3: e_off[dl_e][7:0]  <= ioctl_dout;
            3'd4: e_len[dl_e][15:8] <= ioctl_dout;
            3'd5: e_len[dl_e][7:0]  <= ioctl_dout;
            3'd6: e_first[dl_e]     <= ioctl_dout;
            3'd7: begin e_last[dl_e] <= ioctl_dout; n_entries <= dl_e + 1'd1; end
            default: ;
        endcase
    end
end

assign has_entries = n_entries != 0;

///////////////////////////////////////////////////////////////////////////////
// table buffer, two banks: tb_cur holds the last complete table (NVRAM, or a finished copy), the copy fills the other

reg  [7:0] tbuf [512];
reg  [7:0] tbuf_q;
reg  [7:0] tbuf_rd;
reg        tbuf_valid = 0;
reg        tb_cur = 0;
reg        tbuf_we;
reg  [8:0] tbuf_wa;
reg  [7:0] tbuf_wd;

wire        uploading = ioctl_upload && ioctl_index == TABLE_INDEX;

always @(posedge clk) begin
    if (dl_table && ioctl_wr && ioctl_addr[26:8] == 0) tbuf[{ tb_cur, ioctl_addr[7:0] }] <= ioctl_dout;
    else if (tbuf_we) tbuf[tbuf_wa] <= tbuf_wd;
    tbuf_q <= tbuf[{ tb_cur, uploading ? ioctl_addr[7:0] : tbuf_rd }];
end

// upload: the last complete table, zeros while none is held
assign ioctl_din = tbuf_valid ? tbuf_q : 8'h00;

///////////////////////////////////////////////////////////////////////////////
// check / restore / copy sequencer

typedef enum logic [2:0] { H_IDLE, H_CHECK, H_RESTORE, H_COPY } hst_t;
hst_t hst = H_IDLE;

reg         table_ok = 0;
reg         armed = 0;
reg         match;
reg   [3:0] e;
reg  [15:0] k;
reg   [8:0] n;
reg   [1:0] step;
reg         vbl_l = 0;
reg  [13:0] f_off;

reg         lane;

// restore write: in the cycle the 68000 side of the RAM is idle
wire        f_we      = hst == H_RESTORE && step == 2'd3 && ram_free && ram_ok && !uploading && !reset;

assign ram_addr  = f_off[13:1];
assign ram_wdata = tbuf_q;
assign ram_we_h  = f_we & ~f_off[0];
assign ram_we_l  = f_we &  f_off[0];

always @(posedge clk) lane <= f_off[0];
wire  [7:0] ram_byte = lane ? ram_q[7:0] : ram_q[15:8];

// last byte of the current entry, and the entry check result including it
wire        last_e    = e + 1'd1 == n_entries;
wire        all_match = match && ram_byte == e_last[e];

// a finished copy becomes the current bank
wire        copy_done = hst == H_COPY && step == 2'd2 && last_e && k + 1'd1 == e_len[e] && ram_ok && !uploading && !reset;

// a downloaded table counts only with a non-zero byte (Main saves the zeros above when no table was held)
always @(posedge clk) begin
    if (dl_table && ioctl_wr && ioctl_dout != 8'h00) tbuf_valid <= 1;
    if (copy_done) begin
        tbuf_valid <= 1;
        tb_cur <= ~tb_cur;
    end
end

// each RAM access: step 0 address, step 1 RAM latches it, step 2 data valid (step 3 write for a restore)
always @(posedge clk) begin
    vbl_l   <= vblank;
    tbuf_we <= 0;

    if (reset) begin
        hst      <= H_IDLE;
        table_ok <= 0;
        armed    <= 0;
    end else if (!uploading && ram_ok) begin
        case (hst)
            H_IDLE: if (vblank && !vbl_l && has_entries) begin
                e <= 0;
                k <= 0;
                n <= 0;
                step <= 0;
                match <= 1;
                hst <= table_ok ? H_COPY : H_CHECK;
            end

            // first and last byte of every entry
            H_CHECK: begin
                step <= step + 1'd1;
                if (step == 2'd0) f_off <= k[0] ? e_off[e] + e_len[e][13:0] - 1'd1 : e_off[e];
                if (step == 2'd2) begin
                    step <= 0;
                    if (!k[0]) begin
                        if (ram_byte != e_first[e]) match <= 0;
                        k <= 1;
                    end else begin
                        if (ram_byte != e_last[e]) match <= 0;
                        k <= 0;
                        if (last_e) begin
                            hst <= H_IDLE;
                            if (!armed) begin
                                if (!all_match) armed <= 1;
                            end else if (all_match) begin
                                if (tbuf_valid) begin
                                    e <= 0;
                                    n <= 0;
                                    hst <= H_RESTORE;
                                end else begin
                                    table_ok <= 1;
                                end
                            end
                        end else begin
                            e <= e + 1'd1;
                        end
                    end
                end
            end

            // buffer -> RAM
            H_RESTORE: begin
                if (step != 2'd3) step <= step + 1'd1;
                if (step == 2'd0) begin
                    f_off <= e_off[e] + k[13:0];
                    tbuf_rd <= n[7:0];
                end
                if (step == 2'd3 && ram_free) begin
                    step <= 0;
                    n <= n + 1'd1;
                    if (k + 1'd1 == e_len[e]) begin
                        k <= 0;
                        if (last_e) begin
                            hst <= H_IDLE;
                            table_ok <= 1;
                        end else begin
                            e <= e + 1'd1;
                        end
                    end else begin
                        k <= k + 1'd1;
                    end
                end
            end

            // RAM -> buffer
            H_COPY: begin
                step <= step + 1'd1;
                if (step == 2'd0) f_off <= e_off[e] + k[13:0];
                if (step == 2'd2) begin
                    step <= 0;
                    tbuf_we <= 1;
                    tbuf_wa <= { ~tb_cur, n[7:0] };
                    tbuf_wd <= ram_byte;
                    n <= n + 1'd1;
                    if (k + 1'd1 == e_len[e]) begin
                        k <= 0;
                        if (last_e) hst <= H_IDLE;
                        else e <= e + 1'd1;
                    end else begin
                        k <= k + 1'd1;
                    end
                end
            end

            default: hst <= H_IDLE;
        endcase
    end else begin
        // RAM port taken by an upload or a save state: repeat the current access
        step <= 0;
    end
end

///////////////////////////////////////////////////////////////////////////////
// save request: on OSD open (autosave) or on the OSD save command, once the table is valid and a complete copy is held

reg osd_l = 0, save_l = 0;
always @(posedge clk) begin
    osd_l  <= osd_open;
    save_l <= save_now;
    upload_req <= table_ok && tbuf_valid && ((autosave && osd_open && !osd_l) || (save_now && !save_l));
end

endmodule
