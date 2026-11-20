// Two-channel mixer: 16-bit OPL2 and 9-bit uPD7759 samples, 4.4 fixed-point gains, saturated 16-bit output.

module audio_mix
(
    input                clk,
    input                rst,

    input  signed [15:0] opl,
    input  signed  [8:0] upd,
    input          [7:0] opl_gain,
    input          [7:0] upd_gain,

    output signed [15:0] mixed
);

// Inputs aligned to 16 bits.
wire signed [15:0] opl_s = opl;
wire signed [15:0] upd_s = { upd, 7'd0 };

// Gains as positive signed values.
wire signed  [8:0] opl_g = { 1'b0, opl_gain };
wire signed  [8:0] upd_g = { 1'b0, upd_gain };

// Products, sum with two guard bits, then the integer part of the 4.4 result.
reg  signed [23:0] opl_p, upd_p;
reg  signed [25:0] psum;
wire signed [21:0] pint = psum[25:4];

always @(posedge clk) begin
    opl_p <= opl_g * opl_s;
    upd_p <= upd_g * upd_s;
    psum  <= { {2{opl_p[23]}}, opl_p } + { {2{upd_p[23]}}, upd_p };
end

// Saturation flags from the bits above the 16-bit range.
wire ovf     = pint[21:16] != {6{pint[15]}};
wire ovf_pos = ovf & ~pint[21];
wire ovf_neg = ovf &  pint[21];

// Output register; reset halves it every clock.
reg  signed [15:0] sum;

always @(posedge clk) begin
    if (rst)
        sum <= sum >>> 1;
    else
        sum <= ovf_pos ? 16'h7fff : ovf_neg ? 16'h8000 : pint[15:0];
end

assign mixed = sum;

endmodule
