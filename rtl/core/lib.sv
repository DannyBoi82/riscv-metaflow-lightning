/**
 * lib.sv
 *
 * RISC-V 32-bit Processor
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * Library of standard components used by the RISC-V processor:
 * combinational primitives (mux, adder), the register primitive,
 * load/store helpers, the immediate generator, the BTB predictor,
 * the ALU, the stall controller, and the forwarding controller.
**/

/*----------------------------------------------------------------------------*
 *  You may edit this file and add or change any files in the src directory.  *
 *----------------------------------------------------------------------------*/

`default_nettype none

// Types (imm_mode_t, alu_op_t, ...) live in the internal_defines_pkg
// package (rtl/core/0internal_defines_pkg.sv), so every file using them
// must import it itself: VCS compiles each file as its own compilation
// unit, so imports never leak across files like they do under Verilator.
import internal_defines_pkg::*;

/*--------------------------------------------------------------------------*
 * Combinational primitives                                                  *
 *--------------------------------------------------------------------------*/

/**
 * INPUTS:1 mux of WIDTH-bit values, selecting one input to drive `out`.
 **/
module mux
    #(parameter INPUTS=0, WIDTH=0)
    (input  logic [INPUTS-1:0][WIDTH-1:0]   in,
     input  logic [$clog2(INPUTS)-1:0]      sel,
     output logic [WIDTH-1:0]               out);

    assign out = in[sel];

endmodule: mux

/**
 * WIDTH-bit ripple adder with carry-in and carry-out.
 **/
module adder
    #(parameter WIDTH=0)
    (input  logic               cin,
     input  logic [WIDTH-1:0]   A, B,
     output logic               cout,
     output logic [WIDTH-1:0]   sum);

    assign {cout, sum} = A + B + cin;

endmodule: adder

/*--------------------------------------------------------------------------*
 * Synchronous primitives                                                    *
 *--------------------------------------------------------------------------*/

/**
 * WIDTH-bit register with asynchronous active-low reset, synchronous
 * active-high clear, and an enable. Reset/clear value is RESET_VAL.
 **/
module register
   #(parameter                   WIDTH=0,
     parameter logic [WIDTH-1:0] RESET_VAL='b0)
    (input  logic               clk, en, rst_l, clear,
     input  logic [WIDTH-1:0]   D,
     output logic [WIDTH-1:0]   Q);

    always_ff @(posedge clk, negedge rst_l) begin
        if (!rst_l)     Q <= RESET_VAL;
        else if (clear) Q <= RESET_VAL;
        else if (en)    Q <= D;
    end

endmodule: register

/*--------------------------------------------------------------------------*
 * Load/store helpers (M1 stage)                                             *
 *--------------------------------------------------------------------------*/

/**
 * Selects writeback data from either the ALU result or the load-data path,
 * applying sign- or zero-extension based on the load mode.
 **/
module RDDataMux
    (input  ctrl_signals_t  ctrl_signals,
     input  logic [1:0]     byte_offset,
     input  logic [31:0]    data_load, alu_out,
     output logic [31:0]    rd_data);

    always_comb begin: rd_data_mux
        if (ctrl_signals.mem2RF === 1'b1) begin
            case (ctrl_signals.ldst_mode)
                LDST_W:  rd_data = data_load;
                LDST_H:  rd_data = byte_offset[1]
                                 ? {{16{data_load[31]}}, data_load[31:16]}
                                 : {{16{data_load[15]}}, data_load[15:0]};
                LDST_HU: rd_data = byte_offset[1]
                                 ? {16'd0, data_load[31:16]}
                                 : {16'd0, data_load[15:0]};
                LDST_B: begin
                    case (byte_offset)
                        2'd0: rd_data = {{24{data_load[7]}},  data_load[7:0]};
                        2'd1: rd_data = {{24{data_load[15]}}, data_load[15:8]};
                        2'd2: rd_data = {{24{data_load[23]}}, data_load[23:16]};
                        2'd3: rd_data = {{24{data_load[31]}}, data_load[31:24]};
                    endcase
                end
                LDST_BU: begin
                    case (byte_offset)
                        2'd0: rd_data = {24'd0, data_load[7:0]};
                        2'd1: rd_data = {24'd0, data_load[15:8]};
                        2'd2: rd_data = {24'd0, data_load[23:16]};
                        2'd3: rd_data = {24'd0, data_load[31:24]};
                    endcase
                end
                default: rd_data = data_load;
            endcase
        end
        else begin
            rd_data = alu_out;
        end
    end: rd_data_mux

endmodule: RDDataMux

/**
 * Aligns store data to the byte/half it will be written to within the
 * 32-bit data word.
 **/
module DataMasker
    (input  ldst_mode_t  ldst_mode,
     input  logic [1:0]  byte_offset,
     input  logic [31:0] rs2_data,
     output logic [31:0] data_store);

    always_comb begin
        if ((ldst_mode === LDST_B) || (ldst_mode === LDST_BU)) begin
            case (byte_offset)
                2'd0: data_store = {24'd0, rs2_data[7:0]};
                2'd1: data_store = {16'd0, rs2_data[7:0], 8'd0};
                2'd2: data_store = {8'd0,  rs2_data[7:0], 16'd0};
                2'd3: data_store = {       rs2_data[7:0], 24'd0};
            endcase
        end
        else if ((ldst_mode === LDST_H) || (ldst_mode === LDST_HU)) begin
            data_store = byte_offset[1]
                       ? {rs2_data[15:0], 16'd0}
                       : {16'd0,          rs2_data[15:0]};
        end
        else begin
            data_store = rs2_data;
        end
    end

endmodule: DataMasker

/**
 * Generates the byte-enable mask for stores. Returns 0 when this is not a
 * store, otherwise the appropriate W/H/B mask shifted to the access offset.
 **/
module DataStoreMaskGenerator
    (input  ctrl_signals_t  ctrl_signals,
     input  logic [1:0]     byte_offset,
     output logic [3:0]     data_store_mask);

    always_comb begin
        data_store_mask = 4'h0;
        if (ctrl_signals.memWrite) begin
            case (ctrl_signals.ldst_mode)
                LDST_W: data_store_mask = 4'b1111;
                LDST_H, LDST_HU:
                    data_store_mask = byte_offset[1] ? 4'b1100 : 4'b0011;
                LDST_B, LDST_BU: begin
                    case (byte_offset)
                        2'd0: data_store_mask = 4'b0001;
                        2'd1: data_store_mask = 4'b0010;
                        2'd2: data_store_mask = 4'b0100;
                        2'd3: data_store_mask = 4'b1000;
                    endcase
                end
                default: data_store_mask = 4'h0;
            endcase
        end
    end

endmodule: DataStoreMaskGenerator

/*--------------------------------------------------------------------------*
 * Immediate generator (D stage)                                             *
 *--------------------------------------------------------------------------*/

/**
 * Sign-extends the immediate field of the instruction according to the
 * encoding format selected by `imm_mode`. See RISC-V User-Level ISA spec.
 **/
module ImmediateGenerator
    (input  logic [31:0] instr,
     input  imm_mode_t   imm_mode,
     output logic [31:0] immediate);

    always_comb begin
        case (imm_mode)
            IMM_I:   immediate = {{21{instr[31]}}, instr[30:20]};
            IMM_S:   immediate = {{21{instr[31]}}, instr[30:25], instr[11:8], instr[7]};
            IMM_SB:  immediate = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            IMM_U:   immediate = {{2{instr[31]}}, instr[30:20], instr[19:12], 12'd0};
            IMM_UJ:  immediate = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:25], instr[24:21], 1'b0};
            /* Distinct sentinel patterns to make X-propagation visible in
             * waves. IMM_DC is 3'bx: a 4-state-only case item that can never
             * match in 2-state Verilator, which is fine — it is unreachable
             * under VCS too unless the control path itself is X. */
            // verilator lint_off CASEWITHX
            IMM_DC:  immediate = 32'hC0FFEE12;
            // verilator lint_on CASEWITHX
            default: immediate = 32'hDEADBEEF;
        endcase
    end

endmodule: ImmediateGenerator

/*--------------------------------------------------------------------------*
 * BTB / branch predictor                                                    *
 *--------------------------------------------------------------------------*/

//`define ZERO_BIT_PRED
//`define ONE_BIT_PRED
`ifndef TWO_BIT_PRED
`define TWO_BIT_PRED
`endif

/**
 * BTB-backed branch predictor.
 *
 * Read port (F1):  pc_F1 indexes the BTB, returning {tag, hist, target}.
 *                  predicted_next_pc is the target on a hit-and-take, else
 *                  npc_plus4_F1.
 * Write port (M1): control-flow ops (cond/uncond/indirect) update the entry
 *                  with the resolved target and updated history bits.
 **/
module BTBPredictor
    (input  logic              clk, rst_l,
     input  logic              bcond_write,
     input  ctrl_signals_t     ctrl_signals_write,
     input  logic              correct_branch_prediction,
     input  logic [31:0]       pc_F1, pc_write,
     input  logic [31:0]       npc_plus4_F1,
     input  logic [31:0]       npc_offset_write,
     input  logic [1:0]        write_btb_hist,
     output logic [31:0]       predicted_next_pc,
     output logic [1:0]        read_btb_hist,
     output logic              taken_branch,
     output logic              btb_hit);

    logic [61:0] btb_write_data;
    logic [61:0] btb_read_data;
    logic [29:0] tag, prediction;
    logic [1:0]  read_hist, write_hist;
    logic        btb_we;

    // Write-enable: only update on real control-flow instructions.
    always_comb begin
        case (ctrl_signals_write.pc_source)
            PC_cond, PC_indirect, PC_uncond: btb_we = 1'b1;
            default:                         btb_we = 1'b0;
        endcase
    end

    // BTB write payload
    always_comb begin
        case (ctrl_signals_write.pc_source)
            PC_cond, PC_uncond, PC_indirect:
                btb_write_data = {pc_write[31:2], write_hist, npc_offset_write[31:2]};
            default:
                btb_write_data = 62'd0;
        endcase
    end

    assign {tag, read_hist, prediction} = btb_read_data;
    assign read_btb_hist = read_hist;
    assign btb_hit       = (tag === pc_F1[31:2]);

    sram_1r_1w #(.NUM_WORDS(128), .WORD_WIDTH(62)) BTB (
        .clk        (clk),
        .rst_l      (rst_l),
        .we         (btb_we),
        .read_addr  (pc_F1[8:2]),
        .write_addr (pc_write[8:2]),
        .write_data (btb_write_data),
        .read_data  (btb_read_data)
    );

    // Was the in-flight (M1) branch actually taken?
    logic taken;
    assign taken = ((ctrl_signals_write.pc_source === PC_cond) & (bcond_write === 1'b1))
                 |  (ctrl_signals_write.pc_source === PC_indirect)
                 |  (ctrl_signals_write.pc_source === PC_uncond);
    assign taken_branch = taken;

    // ----- Predictor selection -----
    `ifdef ZERO_BIT_PRED
        // Always predict not-taken; history bits unused but must be driven.
        assign predicted_next_pc = npc_plus4_F1;
        assign write_hist        = 2'b00;

    `elsif ONE_BIT_PRED
        always_comb begin
            predicted_next_pc = (read_hist[0] && btb_hit)
                              ? {prediction, 2'b00}
                              : npc_plus4_F1;
        end
        assign write_hist = taken ? 2'b01 : 2'b00;

    `elsif TWO_BIT_PRED
        // 2'b1x = predict taken, 2'b0x = predict not-taken.
        always_comb begin
            case (read_hist)
                2'b10, 2'b11: predicted_next_pc = btb_hit ? {prediction, 2'b00} : npc_plus4_F1;
                default:      predicted_next_pc = npc_plus4_F1;
            endcase
        end

        // Saturating 2-bit counter update
        always_comb begin
            case (write_btb_hist)
                2'b00:   write_hist = taken ? 2'b01 : 2'b00;
                2'b01:   write_hist = taken ? 2'b10 : 2'b00;
                2'b10:   write_hist = taken ? 2'b11 : 2'b01;
                2'b11:   write_hist = taken ? 2'b11 : 2'b10;
                default: write_hist = 2'b00;
            endcase
        end

    `else
        $error("BTBPredictor: no predictor type defined. Define ZERO_BIT_PRED, ONE_BIT_PRED, or TWO_BIT_PRED.");
    `endif

endmodule: BTBPredictor

/*--------------------------------------------------------------------------*
 * ALU                                                                       *
 *--------------------------------------------------------------------------*/

/**
 * Single-cycle ALU. Operation selected by alu_op_t. Branch ops produce a
 * 0/1 result in alu_out[0]; the rest produce a 32-bit result.
 **/
module riscv_alu
    (input  logic [31:0] alu_src1,
     input  logic [31:0] alu_src2,
     input  alu_op_t     alu_op,
     output logic [31:0] alu_out);

    always_comb begin
        unique case (alu_op)
            ALU_ADD:  alu_out = alu_src1 + alu_src2;
            ALU_ADD4: alu_out = alu_src1 + 32'd4;
            ALU_SUB:  alu_out = alu_src1 + (~alu_src2 + 32'd1);
            ALU_SLL:  alu_out = alu_src1 << alu_src2[4:0];
            ALU_SLLI: alu_out = alu_src1 << alu_src2[4:0];
            ALU_SRL:  alu_out = alu_src1 >> alu_src2[4:0];
            ALU_SRA:  alu_out = $signed($signed(alu_src1) >>> alu_src2[4:0]);
            ALU_XOR:  alu_out = alu_src1 ^ alu_src2;
            ALU_OR:   alu_out = alu_src1 | alu_src2;
            ALU_AND:  alu_out = alu_src1 & alu_src2;

            ALU_SLT:  alu_out = ($signed(alu_src1) < $signed(alu_src2)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_out = (alu_src1 < alu_src2)                  ? 32'd1 : 32'd0;

            // Branch comparators: result in bit 0
            ALU_BEQ:  alu_out = {31'd0, alu_src1 == alu_src2};
            ALU_BNE:  alu_out = {31'd0, alu_src1 != alu_src2};
            ALU_BLT:  alu_out = {31'd0, $signed(alu_src1) <  $signed(alu_src2)};
            ALU_BGE:  alu_out = {31'd0, $signed(alu_src1) >= $signed(alu_src2)};
            ALU_BLTU: alu_out = {31'd0, alu_src1 <  alu_src2};
            ALU_BGEU: alu_out = {31'd0, alu_src1 >= alu_src2};

            // Pass-through (used by LUI to put the U-immediate into rd)
            ALU_PASS: alu_out = alu_src2;
            default:  alu_out = 32'bx;
        endcase
    end

endmodule: riscv_alu

/*--------------------------------------------------------------------------*
 * Stall controller (D stage)                                                *
 *--------------------------------------------------------------------------*/

/**
 * Detects load-use hazards that cannot be solved by forwarding alone.
 * A stall is required if the consumer in D reads a register that an
 * in-flight load (E/M1/M2) is producing.
 **/
module StallFDController
    (input  ctrl_signals_t  ctrl_signals_D,
     input  ctrl_signals_t  ctrl_signals_E,
     input  ctrl_signals_t  ctrl_signals_M1,
     input  ctrl_signals_t  ctrl_signals_M2,
     input  ctrl_signals_t  ctrl_signals_W,         // unused but kept for symmetry
     input  logic [4:0]     rs1_D, rs2_D,
     input  logic [4:0]     rd_E, rd_M1, rd_M2, rd_W, // rd_W unused but kept for symmetry
     input  logic           instr_valid,             // unused; cache-side stall handled in core
     output logic           stall);

    // Suppress "unused" lint by naming explicitly.
    /* verilator lint_off UNUSED */
    ctrl_signals_t unused_ctrl_W = ctrl_signals_W;
    logic [4:0]    unused_rd_W   = rd_W;
    logic          unused_iv     = instr_valid;
    /* verilator lint_on UNUSED */

    logic regw_E,   regw_M1,  regw_M2;
    logic memRead_E, memRead_M1, memRead_M2;

    assign regw_E    = ctrl_signals_E.rfWrite;
    assign regw_M1   = ctrl_signals_M1.rfWrite;
    assign regw_M2   = ctrl_signals_M2.rfWrite;
    assign memRead_E  = ctrl_signals_E.memRead;
    assign memRead_M1 = ctrl_signals_M1.memRead;
    assign memRead_M2 = ctrl_signals_M2.memRead;

    always_comb begin
        logic hazard_rs1, hazard_rs2;

        hazard_rs1 = ctrl_signals_D.uses_rs1 && (rs1_D != 5'd0) && (
            (rs1_D == rd_E ) && regw_E  && memRead_E  ||
            (rs1_D == rd_M1) && regw_M1 && memRead_M1 ||
            (rs1_D == rd_M2) && regw_M2 && memRead_M2);

        hazard_rs2 = ctrl_signals_D.uses_rs2 && (rs2_D != 5'd0) && (
            (rs2_D == rd_E ) && regw_E  && memRead_E  ||
            (rs2_D == rd_M1) && regw_M1 && memRead_M1 ||
            (rs2_D == rd_M2) && regw_M2 && memRead_M2);

        stall = hazard_rs1 || hazard_rs2;
    end

endmodule: StallFDController

/*--------------------------------------------------------------------------*
 * Forwarding controller (D stage)                                           *
 *--------------------------------------------------------------------------*/

/**
 * Bypass network for the D-stage register-read.
 * Priority (newest result wins): E > M1 > M2 > W > regfile.
 **/
module ForwardingController
    (input  ctrl_signals_t  ctrl_signals_D,
     input  ctrl_signals_t  ctrl_signals_E,
     input  ctrl_signals_t  ctrl_signals_M1,
     input  ctrl_signals_t  ctrl_signals_M2,
     input  ctrl_signals_t  ctrl_signals_W,
     input  logic [4:0]     rs1_D, rs2_D,
     input  logic [4:0]     rd_E, rd_M1, rd_M2, rd_W,
     input  logic [31:0]    alu_out_E, alu_out_M1, alu_out_M2, alu_out_W,
     input  logic [31:0]    rs1_data_D, rs2_data_D,
     input  logic [31:0]    rd_data_W,
     output logic [31:0]    rs1_data_fwded, rs2_data_fwded);

    // alu_out_W is unused (the W-stage forwarded value is rd_data_W, which
    // already includes load-mux output). Kept on the port list so a future
    // change can add e.g. a separate ALU-only forward without re-wiring.
    /* verilator lint_off UNUSED */
    logic [31:0] unused_alu_out_W = alu_out_W;
    /* verilator lint_on UNUSED */

    logic regw_E, regw_M1, regw_M2, regw_W;
    assign regw_E  = ctrl_signals_E.rfWrite;
    assign regw_M1 = ctrl_signals_M1.rfWrite;
    assign regw_M2 = ctrl_signals_M2.rfWrite;
    assign regw_W  = ctrl_signals_W.rfWrite;

    always_comb begin
        logic hit_E_rs1, hit_M1_rs1, hit_M2_rs1, hit_W_rs1;
        logic hit_E_rs2, hit_M1_rs2, hit_M2_rs2, hit_W_rs2;

        hit_E_rs1  = ctrl_signals_D.uses_rs1 & (rs1_D != 5'd0) & regw_E  & (rd_E  != 5'd0) & (rs1_D == rd_E );
        hit_M1_rs1 = ctrl_signals_D.uses_rs1 & (rs1_D != 5'd0) & regw_M1 & (rd_M1 != 5'd0) & (rs1_D == rd_M1);
        hit_M2_rs1 = ctrl_signals_D.uses_rs1 & (rs1_D != 5'd0) & regw_M2 & (rd_M2 != 5'd0) & (rs1_D == rd_M2);
        hit_W_rs1  = ctrl_signals_D.uses_rs1 & (rs1_D != 5'd0) & regw_W  & (rd_W  != 5'd0) & (rs1_D == rd_W );

        hit_E_rs2  = ctrl_signals_D.uses_rs2 & (rs2_D != 5'd0) & regw_E  & (rd_E  != 5'd0) & (rs2_D == rd_E );
        hit_M1_rs2 = ctrl_signals_D.uses_rs2 & (rs2_D != 5'd0) & regw_M1 & (rd_M1 != 5'd0) & (rs2_D == rd_M1);
        hit_M2_rs2 = ctrl_signals_D.uses_rs2 & (rs2_D != 5'd0) & regw_M2 & (rd_M2 != 5'd0) & (rs2_D == rd_M2);
        hit_W_rs2  = ctrl_signals_D.uses_rs2 & (rs2_D != 5'd0) & regw_W  & (rd_W  != 5'd0) & (rs2_D == rd_W );

        priority casez ({hit_E_rs1, hit_M1_rs1, hit_M2_rs1, hit_W_rs1})
            4'b1???:  rs1_data_fwded = alu_out_E;
            4'b01??:  rs1_data_fwded = alu_out_M1;
            4'b001?:  rs1_data_fwded = alu_out_M2;
            4'b0001:  rs1_data_fwded = rd_data_W;
            default:  rs1_data_fwded = rs1_data_D;
        endcase

        priority casez ({hit_E_rs2, hit_M1_rs2, hit_M2_rs2, hit_W_rs2})
            4'b1???:  rs2_data_fwded = alu_out_E;
            4'b01??:  rs2_data_fwded = alu_out_M1;
            4'b001?:  rs2_data_fwded = alu_out_M2;
            4'b0001:  rs2_data_fwded = rd_data_W;
            default:  rs2_data_fwded = rs2_data_D;
        endcase
    end

endmodule: ForwardingController