module axi4_slave (
  input  logic        clk,
  input  logic        rstn,

  input  logic [3:0]  aw_id,
  input  logic [31:0] aw_addr,
  input  logic [7:0]  aw_len,
  input  logic [2:0]  aw_size,
  input  logic [1:0]  aw_burst,
  input  logic        aw_valid,
  output logic        aw_ready,

  input  logic [31:0] w_data,
  input  logic [3:0]  w_strb,
  input  logic        w_last,
  input  logic        w_valid,
  output logic        w_ready,

  output logic [3:0]  b_id,
  output logic [1:0]  b_resp,
  output logic        b_valid,
  input  logic        b_ready,

  input  logic [3:0]  ar_id,
  input  logic [31:0] ar_addr,
  input  logic [7:0]  ar_len,
  input  logic [2:0]  ar_size,
  input  logic [1:0]  ar_burst,
  input  logic        ar_valid,
  output logic        ar_ready,

  output logic [3:0]  r_id,
  output logic [31:0] r_data,
  output logic [1:0]  r_resp,
  output logic        r_last,
  output logic        r_valid,
  input  logic        r_ready
);

  logic [31:0] mem [15:0];
  
// WRITE FSM
  
  typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} wstate_e;
  wstate_e wstate;

  logic [31:0] waddr_ptr;
  logic [7:0]  wlen_latch;
  logic [3:0]  wid_latch;

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      wstate   <= W_IDLE;
      aw_ready <= 0;
      w_ready  <= 0;
      b_valid  <= 0;
      b_resp   <= 2'b00;
    end
    else begin
      case (wstate)

        W_IDLE: begin
          b_valid  <= 0;
          aw_ready <= 1;
          if (aw_valid && aw_ready) begin
            waddr_ptr  <= aw_addr;
            wlen_latch <= aw_len;
            wid_latch  <= aw_id;
            aw_ready   <= 0;
            wstate     <= W_DATA;
          end
        end

        W_DATA: begin
          w_ready <= 1;
          if (w_valid && w_ready) begin
            mem[waddr_ptr[5:2]] <= w_data;
            waddr_ptr           <= waddr_ptr + 4;
            w_ready              <= 0;

            if (w_last)
              wstate <= W_RESP;
          end
        end

        W_RESP: begin
          b_id    <= wid_latch;
          b_resp  <= 2'b00;
          b_valid <= 1;
          if (b_valid && b_ready) begin
            b_valid <= 0;
            wstate  <= W_IDLE;
          end
        end

        default: wstate <= W_IDLE;
      endcase
    end
  end

  // READ FSM
  
  typedef enum logic [1:0] {R_IDLE, R_DATA} rstate_e;
  rstate_e rstate;

  logic [31:0] raddr_ptr;
  logic [7:0]  rbeat_cnt;
  logic [7:0]  rlen_latch;
  logic [3:0]  rid_latch;

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      rstate    <= R_IDLE;
      ar_ready  <= 0;
      r_valid   <= 0;
      r_last    <= 0;
      r_resp    <= 2'b00;
      r_data    <= 32'h0;
      rbeat_cnt <= 0;
    end
    else begin
      case (rstate)

        R_IDLE: begin
          r_valid  <= 0;
          ar_ready <= 1;
          if (ar_valid && ar_ready) begin
            raddr_ptr  <= ar_addr;
            rlen_latch <= ar_len;
            rid_latch  <= ar_id;
            rbeat_cnt  <= 0;
            ar_ready   <= 0;
            rstate     <= R_DATA;
          end
        end

        R_DATA: begin
          r_id    <= rid_latch;
          r_data  <= mem[raddr_ptr[5:2]];
          r_resp  <= 2'b00;
          r_valid <= 1;
          r_last  <= (rbeat_cnt == rlen_latch);

          if (r_valid && r_ready) begin
            if (rbeat_cnt == rlen_latch) begin
              r_valid <= 0;
              rstate  <= R_IDLE;
            end
            else begin
              raddr_ptr <= raddr_ptr + 4;
              rbeat_cnt <= rbeat_cnt + 1;
            end
          end
        end

        default: rstate <= R_IDLE;
      endcase
    end
  end

endmodule
