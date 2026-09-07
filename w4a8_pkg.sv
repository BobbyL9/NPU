// -----------------------------------------------------------------------------
// Apple Silicon - W4A8 Global Package
// -----------------------------------------------------------------------------
package w4a8_pkg;
  parameter int SIMD_WIDTH = 4;
  parameter int WEIGHT_W   = 4;
  parameter int ACT_W      = 8;
  parameter int SCALE_W    = 8;
  parameter int INT_W      = 16; // W(8-bit ext) * S(8-bit)
  parameter int PROD_W     = 24; // Int(16-bit) * A(8-bit)
  parameter int ACC_W      = 32;

  // Struct definitions for clean routing
  typedef struct packed {
    logic signed [SCALE_W-1:0]  scale;
    logic [SIMD_WIDTH-1:0][WEIGHT_W-1:0] weights; 
  } weight_payload_t;

  typedef struct packed {
    logic signed [ACT_W-1:0] a;
  } act_payload_t;
endpackage : w4a8_pkg