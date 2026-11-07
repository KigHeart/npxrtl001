// cim_tile: weight-stationary digital compute-in-memory tile, bit-serial over the input (INT8 x INT8 -> INT32).
// Models the DIMC datapath of report Section 3: weights stay in the array; each cycle one input bit-plane gates
// the stored weights and a per-column adder tree reduces them; shift-accumulate over 8 planes (MSB plane subtracts).
// Contract = golden/src/lib.rs `cim`. Latency: 1 load cycle + 8 bit-plane cycles = 9 clock edges from `start` capture to `done`.
module cim_tile #(
  parameter int ROWS = 16,
  parameter int COLS = 8,
  localparam int RW = $clog2(ROWS),
  localparam int CW = $clog2(COLS)
) (
  input  logic                    clk,
  input  logic                    rst_n,
  // weight write port (array programming)
  input  logic                    w_we,
  input  logic [RW-1:0]           w_row,
  input  logic [CW-1:0]           w_col,
  input  logic signed [7:0]       w_data,
  // compute
  input  logic                    start,       // ignored while busy
  input  logic [ROWS*8-1:0]       x_flat,      // x[r] = x_flat[8*r +: 8], signed
  output logic                    busy,
  output logic                    done,        // one-cycle pulse; y_flat valid from this cycle until next start
  output logic [COLS*32-1:0]      y_flat       // y[c] = y_flat[32*c +: 32], signed
);
  logic signed [7:0]  wmem [ROWS*COLS];       // row-major
  logic [ROWS*8-1:0]  x_r;
  logic [2:0]         bit_idx;
  logic signed [31:0] acc [COLS];

  // per-column partial sum of weights selected by the current input bit-plane
  logic signed [15:0] part [COLS];
  always_comb begin
    for (int c = 0; c < COLS; c++) begin
      part[c] = '0;
      for (int r = 0; r < ROWS; r++)
        if (x_r[8*r + int'(bit_idx)]) part[c] = part[c] + 16'(wmem[r*COLS + c]);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0; done <= 1'b0; bit_idx <= '0; x_r <= '0;
      for (int c = 0; c < COLS; c++) acc[c] <= '0;
    end else begin
      done <= 1'b0;
      if (w_we && !busy) wmem[w_row*COLS + int'(w_col)] <= w_data;
      if (!busy) begin
        if (start) begin
          busy <= 1'b1; bit_idx <= '0; x_r <= x_flat;
          for (int c = 0; c < COLS; c++) acc[c] <= '0;
        end
      end else begin
        for (int c = 0; c < COLS; c++) begin
          logic signed [31:0] p32;
          p32 = 32'(part[c]);
          acc[c] <= (bit_idx == 3'd7) ? acc[c] - (p32 <<< 7) : acc[c] + (p32 <<< bit_idx);
        end
        if (bit_idx == 3'd7) begin busy <= 1'b0; done <= 1'b1; end
        bit_idx <= bit_idx + 3'd1;
      end
    end
  end

  always_comb for (int c = 0; c < COLS; c++) y_flat[32*c +: 32] = acc[c];
endmodule
