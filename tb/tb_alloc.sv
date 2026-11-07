`timescale 1ns/1ps
module tb_alloc;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic req_valid = 0; logic req_ready; logic [2:0] req_op; logic [3:0] req_seq, req_tenant; logic [4:0] req_lp;
  logic resp_valid; logic [2:0] resp_status; logic [7:0] resp_val; logic [6:0] free_count;
  kv_page_alloc dut(.*);
  string dir; integer fd, n, errs, op, seq, t, lp, est, eval_, efree, rc;
  initial begin
    if (!$value$plusargs("vec=%s", dir)) dir = "sim/vec";
    fd = $fopen({dir, "/alloc.txt"}, "r");
    if (fd == 0) begin $display("FAIL: cannot open vectors"); $finish; end
    n = 0; errs = 0;
    repeat (3) @(negedge clk); rst_n = 1; @(negedge clk);
    while ($fscanf(fd, "%d %d %d %d %d %d %d", op, seq, t, lp, est, eval_, efree) == 7) begin
      if (!req_ready) begin errs++; $display("op %0d: req_ready low before issue", n); end
      req_valid = 1; req_op = op[2:0]; req_seq = seq[3:0]; req_tenant = t[3:0]; req_lp = lp[4:0];
      @(negedge clk); req_valid = 0;
      rc = 0;
      while (!resp_valid && rc < 40) begin @(negedge clk); rc++; end
      if (!resp_valid) begin errs++; $display("op %0d: no response", n); end
      else if (resp_status !== est[2:0] || resp_val !== eval_[7:0] || free_count !== efree[6:0]) begin
        errs++;
        if (errs <= 8) $display("MISMATCH op#%0d (op=%0d seq=%0d ten=%0d lp=%0d): got st=%0d val=%0d free=%0d, want st=%0d val=%0d free=%0d",
          n, op, seq, t, lp, resp_status, resp_val, free_count, est, eval_, efree);
      end
      n++;
    end
    $display("kv_page_alloc: %0d ops, %0d mismatches -> %s", n, errs, (errs == 0 && n > 0) ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #50_000_000; $display("kv_page_alloc: TIMEOUT"); $finish; end
endmodule
