`timescale 1ns/1ps
module tb_softmax;
  localparam int N = 8;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic in_valid = 0; logic [N*16-1:0] s_flat; logic out_valid; logic [N*16-1:0] p_flat;
  softmax_q15 #(.N(N)) dut(.*);
  string dir; integer fd, n, errs, rc; integer sv [N]; integer pv [N];
  initial begin
    if (!$value$plusargs("vec=%s", dir)) dir = "sim/vec";
    fd = $fopen({dir, "/softmax.txt"}, "r");
    if (fd == 0) begin $display("FAIL: cannot open vectors"); $finish; end
    n = 0; errs = 0;
    repeat (3) @(negedge clk); rst_n = 1; @(negedge clk);
    while (!$feof(fd)) begin
      rc = 0;
      for (int i = 0; i < N; i++) rc += $fscanf(fd, "%d", sv[i]);
      for (int i = 0; i < N; i++) rc += $fscanf(fd, "%d", pv[i]);
      if (rc == 2*N) begin
        for (int i = 0; i < N; i++) s_flat[16*i +: 16] = 16'(sv[i]);
        in_valid = 1; @(negedge clk); in_valid = 0;
        if (!out_valid) begin errs++; $display("test %0d: out_valid low", n); end
        for (int i = 0; i < N; i++) begin
          if (p_flat[16*i +: 16] !== 16'(pv[i])) begin
            errs++;
            if (errs <= 8) $display("MISMATCH test %0d lane %0d: got %0d want %0d", n, i, p_flat[16*i +: 16], pv[i]);
          end
        end
        n++;
        @(negedge clk);
      end
    end
    $display("softmax_q15: %0d vectors, %0d mismatches -> %s", n, errs, (errs == 0 && n > 0) ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #50_000_000; $display("softmax_q15: TIMEOUT"); $finish; end
endmodule
