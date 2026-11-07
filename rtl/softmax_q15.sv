// softmax_q15: 8-lane fixed-point softmax for the digital precision island (report Sections 2.1(4), 4.2).
// Q8.8 scores in, Q15 probabilities out. Contract = golden/src/lib.rs `softmax::q15`.
// Registered output, 1-cycle latency. NOTE: uses a combinational divider per lane (behavioural; for tape-out
// replace with a shared sequential divider or reciprocal LUT + multiply).
// Structure: pure automatic functions over packed vectors, each wire driven exactly once.
module softmax_q15 #(parameter int N = 8) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              in_valid,
  input  logic [N*16-1:0]   s_flat,     // signed Q8.8
  output logic              out_valid,
  output logic [N*16-1:0]   p_flat      // unsigned Q15
);
  `include "exp2_lut.svh"

  function automatic logic signed [15:0] f_max(input logic [N*16-1:0] s);
    logic signed [15:0] m;
    m = $signed(s[15:0]);
    for (int i = 1; i < N; i++)
      if ($signed(s[16*i +: 16]) > m) m = $signed(s[16*i +: 16]);
    return m;
  endfunction

  // e_i = 2^(((s_i - max) * 369) >> 8, in Q8) as Q15, packed 32 bits per lane
  function automatic logic [N*32-1:0] f_exp(input logic [N*16-1:0] s, input logic signed [15:0] m);
    logic [N*32-1:0]    r;
    logic signed [31:0] d, u, k;
    logic [31:0]        sh, lv;
    r = '0;
    for (int i = 0; i < N; i++) begin
      d  = 32'($signed(s[16*i +: 16])) - 32'(m);
      u  = (d * 32'sd369) >>> 8;
      k  = u >>> 8;
      sh = 32'(-k);
      lv = 32'(exp2_lut(u[7:0]));
      r[32*i +: 32] = (sh >= 32'd16) ? 32'd0 : (lv >> sh);
    end
    return r;
  endfunction

  function automatic logic [31:0] f_sum(input logic [N*32-1:0] e);
    logic [31:0] t;
    t = '0;
    for (int i = 0; i < N; i++) t = t + e[32*i +: 32];
    return t;
  endfunction

  function automatic logic [N*16-1:0] f_div(input logic [N*32-1:0] e, input logic [31:0] sum);
    logic [N*16-1:0] r;
    // verilator lint_off UNUSEDSIGNAL
    logic [63:0]     q;
    // verilator lint_on UNUSEDSIGNAL
    r = '0;
    for (int i = 0; i < N; i++) begin
      q = ({32'd0, e[32*i +: 32]} << 15) / {32'd0, sum};
      r[16*i +: 16] = q[15:0];
    end
    return r;
  endfunction

  wire signed [15:0]  mx     = f_max(s_flat);
  wire [N*32-1:0]     e_flat = f_exp(s_flat, mx);
  wire [31:0]         sum    = f_sum(e_flat);
  wire [N*16-1:0]     p_comb = f_div(e_flat, sum);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin out_valid <= 1'b0; p_flat <= '0; end
    else begin
      out_valid <= in_valid;
      if (in_valid) p_flat <= p_comb;
    end
  end
endmodule
