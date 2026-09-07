`timescale 1ns/1ps
module npu_controller #(
  parameter int ADDR_W = 10
)(
  input  logic clk,
  input  logic rst_n,

  // Control / Status
  input  logic start_i,
  input  logic [15:0] cfg_m_rows_i,   // Number of output features (Rows of Matrix)
  input  logic [15:0] cfg_k_iters_i,  // Vector length / 4 (SIMD width)
  output logic done_o,
  
  // BRAM Interfaces (Read-Only for Fetch)
  output logic              bram_w_en_o,
  output logic [ADDR_W-1:0] bram_w_addr_o,
  input  logic [31:0]       bram_w_data_i, // [23:0] used
  
  output logic              bram_a_en_o,
  output logic [ADDR_W-1:0] bram_a_addr_o,
  input  logic [31:0]       bram_a_data_i,

  // BRAM Interface (Write-Only for Writeback)
  output logic              bram_out_en_o,
  output logic              bram_out_we_o,
  output logic [ADDR_W-1:0] bram_out_addr_o,
  output logic [31:0]       bram_out_data_o,

  // MAC AXI-Stream Interface
  output logic [23:0] m_axis_w_tdata,
  output logic        m_axis_w_tvalid,
  input  logic        m_axis_w_tready,

  output logic [31:0] m_axis_a_tdata,
  output logic        m_axis_a_tvalid,
  output logic        m_axis_a_tlast,
  input  logic        m_axis_a_tready,

  input  logic [31:0] s_axis_res_tdata,
  input  logic        s_axis_res_tvalid,
  output logic        s_axis_res_tready
);

  // ===========================================================================
  // FETCH ENGINE (BRAM to MAC)
  // ===========================================================================
  typedef enum logic [1:0] {IDLE, FETCH} fetch_state_t;
  fetch_state_t f_state_q, f_state_d;

  logic [15:0] cnt_m_q, cnt_m_d; // Row counter
  logic [15:0] cnt_k_q, cnt_k_d; // Column iter counter
  
  // BRAM Read Latency Pipeline (1 Cycle)
  logic bram_read_valid_q, bram_read_tlast_q;
  
  always_comb begin
    f_state_d = f_state_q;
    cnt_m_d   = cnt_m_q;
    cnt_k_d   = cnt_k_q;
    
    bram_w_en_o   = 1'b0;
    bram_a_en_o   = 1'b0;
    bram_w_addr_o = '0;
    bram_a_addr_o = '0;

    case (f_state_q)
      IDLE: begin
        if (start_i) begin
          f_state_d = FETCH;
          cnt_m_d   = '0;
          cnt_k_d   = '0;
        end
      end
      
      FETCH: begin
        // Only fetch if MAC is ready for the previous fetch to enter stream
        if (m_axis_w_tready && m_axis_a_tready) begin
          bram_w_en_o   = 1'b1;
          bram_a_en_o   = 1'b1;
          // Weight layout: contiguous linear memory. Address = Row * K_iters + Col
          bram_w_addr_o = (cnt_m_q * cfg_k_iters_i) + cnt_k_q; 
          // Activation layout: reused for every row. Address = Col
          bram_a_addr_o = cnt_k_q;
          
          if (cnt_k_q == (cfg_k_iters_i - 1)) begin
            cnt_k_d = '0;
            if (cnt_m_q == (cfg_m_rows_i - 1)) begin
              f_state_d = IDLE; // Finished all rows
            end else begin
              cnt_m_d = cnt_m_q + 1; // Next row
            end
          end else begin
            cnt_k_d = cnt_k_q + 1; // iterate through column
          end
        end
      end
    endcase
  end

  // BRAM -> AXI-Stream Pipeline Registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      f_state_q         <= IDLE;
      cnt_m_q           <= '0;
      cnt_k_q           <= '0;
      bram_read_valid_q <= 1'b0;
      bram_read_tlast_q <= 1'b0;
    end else begin
      f_state_q         <= f_state_d;
      cnt_m_q           <= cnt_m_d;
      cnt_k_q           <= cnt_k_d;
      
      // Advance pipeline if MAC is consuming data
      if (m_axis_w_tready && m_axis_a_tready) begin
        bram_read_valid_q <= bram_w_en_o;
        bram_read_tlast_q <= (cnt_k_q == (cfg_k_iters_i - 1)) && bram_w_en_o;
      end
    end
  end

  // Drive AXI-S ports directly from BRAM outputs (aligned with valid pipeline)
  assign m_axis_w_tdata  = bram_w_data_i[23:0];
  assign m_axis_w_tvalid = bram_read_valid_q;
  
  assign m_axis_a_tdata  = bram_a_data_i;
  assign m_axis_a_tvalid = bram_read_valid_q;
  assign m_axis_a_tlast  = bram_read_tlast_q;


  // ===========================================================================
  // WRITEBACK ENGINE (MAC to Result BRAM)
  // ===========================================================================
  logic [15:0] wb_cnt_m_q; // Tracks which row result we are writing
  
  assign s_axis_res_tready = 1'b1; // Always ready to sink results into BRAM
  
  assign bram_out_en_o   = s_axis_res_tvalid;
  assign bram_out_we_o   = s_axis_res_tvalid;
  assign bram_out_addr_o = wb_cnt_m_q;
  assign bram_out_data_o = s_axis_res_tdata;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wb_cnt_m_q <= '0;
      done_o     <= 1'b0;
    end else begin
      done_o <= 1'b0; // Default clear
      
      if (start_i) wb_cnt_m_q <= '0; // Reset count on new operation
      
      if (s_axis_res_tvalid) begin
      // (below) writeback index matches total row count, we have saved every row's computed output
        if (wb_cnt_m_q == (cfg_m_rows_i - 1)) begin
          done_o <= 1'b1; // Trigger Done interrupt
        end else begin
          wb_cnt_m_q <= wb_cnt_m_q + 1; // havent saved every row, go to next row
        end
      end
    end
  end

endmodule