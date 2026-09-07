// -----------------------------------------------------------------------------
// Top-Level AXI4-Stream Wrapper with Formal Assertions
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module w4a8_top import w4a8_pkg::*; (
  input  logic clk,
  input  logic rst_n,

  // AXI4-Stream Weights Input
  input  logic [23:0] s_axis_w_tdata,
  input  logic        s_axis_w_tvalid,
  output logic        s_axis_w_tready,

  // AXI4-Stream Activations Input
  input  logic [31:0] s_axis_a_tdata,
  input  logic        s_axis_a_tvalid,
  input  logic        s_axis_a_tlast,
  output logic        s_axis_a_tready,

  // AXI4-Stream Result Output
  output logic [31:0] m_axis_res_tdata,
  output logic        m_axis_res_tvalid,
  input  logic        m_axis_res_tready
);

  // Stream Synchronization
  logic joint_valid, stall, core_valid;
  logic [31:0] core_result;
  logic        core_res_valid;

  assign joint_valid = s_axis_w_tvalid & s_axis_a_tvalid;
  assign stall       = core_res_valid & !m_axis_res_tready;
  
  // Ready propagates if we are not stalled
  assign s_axis_w_tready = joint_valid & !stall;
  assign s_axis_a_tready = joint_valid & !stall;

  w4a8_execution_core u_core (
    .clk         (clk),
    .rst_n       (rst_n),
    .stall_i     (stall),
    .valid_i     (joint_valid),
    .tlast_i     (s_axis_a_tlast),
    .w_payload_i (s_axis_w_tdata),
    .a_payload_i (s_axis_a_tdata),
    .acc_out_o   (core_result),
    .acc_valid_o (core_res_valid)
  );

  // Output formatting (Direct wire from core, buffered by pipeline)
  assign m_axis_res_tdata  = core_result;
  assign m_axis_res_tvalid = core_res_valid;

  // ---------------------------------------------------------------------------
  // Concurrent SystemVerilog Assertions (SVA) for Protocol Checking
  // ---------------------------------------------------------------------------
  `ifndef SYNTHESIS
    property p_axi_w_valid_hold;
      @(posedge clk) disable iff (!rst_n)
      (s_axis_w_tvalid && !s_axis_w_tready) |=> (s_axis_w_tvalid && $stable(s_axis_w_tdata));
    endproperty
    assert property (p_axi_w_valid_hold) else $error("AXI-S W: valid dropped/data changed while not ready!");

    property p_axi_a_valid_hold;
      @(posedge clk) disable iff (!rst_n)
      (s_axis_a_tvalid && !s_axis_a_tready) |=> (s_axis_a_tvalid && $stable(s_axis_a_tdata));
    endproperty
    assert property (p_axi_a_valid_hold) else $error("AXI-S A: valid dropped/data changed while not ready!");

    property p_axi_res_valid_hold;
      @(posedge clk) disable iff (!rst_n)
      (m_axis_res_tvalid && !m_axis_res_tready) |=> (m_axis_res_tvalid && $stable(m_axis_res_tdata));
    endproperty
    assert property (p_axi_res_valid_hold) else $error("AXI-S RES: valid dropped/data changed while not ready!");
  `endif

endmodule