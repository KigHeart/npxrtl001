`timescale 1ns/1ps
module tb_cim;
  localparam int ROWS = 16, COLS = 8;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic w_we = 0; logic [3:0] w_row; logic [2:0] w_col; logic signed [7:0] w_data;
  logic start = 0; logic [ROWS*8-1:0] x_flat; logic busy, done; logic [COLS*32-1:0] y_flat;
  cim_tile #(.ROWS(ROWS), .COLS(COLS)) dut(.*);
  logic [ROWS*8-1:0] xtmp;
  string dir; integer fd, n, errs, v, rc, r, c;
  integer wv [ROWS*COLS]; integer xv [ROWS]; integer yv [COLS];
  initial begin
    if (!$value$plusargs("vec=%s", dir)) dir = "sim/vec";
    fd = $fopen({dir, "/cim.txt"}, "r");
    if (fd == 0) begin $display("FAIL: cannot open vectors"); $finish; end
    n = 0; errs = 0;
    repeat (3) @(negedge clk); rst_n = 1; @(negedge clk);
    while (!$feof(fd)) begin
      rc = 0;
      for (int i = 0; i < ROWS*COLS; i++) rc += $fscanf(fd, "%d", wv[i]);
      for (int i = 0; i < ROWS; i++)      rc += $fscanf(fd, "%d", xv[i]);
      for (int i = 0; i < COLS; i++)      rc += $fscanf(fd, "%d", yv[i]);
      if (rc == ROWS*COLS + ROWS + COLS) begin
        for (r = 0; r < ROWS; r++) for (c = 0; c < COLS; c++) begin
          w_we = 1; w_row = r[3:0]; w_col = c[2:0]; w_data = 8'(wv[r*COLS + c]); @(negedge clk);
        end
        w_we = 0;
        xtmp = '0; for (int i = 0; i < ROWS; i++) xtmp[8*i +: 8] = 8'(xv[i]);
        x_flat = xtmp;   // whole-vector assign (see tb_softmax.sv note on Verilator 5.020)
        start = 1; @(negedge clk); start = 0;
        v = 0;
        while (!done && v < 30) begin @(negedge clk); v++; end
        if (!done) begin errs++; $display("test %0d: done never asserted", n); end
        else begin
          for (int c2 = 0; c2 < COLS; c2++) begin
            if ($signed(y_flat[32*c2 +: 32]) !== yv[c2]) begin
              errs++;
              if (errs <= 8) $display("MISMATCH test %0d col %0d: got %0d want %0d", n, c2, $signed(y_flat[32*c2 +: 32]), yv[c2]);
            end
          end
          if (v != 8) begin errs++; $display("test %0d: latency off: waited %0d, expected 8 (1 load + 8 compute edges)", n, v); end
        end
        n++;
        @(negedge clk);
      end
    end
    $display("cim_tile: %0d tests, %0d mismatches -> %s", n, errs, (errs == 0 && n > 0) ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #50_000_000; $display("cim_tile: TIMEOUT"); $finish; end
endmodule
