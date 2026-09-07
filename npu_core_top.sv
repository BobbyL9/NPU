`timescale 1ns/1ps
module npu_core_top #(
  parameter int ADDR_W = 10
)(
  input  logic clk,
  input  logic rst_n,

  // Simple Host Config Bus (Can be adapted to AXI-Lite)
  input  logic        host_start,
  input  logic [15:0] host_cfg_m_rows,
  input  logic [15:0] host_cfg_k_iters,
  output logic        npu_done_irq,

  // Host Port: Weight BRAM
  input  logic              host_w_en,
  input  logic              host_w_we,
  input  logic [ADDR_W-1:0] host_w_addr,
  input  logic [31:0]       host_w_din,

  // Host Port: Activation BRAM
  input  logic              host_a_en,
  input  logic              host_a_we,
  input  logic [ADDR_W-1:0] host_a_addr,
  input  logic [31:0]       host_a_din,

  // Host Port: Result BRAM
  input  logic              host_out_en,
  input  logic [ADDR_W-1:0] host_out_addr,
  output logic [31:0]       host_out_dout
);

  // Internal Signals
  logic              bram_w_en, bram_a_en, bram_out_en, bram_out_we;
  logic [ADDR_W-1:0] bram_w_addr, bram_a_addr, bram_out_addr;
  logic [31:0]       bram_w_dout, bram_a_dout, bram_out_din;
  
  logic [23:0] w_tdata; logic w_tvalid, w_tready;
  logic [31:0] a_tdata; logic a_tvalid, a_tlast, a_tready;
  logic [31:0] res_tdata; logic res_tvalid, res_tready;

  // ---------------------------------------------------------------------------
  // 1. Memory Subsystem
  // ---------------------------------------------------------------------------
  npu_bram_dp #(.ADDR_WIDTH(ADDR_W)) u_bram_weights (
    .clk(clk),
    .host_en(host_w_en), .host_we(host_w_we), .host_addr(host_w_addr), .host_din(host_w_din), .host_dout(),
    .npu_en(bram_w_en),  .npu_we(1'b0),       .npu_addr(bram_w_addr),  .npu_din('0),          .npu_dout(bram_w_dout)
  );

  npu_bram_dp #(.ADDR_WIDTH(ADDR_W)) u_bram_acts (
    .clk(clk),
    .host_en(host_a_en), .host_we(host_a_we), .host_addr(host_a_addr), .host_din(host_a_din), .host_dout(),
    .npu_en(bram_a_en),  .npu_we(1'b0),       .npu_addr(bram_a_addr),  .npu_din('0),          .npu_dout(bram_a_dout)
  );

  npu_bram_dp #(.ADDR_WIDTH(ADDR_W)) u_bram_out (
    .clk(clk),
    .host_en(host_out_en), .host_we(1'b0),      .host_addr(host_out_addr), .host_din('0),         .host_dout(host_out_dout),
    .npu_en(bram_out_en),  .npu_we(bram_out_we),.npu_addr(bram_out_addr),  .npu_din(bram_out_din),.npu_dout()
  );

  // ---------------------------------------------------------------------------
  // 2. Control Subsystem
  // ---------------------------------------------------------------------------
  npu_controller #(.ADDR_W(ADDR_W)) u_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(host_start),
    .cfg_m_rows_i(host_cfg_m_rows),
    .cfg_k_iters_i(host_cfg_k_iters),
    .done_o(npu_done_irq),
    
    // Memory interfaces
    .bram_w_en_o(bram_w_en), .bram_w_addr_o(bram_w_addr), .bram_w_data_i(bram_w_dout),
    .bram_a_en_o(bram_a_en), .bram_a_addr_o(bram_a_addr), .bram_a_data_i(bram_a_dout),
    .bram_out_en_o(bram_out_en), .bram_out_we_o(bram_out_we), .bram_out_addr_o(bram_out_addr), .bram_out_data_o(bram_out_din),
    
    // AXI Stream to MAC
    .m_axis_w_tdata(w_tdata), .m_axis_w_tvalid(w_tvalid), .m_axis_w_tready(w_tready),
    .m_axis_a_tdata(a_tdata), .m_axis_a_tvalid(a_tvalid), .m_axis_a_tlast(a_tlast), .m_axis_a_tready(a_tready),
    .s_axis_res_tdata(res_tdata), .s_axis_res_tvalid(res_tvalid), .s_axis_res_tready(res_tready)
  );

  // ---------------------------------------------------------------------------
  // 3. Compute Subsystem (Your previous module)
  // ---------------------------------------------------------------------------
  w4a8_top u_mac_core (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_w_tdata(w_tdata),   .s_axis_w_tvalid(w_tvalid),   .s_axis_w_tready(w_tready),
    .s_axis_a_tdata(a_tdata),   .s_axis_a_tvalid(a_tvalid),   .s_axis_a_tlast(a_tlast), .s_axis_a_tready(a_tready),
    .m_axis_res_tdata(res_tdata), .m_axis_res_tvalid(res_tvalid), .m_axis_res_tready(res_tready)
  );

endmodule