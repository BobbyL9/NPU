`timescale 1ns/1ps
module npu_bram_dp #(
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 10 // 1024 entries
)(
  input  logic clk,
  
  // Port A: Host Side
  input  logic                  host_en,
  input  logic                  host_we,
  input  logic [ADDR_WIDTH-1:0] host_addr,
  input  logic [DATA_WIDTH-1:0] host_din,
  output logic [DATA_WIDTH-1:0] host_dout,

  // Port B: NPU Side
  input  logic                  npu_en,
  input  logic                  npu_we,
  input  logic [ADDR_WIDTH-1:0] npu_addr,
  input  logic [DATA_WIDTH-1:0] npu_din,
  output logic [DATA_WIDTH-1:0] npu_dout
);

  // Core memory array
  logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

  // Port A
  always_ff @(posedge clk) begin
    if (host_en) begin
      if (host_we) mem[host_addr] <= host_din;
      host_dout <= mem[host_addr];
    end
  end

  // Port B
  always_ff @(posedge clk) begin
    if (npu_en) begin
      if (npu_we) mem[npu_addr] <= npu_din;
      npu_dout <= mem[npu_addr];
    end
  end

endmodule