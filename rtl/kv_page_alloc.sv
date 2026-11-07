// kv_page_alloc: paged KV-cache allocator with tenant ownership (report Section 5.3).
// Contract = golden/src/lib.rs `alloc`. One request at a time; FREE walks the page table (1 page/cycle).
// Status: 0 OK, 1 NOSEQ, 2 TENANT, 3 FULLSEQ, 4 NOMEM, 5 RANGE, 6 EXISTS, 7 BADOP.
module kv_page_alloc #(
  parameter int NSEQ   = 16,
  parameter int MAXLP  = 16,   // logical pages per sequence; must be a power of two
  parameter int NPAGES = 64,
  localparam int SW = $clog2(NSEQ),
  localparam int LW = $clog2(MAXLP),
  localparam int PW = $clog2(NPAGES),
  localparam int TW = 4
) (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          req_valid,
  output logic          req_ready,
  input  logic [2:0]    req_op,        // 0 OPEN, 1 ALLOC, 2 LOOKUP, 3 FREE
  input  logic [SW-1:0] req_seq,
  input  logic [TW-1:0] req_tenant,
  input  logic [LW:0]   req_lp,        // logical page (LOOKUP); LW+1 bits so out-of-range is representable
  output logic          resp_valid,    // one-cycle pulse
  output logic [2:0]    resp_status,
  output logic [7:0]    resp_val,
  output logic [PW:0]   free_count
);
  localparam logic [2:0] OP_OPEN = 3'd0, OP_ALLOC = 3'd1, OP_LOOKUP = 3'd2, OP_FREE = 3'd3;
  localparam logic [2:0] ST_OK = 3'd0, ST_NOSEQ = 3'd1, ST_TENANT = 3'd2, ST_FULLSEQ = 3'd3,
                         ST_NOMEM = 3'd4, ST_RANGE = 3'd5, ST_EXISTS = 3'd6, ST_BADOP = 3'd7;

  logic [NSEQ-1:0]   seq_open;
  logic [TW-1:0]     seq_tenant [NSEQ];
  logic [LW:0]       seq_len    [NSEQ];
  logic [PW-1:0]     pt         [NSEQ*MAXLP];
  logic [NPAGES-1:0] free_map;

  typedef enum logic {S_IDLE, S_FREEING} state_t;
  state_t state;
  logic [SW-1:0] f_seq;
  logic [LW:0]   f_idx, f_cnt;

  assign req_ready = (state == S_IDLE);

  // lowest free page (descending loop: last assignment, i.e. lowest index, wins)
  logic          any_free;
  logic [PW-1:0] first_free;
  always_comb begin
    any_free   = 1'b0;
    first_free = '0;
    for (int i = NPAGES-1; i >= 0; i--)
      if (free_map[i]) begin any_free = 1'b1; first_free = PW'(i); end
  end

  always_comb begin
    free_count = '0;
    for (int i = 0; i < NPAGES; i++) free_count = free_count + (PW+1)'(free_map[i]);
  end

  wire open_q   = seq_open[req_seq];
  wire tenant_ok = (seq_tenant[req_seq] == req_tenant);
  wire [LW:0] len_q = seq_len[req_seq];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      seq_open    <= '0;
      free_map    <= '1;
      state       <= S_IDLE;
      resp_valid  <= 1'b0;
      resp_status <= ST_OK;
      resp_val    <= '0;
      f_seq <= '0; f_idx <= '0; f_cnt <= '0;
      for (int i = 0; i < NSEQ; i++) begin seq_tenant[i] <= '0; seq_len[i] <= '0; end
    end else begin
      resp_valid <= 1'b0;
      case (state)
        S_IDLE: if (req_valid) begin
          resp_valid  <= 1'b1;
          resp_status <= ST_OK;
          resp_val    <= '0;
          unique case (req_op)
            OP_OPEN: begin
              if (open_q) resp_status <= ST_EXISTS;
              else begin
                seq_open[req_seq]   <= 1'b1;
                seq_tenant[req_seq] <= req_tenant;
                seq_len[req_seq]    <= '0;
              end
            end
            OP_ALLOC: begin
              if (!open_q)                 resp_status <= ST_NOSEQ;
              else if (!tenant_ok)         resp_status <= ST_TENANT;
              else if (len_q == (LW+1)'(MAXLP)) resp_status <= ST_FULLSEQ;
              else if (!any_free)          resp_status <= ST_NOMEM;
              else begin
                free_map[first_free]            <= 1'b0;
                pt[{req_seq, len_q[LW-1:0]}]    <= first_free;
                seq_len[req_seq]                <= len_q + 1'b1;
                resp_val                        <= 8'(first_free);
              end
            end
            OP_LOOKUP: begin
              if (!open_q)                 resp_status <= ST_NOSEQ;
              else if (!tenant_ok)         resp_status <= ST_TENANT;
              else if (req_lp >= len_q)    resp_status <= ST_RANGE;
              else                         resp_val    <= 8'(pt[{req_seq, req_lp[LW-1:0]}]);
            end
            OP_FREE: begin
              if (!open_q)                 resp_status <= ST_NOSEQ;
              else if (!tenant_ok)         resp_status <= ST_TENANT;
              else if (len_q == '0) begin
                seq_open[req_seq] <= 1'b0;
              end else begin
                // defer response until the walk completes
                resp_valid <= 1'b0;
                state <= S_FREEING;
                f_seq <= req_seq; f_idx <= '0; f_cnt <= len_q;
              end
            end
            default: resp_status <= ST_BADOP;
          endcase
        end
        S_FREEING: begin
          free_map[pt[{f_seq, f_idx[LW-1:0]}]] <= 1'b1;
          if (f_idx + 1'b1 == f_cnt) begin
            seq_open[f_seq] <= 1'b0;
            seq_len[f_seq]  <= '0;
            resp_valid      <= 1'b1;
            resp_status     <= ST_OK;
            resp_val        <= 8'(f_cnt);
            state           <= S_IDLE;
          end else f_idx <= f_idx + 1'b1;
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
