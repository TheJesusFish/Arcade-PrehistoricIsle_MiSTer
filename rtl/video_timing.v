
module video_timing
(
    input       clk,
    input       clk_pix,
    input       reset,

    input  [2:0] pcb,
    input        refresh_mod,

    input  signed [3:0] hs_offset,
    input  signed [3:0] vs_offset,

    input  signed [3:0] hs_width,
    input  signed [3:0] vs_width,

    output [8:0] hc,
    output [8:0] vc,
    output [8:0] vtotal,

    output reg  hsync,
    output reg  vsync,

    output reg  hbl,
    output reg  vbl
);

// sync position and width adjustments as signed values (-8..7)
wire signed [10:0] hs_ofs = hs_offset;
wire signed [10:0] hs_wid = hs_width;
wire signed [10:0] vs_ofs = vs_offset;
wire signed [10:0] vs_wid = vs_width;

wire [8:0] h_ofs = 0;
wire [8:0] HBL_START  = 256;
wire [8:0] HBL_END    = 0;
wire [8:0] HS_START   = 11'sd300 + hs_ofs;
wire [8:0] HS_END     = 11'sd332 + hs_ofs + hs_wid;
wire [8:0] HTOTAL     = 383;

wire [8:0] v_ofs = 0;
wire [8:0] VBL_START  = 241;
wire [8:0] VBL_END    = 17;
wire [8:0] VTOTAL     = 288 - ( refresh_mod ? 0 : 25 );

// last line of the frame in the current refresh mode
assign vtotal = VTOTAL;

// vsync start and length (at least one line), wrapped at the end of the frame
wire signed [10:0] vs_start_raw = ( refresh_mod ? 11'sd261 : 11'sd251 ) + vs_ofs;
wire signed [10:0] vs_len_raw   = ( refresh_mod ? 11'sd8 : 11'sd6 ) + vs_wid;
wire        [10:0] vs_len       = ( vs_len_raw < 11'sd1 ) ? 11'd1 : vs_len_raw;
wire        [10:0] vs_end_raw   = vs_start_raw + vs_len;
wire        [10:0] vlines       = VTOTAL + 1'd1;
wire [8:0] VS_START   = ( vs_start_raw >= $signed(vlines) ) ? vs_start_raw - vlines : vs_start_raw;
wire [8:0] VS_END     = ( vs_end_raw >= vlines ) ? vs_end_raw - vlines : vs_end_raw;

reg [8:0] v;
reg [8:0] h;

assign vc = v - v_ofs;
assign hc = h - h_ofs;

always @ (posedge clk) begin
    if (reset && clk_pix) begin
        h <= 0;
        v <= 0;

        hbl <= 0;
        vbl <= 0;

        hsync <= 0;
        vsync <= 0;
    end else if ( clk_pix == 1 ) begin
        // counter
        if (h == HTOTAL) begin
            h <= 0;
            v <= v + 1'd1;

            if ( v == VTOTAL ) begin
                v <= 0;
            end
        end else begin
            h <= h + 1'd1;
        end

        // h signals
        if ( h == HBL_START ) begin
            hbl <= 1;
        end else if ( h == HBL_END ) begin
            hbl <= 0;
        end

        // v signals
        if ( v == VBL_START ) begin
            vbl <= 1;
        end else if ( v == VBL_END ) begin
            vbl <= 0;
        end

        if ( v == (VS_START ) ) begin
            vsync <= 1;
        end else if ( v == (VS_END ) ) begin
            vsync <= 0;
        end

        if ( h == (HS_START ) ) begin
            hsync <= 1;
        end else if ( h == (HS_END ) ) begin
            hsync <= 0;
        end
    end
end

endmodule

