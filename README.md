# W4A8 mixed-precision SIMD NPU Accelerator

A hardware-proven, high-efficiency Neural Processing Unit (NPU) accelerator featuring a 3-stage pipelined **W4A8 SIMD MAC engine** paired with a **Decoupled-Access/Execute (DAE) memory controller** [1, 15, 16]. This IP is designed as a silicon-bound production asset for low-latency, edge-side Large Language Model (LLM) and Transformer matrix inference [1].

The design is fully synthesizable, utilizing dedicated **SystemVerilog RTL** optimized for Xilinx UltraScale+ FPGAs (specifically VU9P targets) to bypass the traditional "AI Memory Wall" and maximize hardware DSP density [1, 14, 15].

---

## Key Architectural Features

* **W4A8 Mixed-Precision Format**: Combines heavily quantized **4-bit signed weights (W4)** with highly sensitive **8-bit signed activations (A8)** and an **8-bit signed scale factor** [1, 3, 6]. This achieves a **4x reduction in weight memory bandwidth** while preserving model precision through dynamic dequantization [1].
* **3-Stage Spatial Pipeline**: Executes steady-state **1 MAC/cycle (4 operations/cycle)** [5]. The pipeline is architectured across three distinct stages to manage arithmetic dependencies without clock bubbles:
  * **Stage 1 (Dequantization & Isolation)**: Combinatorial sign-extension and Scale $\times$ Weight multiplication [7, 8].
  * **Stage 2 (SIMD Multiplication)**: Matrix multiply array computing 16-bit intermediate values with 8-bit activations [8].
  * **Stage 3 (Reduction & Accumulation)**: High-performance spatial adder tree coupled with a 32-bit vector accumulator [9].
* **Decoupled Access/Execute (DAE)**: Isolates the memory-bound logistics from compute logic. The control system uses two independent state machines (Fetch and Writeback) interfacing with three True Dual-Port Block RAM (BRAM) arrays, ensuring the execution engine remains completely saturated with data [15, 16].
* **Low-Power Optimizations**: Implements **zero-activation operand isolation** and automatic clock-enable gating, shutting down redundant register switching in the multiplier array to save up to **30% in dynamic datapath power** [8, 18].
* **AXI4-Stream Protocol Interconnect**: Synchronizes weight and activation transfers with joint-valid handshaking and backpressure stall propagation [3, 10].
* **Verification & Safety**: Includes concurrent **SystemVerilog Assertions (SVA)** for bus protocol compliance and a class-based, constrained-random coverage-driven testbench [10, 11].

---

## Repository Directory Tree

Strict directory hygiene is maintained to support seamless integration with Vivado IP Repository packaging, non-project batch scripting, or standard simulation frameworks [2]:

```text
w4a8_npu_core/
├── docs/
│   ├── w4a8_mac_microarch_spec.md       # Microarchitectural timing & register spec
│   └── synth_utilization.rpt            # Vivado out-of-context utilization reports
├── rtl/
│   ├── w4a8_pkg.sv                      # Global parameters, structs, types [COMPILE FIRST]
│   ├── w4a8_weight_unpacker.sv          # INT4 to INT8 combinatorial sign-extension
│   ├── w4a8_simd_lane.sv                # Single scalar pipeline lane (Dequant + Mult)
│   ├── w4a8_execution_core.sv           # Spatial adder tree, accumulator, pipeline control
│   ├── w4a8_top.sv                      # AXI4-Stream compute core wrapper & SVA logic
│   ├── npu_bram_dp.sv                   # Inferrable True Dual-Port block RAM template
│   ├── npu_controller.sv                # Decoupled Fetch & Writeback scheduler FSMs
│   └── npu_core_top.sv                  # NPU top-level system structural wrapper
├── tb/
│   ├── interfaces/
│   │   └── axi4_stream_if.sv            # AXI4-Stream interface definitions
│   └── tb_w4a8_top.sv                   # Class-based verification environment with coverage
└── scripts/
    ├── vivado_synth.tcl                 # Vivado non-project Out-Of-Context synthesis script
    └── vivado_sim.tcl                   # Vivado xsim compilation and simulation run script
```

---

## Architectural Block Diagram

Below is the internal dataflow mapping, detailing how data is fetched from local dual-port SRAM, streamed through the 3-stage synchronized execution core, and committed back to the output memory buffer [4, 17]:

```text
+-----------------------------------------------------------------------------------------+
|                                      NPU CORE TOP                                       |
|                                                                                         |
|  [Host Config Bus] ---> Registers (Start, cfg_m_rows_i, cfg_k_iters_i)                  |
|                                |                                                        |
|                       +--------v---------+                                              |
|   [Host BRAM Port] -> |  Fetch Engine    |   <---- Address Generation                   |
|                       +--+------------+--+                                              |
|                          | (Addrs)    |                                                 |
|    +---------------------v-+       +--v--------------------+                            |
|    | Weight BRAM (Dual Pt) |       | Act BRAM (Dual Pt)    |                            |
|    +---------------------+-+       +--+--------------------+                            |
|                          |            |                                                 |
|  AXI-S Weights (24b) --> |            | <-- AXI-S Acts (32b + tlast)                    |
|                       +--v------------v--+                                              |
|                       |    w4a8_top      | (Compute Core Wrapper)                       |
|                       |==================|                                              |
|                       | STAGE 1:         | -- Sign-Extension & Dequant (Scale * Weight) |
|                       | STAGE 2:         | -- SIMD Multiplication (4 Labeled Lanes)     |
|                       | STAGE 3:         | -- Spatial Adder Tree & 32-bit Accumulator   |
|                       +--------+---------+                                              |
|                                | AXI-S Result (32b)                                     |
|                       +--------v---------+                                              |
|                       | Writeback Engine |                                              |
|                       +--------+---------+                                              |
|                                | (Addrs & Data)                                         |
|                       +--------v---------+                                              |
|   [Host BRAM Port] <- | Output BRAM      |                                              |
|                       +------------------+                                              |
+-----------------------------------------------------------------------------------------+
```

---

## Detailed Pipeline Timeline

The MAC datapath requires a steady-state latency of **3 cycles** [5]. Handshaking is governed by a global stall network propagated from `m_axis_res_tready` to prevent register data overwrites [5, 10].

| Clock Cycle | Stage | Operations executed in hardware |
|---|---|---|
| **Cycle T0** | **Fetch & Unpack** | Fetch inputs. Unpack four packed `INT4` weights to `INT8` using manual sign-extension [7]. |
| **Cycle T1** | **Stage 1 (Dequant)** | Multiply unpacked 8-bit weights by the 8-bit scale factor (`w_ext_i * scale_i`) [8]. Apply zero-activation operand isolation on inputs to gate multiplying stages [8]. |
| **Cycle T2** | **Stage 2 (Multiply)** | Feed dequantized weights (16-bit) and activations (8-bit) to SIMD multiplier lanes to produce four 24-bit product terms [8]. |
| **Cycle T3** | **Stage 3 (Reduce)** | Sum products combinatorially via an adder tree (`PROD_W` $\rightarrow$ 25-bit $\rightarrow$ 26-bit) [9]. Accumulate intermediate results into a 32-bit register (`acc_q`) [9]. |
| **Cycle T4+** | **Writeback** | Once the `tlast` packet boundary is processed, write the accumulated results directly into Output SRAM and clear registers [9, 24]. |

---

## Verifying the Design

The verification suite (`tb/tb_w4a8_top.sv`) includes a complete, constrained-random functional simulation block with a golden software model and a parameterized functional coverage group [11, 12].

### Covergroup Model Coverage Parameters
The coverage engine tracks hardware utilization across several boundary targets:
* **Weight Binning**: Verifies performance across raw `INT4` bounds: `-8` (`min_val`), `+7` (`max_val`), and `0` (`zero`) [12].
* **Activation Binning**: Evaluates clock-gating transitions (`8'h00` vs. non-zero `[1:255]`) [12].
* **Stall Gating**: Measures the effectiveness of backpressure-induced stalls [12].

### Running Simulation (Vivado xsim)
To compile the system libraries and run the random stimulus suite, execute this command in your terminal:
```bash
vivado -mode batch -source scripts/vivado_sim.tcl
```

### Out-of-Context Synthesis (PPA Metrics)
To verify the physical timing footprint and resource constraints without requiring top-level input/output pad allocations, run:
```bash
vivado -mode batch -source scripts/vivado_synth.tcl
```
Utilization reports and critical timing budgets will be generated inside `docs/synth_utilization.rpt` and `docs/synth_timing.rpt` respectively [14].

---

## FPGA System Integration

Once packaged as an IP Block inside Vivado, this accelerator can be easily integrated into a system-on-chip block design [28, 29]:

1. **IP Packaging**: Use Vivado's IP Packager (`Tools > Create and Package New IP`) to bundle the `npu_core_top` module.
2. **Block Design**: Connect a host controller (such as a hard-core ARM processor in Zynq or a soft-core MicroBlaze processor) [29].
3. **Memory Configuration**: Configure three **AXI BRAM Controller** IPs in dual-port mode. Map their BRAM Port B pins directly to the `host_w_*`, `host_a_*`, and `host_out_*` ports of the NPU [29].
4. **Control Lines**: Map an AXI GPIO peripheral to drive control wires (`host_start`, `host_cfg_m_rows`, `host_cfg_k_iters`) and listen to the interrupt line (`npu_done_irq`) [29].

### Host Bare-Metal C Implementation
Your bare-metal driver (running in Vitis) uses the following system workflow to initiate a matrix-vector calculation [30]:

```c
#include <string.h>
#include "xgpio.h"

// Define address mapping for physical AXI BRAM Controllers
#define ACT_BRAM_ADDR     (volatile int*)0xC0000000
#define WEIGHT_BRAM_ADDR  (volatile int*)0xC2000000
#define OUT_BRAM_ADDR     (volatile int*)0xC4000000

void run_npu_inference(int m_rows, int k_cols, int* weights, int* acts, int* results) {
    XGpio gpio;
    XGpio_Initialize(&gpio, 0); // Initialize NPU Control GPIO interface
    
    // 1. Flush quantized activation vectors to Activation BRAM (e.g., 64 bytes)
    memcpy((void*)ACT_BRAM_ADDR, acts, k_cols);
    
    // 2. Flush packed quantized weights to Weight BRAM (e.g., 1024 bytes)
    memcpy((void*)WEIGHT_BRAM_ADDR, weights, (m_rows * k_cols) / 4);
    
    // 3. Write configuration settings via GPIO: cfg_m_rows and cfg_k_iters (col / 4)
    // Example: For 16 rows and 64 columns (k_iters = 16)
    int cfg_k_iters = k_cols / 4;
    XGpio_DiscreteWrite(&gpio, 1, (m_rows << 16) | cfg_k_iters);
    
    // 4. Pulse the host_start pin to trigger execution
    XGpio_DiscreteWrite(&gpio, 2, 1); // Start high
    XGpio_DiscreteWrite(&gpio, 2, 0); // Start low
    
    // 5. Poll the interrupt pin or wait for Done IRQ
    while (XGpio_DiscreteRead(&gpio, 3) == 0);
    
    // 6. Pull completed 32-bit outputs out of the Output BRAM
    memcpy(results, (void*)OUT_BRAM_ADDR, m_rows * sizeof(int));
}
```

---

## References

* **Microsoft Research**: *ZeroQuant-FP: A Leap Forward in LLMs Post-Training W4A8 Quantization Using Floating-Point Formats* [17].
* **Cornell University**: *Understanding the Potential of FPGA-Based Spatial Acceleration for Large Language Model Inference* [14].
* **DATE 2000**: *Automating RT-Level Operand Isolation to Minimize Power Consumption in Datapaths* [18].
* **arXiv**: *LlamaF: An Efficient Llama2 Architecture Accelerator on Embedded FPGAs* [7].
