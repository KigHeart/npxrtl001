`timescale 1ns/1ps
module tb_decode;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic in_valid = 0; logic [127:0] desc; logic cfg_photonic_en; logic [15:0] kv_open; logic [63:0] kv_tenants;
  logic out_valid; logic [2:0] out_status, out_dispatch; logic [127:0] out_desc;
  cmd_decode dut(.*);
  string dir; integer fd, n, errs, pen, est, edisp, rc; logic [127:0] d; logic [15:0] ko; logic [63:0] kt;
  initial begin
    if (!$value$plusargs("vec=%s", dir)) dir = "sim/vec";
    fd = $fopen({dir, "/decode.txt"}, "r");
    if (fd == 0) begin $display("FAIL: cannot open vectors"); $finish; end
    n = 0; errs = 0;
    repeat (3) @(negedge clk); rst_n = 1; @(negedge clk);
    while ($fscanf(fd, "%h %d %h %h %d %d", d, pen, ko, kt, est, edisp) == 6) begin
      desc = d; cfg_photonic_en = pen[0]; kv_open = ko; kv_tenants = kt; in_valid = 1;
      @(negedge clk); in_valid = 0;
      if (!out_valid || out_status !== est[2:0] || out_dispatch !== edisp[2:0] || (est == 0 && out_desc !== d)) begin
        errs++;
        if (errs <= 8) $display("MISMATCH vec %0d: desc=%h got st=%0d disp=%0d want st=%0d disp=%0d", n, d, out_status, out_dispatch, est, edisp);
      end
      // invariant: no dispatch on error
      if (out_status !== 3'd0 && out_dispatch !== 3'd0) begin errs++; $display("INVARIANT VIOLATION vec %0d: dispatch on error", n); end
      n++;
    end
    $display("cmd_decode: %0d descriptors, %0d mismatches -> %s", n, errs, (errs == 0 && n > 0) ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #50_000_000; $display("cmd_decode: TIMEOUT"); $finish; end
endmodule
