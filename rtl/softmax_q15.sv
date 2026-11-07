// softmax_q15: 8-lane fixed-point softmax for the digital precision island (report Sections 2.1(4), 4.2).
// Q8.8 scores in, Q15 probabilities out. Contract = golden/src/lib.rs `softmax::q15`.
// Registered output, 1-cycle latency. NOTE: uses a combinational divider per lane (behavioural; for tape-out
// replace with a shared sequential divider or reciprocal LUT + multiply).
module softmax_q15 #(parameter int N = 8) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              in_valid,
  input  logic [N*16-1:0]   s_flat,     // signed Q8.8
  output logic              out_valid,
  output logic [N*16-1:0]   p_flat      // unsigned Q15
);
  `include "exp2_lut.svh"

  logic signed [15:0] s [N];
  logic signed [15:0] mx;
  logic [31:0]        e [N];
  logic [31:0]        sum;
  logic [15:0]        p [N];

  always_comb begin
    for (int i = 0; i < N; i++) s[i] = s_flat[16*i +: 16];
    mx = s[0];
    for (int i = 1; i < N; i++) if (s[i] > mx) mx = s[i];
    sum = '0;
    for (int i = 0; i < N; i++) begin
      logic signed [31:0] d, u, k;
      logic [7:0]         f;
      logic [31:0]        sh;
      d = 32'(s[i]) - 32'(mx);
      u = (d * 32'sd369) >>> 8;
      k = u >>> 8;
      f = u[7:0];
      sh = 32'(-k);
      e[i] = (sh >= 32'd16) ? 32'd0 : (32'(exp2_lut(f)) >> sh);
      sum  = sum + e[i];
    end
    for (int i = 0; i < N; i++) p[i] = 16'((({32'd0, e[i]} << 15)) / {32'd0, sum});
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin out_valid <= 1'b0; p_flat <= '0; end
    else begin
      out_valid <= in_valid;
      if (in_valid) for (int i = 0; i < N; i++) p_flat[16*i +: 16] <= p[i];
    end
  end
endmodule
