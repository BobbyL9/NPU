// -----------------------------------------------------------------------------
// SIMD Core, Spatial Adder Tree, and 32-bit Accumulator
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module w4a8_execution_core import w4a8_pkg::*; (
  input  logic clk,
  input  logic rst_n,
  input  logic stall_i,
  
  input  logic valid_i,
  input  logic tlast_i,
  input  weight_payload_t w_payload_i,
  input  logic [SIMD_WIDTH-1:0][ACT_W-1:0] a_payload_i,
  
  output logic [ACC_W-1:0] acc_out_o,
  output logic             acc_valid_o
);

  // ---------------------------------------------------------------------------
  // Interconnect & Unpacker
  // ---------------------------------------------------------------------------
  logic signed [ACT_W-1:0] unpacked_w [SIMD_WIDTH];
  w4a8_weight_unpacker u_unpacker (
    .packed_weights_i (w_payload_i.weights),
    .unpacked_weights_o (unpacked_w)
  );

  // ---------------------------------------------------------------------------
  // SIMD Lane Instantiation
  // ---------------------------------------------------------------------------
  logic signed [PROD_W-1:0] lane_products [SIMD_WIDTH];
  
  genvar i;
  generate
    for (i = 0; i < SIMD_WIDTH; i++) begin : gen_simd_lanes
      w4a8_simd_lane u_lane (
        .clk       (clk),
        .rst_n     (rst_n),
        .stall_i   (stall_i),
        .valid_i   (valid_i),
        .w_ext_i   (unpacked_w[i]),
        .scale_i   (w_payload_i.scale),
        .act_i     (a_payload_i[i]),
        .product_o (lane_products[i])
      );
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Pipeline Control Shift Register (Tracks Valid and TLAST)
  // ---------------------------------------------------------------------------
  logic [2:0] valid_pipe_q, tlast_pipe_q;
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_pipe_q <= '0;
      tlast_pipe_q <= '0;
    end else if (!stall_i) begin
      valid_pipe_q <= {valid_pipe_q[1:0], valid_i};
      tlast_pipe_q <= {tlast_pipe_q[1:0], (valid_i & tlast_i)};
    end
  end

  // ---------------------------------------------------------------------------
  // Stage 3: Spatial Adder Tree & Accumulator
  // ---------------------------------------------------------------------------
  logic signed [PROD_W:0]   sum_lvl1_0, sum_lvl1_1;
  logic signed [PROD_W+1:0] sum_lvl2;
  logic signed [ACC_W-1:0]  acc_q;
  
  assign sum_lvl1_0 = lane_products[0] + lane_products[1];
  assign sum_lvl1_1 = lane_products[2] + lane_products[3];
  assign sum_lvl2   = sum_lvl1_0 + sum_lvl1_1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_q <= '0;
    end else if (!stall_i && valid_pipe_q[1]) begin
      if (tlast_pipe_q[2]) begin // Previous cycle was tlast, reset acc for new vector
        acc_q <= sum_lvl2; 
      end else begin
        acc_q <= acc_q + sum_lvl2;
      end
    end
  end

  // Output assignment
  assign acc_out_o   = acc_q;
  assign acc_valid_o = valid_pipe_q[2] & tlast_pipe_q[2];

endmodule