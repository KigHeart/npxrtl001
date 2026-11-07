// cmd_decode: validates and routes the 128-bit engine command descriptor (report Section 6.2).
// Contract = golden/src/lib.rs `decode`. Error priority is fixed: reserved > resource > precision > dim > align > kv > tenant.
// Layout: [7:0] kernel_id [9:8] resource(0 CiM,1 photonic,2 digital) [13:10] precision [17:14] tenant
//         [21:18] kv_seq [22] kv_valid [23] kv_write [31:24] rsv [63:32] tensor_addr [79:64] dim_m [95:80] dim_n
//         [103:96] fence_id [111:104] deadline_q [115:112] priority [127:116] rsv
// Status: 0 OK, 1 RESERVED, 2 RESOURCE, 3 PRECISION, 4 DIM, 5 ALIGN, 6 KV, 7 TENANT.
// Registered outputs, 1-cycle latency. Security invariant (report 7.3): nothing dispatches unless status == 0.
module cmd_decode (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         in_valid,
  input  logic [127:0] desc,
  input  logic         cfg_photonic_en,
  input  logic [15:0]  kv_open,        // from allocator view: sequence open
  input  logic [63:0]  kv_tenants,     // 4 bits per sequence
  output logic         out_valid,
  output logic [2:0]   out_status,
  output logic [2:0]   out_dispatch,   // one-hot {digital, photonic, cim}; zero unless status == 0
  output logic [127:0] out_desc
);
  wire [1:0]  res     = desc[9:8];
  wire [3:0]  prec    = desc[13:10];
  wire [3:0]  tenant  = desc[17:14];
  wire [3:0]  kvseq   = desc[21:18];
  wire        kvvalid = desc[22];
  wire [4:0]  addr_lo = desc[36:32];   // 32-byte alignment check; upper address bits are routed via out_desc
  wire [15:0] dm      = desc[79:64];
  wire [15:0] dn      = desc[95:80];

  logic [2:0] st;
  logic       prec_ok;
  always_comb begin
    case (res)
      2'd0:    prec_ok = (prec == 4'd0) || (prec == 4'd1) || (prec == 4'd3);
      2'd1:    prec_ok = (prec == 4'd0) || (prec == 4'd2);
      default: prec_ok = (prec == 4'd0) || (prec == 4'd2) || (prec == 4'd3);
    endcase
    if (desc[31:24] != 8'd0 || desc[127:116] != 12'd0)       st = 3'd1;
    else if (res == 2'd3 || (res == 2'd1 && !cfg_photonic_en)) st = 3'd2;
    else if (!prec_ok)                                       st = 3'd3;
    else if (dm == 16'd0 || dn == 16'd0)                     st = 3'd4;
    else if (addr_lo != 5'd0)                              st = 3'd5;
    else if (kvvalid && !kv_open[kvseq])                     st = 3'd6;
    else if (kvvalid && kv_tenants[4*kvseq +: 4] != tenant)  st = 3'd7;
    else                                                     st = 3'd0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin out_valid <= 1'b0; out_status <= '0; out_dispatch <= '0; out_desc <= '0; end
    else begin
      out_valid <= in_valid;
      if (in_valid) begin
        out_status   <= st;
        out_desc     <= desc;
        out_dispatch <= (st == 3'd0) ? (3'b001 << res) : 3'b000;
      end
    end
  end
endmodule
