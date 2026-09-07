`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/03/2026 11:11:33 PM
// Design Name: 
// Module Name: w4a8_simd_lane
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
// -----------------------------------------------------------------------------
// Single Lane Data Path: Ext_W * Scale -> Pipelined -> Intermediate * Act
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module w4a8_simd_lane import w4a8_pkg::*; (
  input  logic clk,
  input  logic rst_n,
  input  logic stall_i,
  input  logic valid_i,
  
  input  logic signed [ACT_W-1:0]   w_ext_i,
  input  logic signed [SCALE_W-1:0] scale_i,
  input  logic signed [ACT_W-1:0]   act_i,
  
  output logic signed [PROD_W-1:0]  product_o
);

  // Stage 1 Registers
  logic signed [INT_W-1:0] stg1_intermediate_q;
  logic signed [ACT_W-1:0] stg1_act_q;
  
  // Operand Isolation / Clock Gating condition
  logic clk_en;
  assign clk_en = valid_i && !stall_i;

  // Pipeline Stage 1: Dequantization ---------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stg1_intermediate_q <= '0;
      stg1_act_q          <= '0;
    end else if (clk_en) begin
      stg1_intermediate_q <= w_ext_i * scale_i;
      
      // Zero-activation operand isolation for power savings
      if (act_i == '0) stg1_act_q <= '0;
      else             stg1_act_q <= act_i;
    end
  end
// --------------------------------------------------------------------------  

  // Pipeline Stage 2: Product ----------------------------------------------
  logic signed [PROD_W-1:0] stg2_product_d;
  assign stg2_product_d = stg1_intermediate_q * stg1_act_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      product_o <= '0;
    end else if (!stall_i) begin
      product_o <= stg2_product_d;
    end
  end
// --------------------------------------------------------------------------
endmodule
