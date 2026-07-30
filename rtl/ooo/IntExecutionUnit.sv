module IntExecutionUnit(
    input issue_pkt_t issue_pkt,
    output dris_writeback_pkt_t writeback_pkt
);

   logic [XLEN-1:0] alu_out, next_pc;
   logic bcond;

    riscv_alu alu (
        .alu_src1 (issue_pkt.op_1_I),
        .alu_src2 (issue_pkt.op_2_I),
        .alu_op   (issue_pkt.ctrl_signals_I.alu_op),
        .alu_out  (alu_out)
    );

    assign bcond = alu_out[0];

    always_comb begin: next_pc_logic
        unique case (issue_pkt.ctrl_signals_I.pc_source)
            PC_cond:     next_pc =
                             bcond
                                 ? issue_pkt.pc_I + issue_pkt.imm_I
                                 : issue_pkt.pc_I + XLEN'(4);
            PC_uncond:   next_pc =
                             issue_pkt.pc_I + issue_pkt.imm_I;
            // op_1_I is the PC here (usePC link setup), so the target's
            // rs1 rides the packet's dedicated rs1_data_I field
            PC_indirect: next_pc =
                             (issue_pkt.rs1_data_I + issue_pkt.imm_I)
                             & ~(XLEN'(1));
            default:     next_pc =
                             issue_pkt.pc_I + XLEN'(4);
        endcase        
    end: next_pc_logic

    always_comb begin: writeback_pkt_generation
        writeback_pkt.valid_W = issue_pkt.ready_I;
        writeback_pkt.id_W = issue_pkt.id_I;
        writeback_pkt.pc_W = issue_pkt.pc_I;
        writeback_pkt.ctrl_signals_W = issue_pkt.ctrl_signals_I;
        writeback_pkt.result_data_W = alu_out;
        writeback_pkt.next_pc_W = next_pc;

        `ifdef DEBUG
                writeback_pkt.debug_instr_dris_W = issue_pkt.debug_instr_I;
        `endif

    end: writeback_pkt_generation

endmodule : IntExecutionUnit
