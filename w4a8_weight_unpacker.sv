// -----------------------------------------------------------------------------
// Performs combinatorial sign-extension of packed INT4 weights to INT8
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module w4a8_weight_unpacker import w4a8_pkg::*; (
  input  logic [SIMD_WIDTH-1:0][WEIGHT_W-1:0] packed_weights_i,
  output logic signed [ACT_W-1:0]             unpacked_weights_o [SIMD_WIDTH]
);

  always_comb begin
    for (int i = 0; i < SIMD_WIDTH; i++) begin
      // Sign extend 4-bit to 8-bit manually for strict hardware mapping
      unpacked_weights_o[i] = { { (ACT_W - WEIGHT_W) {packed_weights_i[i][WEIGHT_W-1]} }, 
                                packed_weights_i[i] };
    end
  end

endmodule