# Begin_DVE_Session_Save_Info
# DVE view(Wave.1 ) session
# Saved on Thu Aug 6 18:35:47 2026
# Toplevel windows open: 2
# 	TopLevel.1
# 	TopLevel.2
#   Wave.1: 316 signals
# End_DVE_Session_Save_Info

# DVE version: T-2022.06_Full64
# DVE build date: May 31 2022 20:53:03


#<Session mode="View" path="/afs/ece.cmu.edu/usr/daniello/Private/riscv-metaflow-lightning/mixed_store_bug.tcl" type="Debug">

#<Database>

gui_set_time_units 1s
#</Database>

# DVE View/pane content session: 

# Begin_DVE_Session_Save_Info (Wave.1)
# DVE wave signals session
# Saved on Thu Aug 6 18:35:47 2026
# 316 signals
# End_DVE_Session_Save_Info

# DVE version: T-2022.06_Full64
# DVE build date: May 31 2022 20:53:03


#Add ncecessay scopes
gui_load_child_values {top.RISCV_Core_interface.core_inst.scheduler}
gui_load_child_values {top.RISCV_Core_interface.core_inst.ssc}
gui_load_child_values {top.RISCV_Core_interface.core_inst.iiu}

gui_set_time_units 1s

set _wave_session_group_1 core_inst_1
if {[gui_sg_is_group -name "$_wave_session_group_1"]} {
    set _wave_session_group_1 [gui_sg_generate_new_name]
}
set Group1 "$_wave_session_group_1"

gui_sg_addsignal -group "$_wave_session_group_1" { {Sim:top.RISCV_Core_interface.core_inst.core_req_stall_mem} {Sim:top.RISCV_Core_interface.core_inst.fetch_pkts} {Sim:top.RISCV_Core_interface.core_inst.commit_pkts} {Sim:top.RISCV_Core_interface.core_inst.flush_vector} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_ready_d} {Sim:top.RISCV_Core_interface.core_inst.RF_WAYS} {Sim:top.RISCV_Core_interface.core_inst.issue_pkts_reg} {Sim:top.RISCV_Core_interface.core_inst.fetch_ptr} {Sim:top.RISCV_Core_interface.core_inst.core_req_we_d} {Sim:top.RISCV_Core_interface.core_inst.trap_valid} {Sim:top.RISCV_Core_interface.core_inst.core_req_id_d} {Sim:top.RISCV_Core_interface.core_inst.mem_rs2_data} {Sim:top.RISCV_Core_interface.core_inst.trap_pc} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_data_valid_d} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_ready} {Sim:top.RISCV_Core_interface.core_inst.retire_vector} {Sim:top.RISCV_Core_interface.core_inst.rf_commit_valid} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_ctrl_signals_d} {Sim:top.RISCV_Core_interface.core_inst.rf_we} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_data_valid} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_data_d} {Sim:top.RISCV_Core_interface.core_inst.sched_rs2_addr} {Sim:top.RISCV_Core_interface.core_inst.clock} {Sim:top.RISCV_Core_interface.core_inst.MEM_ISSUE_WAYS} {Sim:top.RISCV_Core_interface.core_inst.store_ready} {Sim:top.RISCV_Core_interface.core_inst.rf_commit_pc} {Sim:top.RISCV_Core_interface.core_inst.retire_ptr} {Sim:top.RISCV_Core_interface.core_inst.sched_rs1_data} {Sim:top.RISCV_Core_interface.core_inst.rf_rd_data} {Sim:top.RISCV_Core_interface.core_inst.writeback_pkts} {Sim:top.RISCV_Core_interface.core_inst.core_req_re_d} {Sim:top.RISCV_Core_interface.core_inst.halted} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_data} {Sim:top.RISCV_Core_interface.core_inst.rf_rd} {Sim:top.RISCV_Core_interface.core_inst.core_req_stall_mem_d} {Sim:top.RISCV_Core_interface.core_inst.rf_commit_pkts} {Sim:top.RISCV_Core_interface.core_inst.rf_rs1} {Sim:top.RISCV_Core_interface.core_inst.rf_rs2} {Sim:top.RISCV_Core_interface.core_inst.rf_rs1_data} {Sim:top.RISCV_Core_interface.core_inst.ADDRESS_SIZE} {Sim:top.RISCV_Core_interface.core_inst.mem_rs2_addr} {Sim:top.RISCV_Core_interface.core_inst.core_req_cancel} {Sim:top.RISCV_Core_interface.core_inst.sched_read_rf} {Sim:top.RISCV_Core_interface.core_inst.mem_rs1_data} {Sim:top.RISCV_Core_interface.core_inst.core_req_store_mask_d} {Sim:top.RISCV_Core_interface.core_inst.store_id} {Sim:top.RISCV_Core_interface.core_inst.RETIRES_PER_CYCLE} {Sim:top.RISCV_Core_interface.core_inst.issue_pkts} {Sim:top.RISCV_Core_interface.core_inst.WRITEBACK_PORTS} {Sim:top.RISCV_Core_interface.core_inst.dris_entries} {Sim:top.RISCV_Core_interface.core_inst.reset_n} {Sim:top.RISCV_Core_interface.core_inst.rf_commit_insn} {Sim:top.RISCV_Core_interface.core_inst.mem_read_rf} {Sim:top.RISCV_Core_interface.core_inst.core_req_ctrl_signals_d} {Sim:top.RISCV_Core_interface.core_inst.sched_rs1_addr} {Sim:top.RISCV_Core_interface.core_inst.flush_mask} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_addr_d} {Sim:top.RISCV_Core_interface.core_inst.core_req_cancel_d} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_excpt} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_excpt_d} {Sim:top.RISCV_Core_interface.core_inst.mem_issue_pkts} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_addr} {Sim:top.RISCV_Core_interface.core_inst.oldest_branch_id} {Sim:top.RISCV_Core_interface.core_inst.d_granted} {Sim:top.RISCV_Core_interface.core_inst.core_req_addr_d} {Sim:top.RISCV_Core_interface.core_inst.sched_rs2_data} {Sim:top.RISCV_Core_interface.core_inst.core_req_re} {Sim:top.RISCV_Core_interface.core_inst.core_rsp_id_d} {Sim:top.RISCV_Core_interface.core_inst.FETCH_WORDS} {Sim:top.RISCV_Core_interface.core_inst.reg_commits} {Sim:top.RISCV_Core_interface.core_inst.dris_intake_pkts} {Sim:top.RISCV_Core_interface.core_inst.set_dispatched} {Sim:top.RISCV_Core_interface.core_inst.mem_rs1_addr} }
gui_sg_addsignal -group "$_wave_session_group_1" { {Sim:top.RISCV_Core_interface.core_inst.EXEC_UNITS} {Sim:top.RISCV_Core_interface.core_inst.$unit} {Sim:top.RISCV_Core_interface.core_inst.update_bus} {Sim:top.RISCV_Core_interface.core_inst.set_dispatched_mem} {Sim:top.RISCV_Core_interface.core_inst.branch_fence_valid} {Sim:top.RISCV_Core_interface.core_inst.core_req_store_data_d} {Sim:top.RISCV_Core_interface.core_inst.core_req_addr} {Sim:top.RISCV_Core_interface.core_inst.trap_id} {Sim:top.RISCV_Core_interface.core_inst.rf_rs2_data} }
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.RF_WAYS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.RF_WAYS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.MEM_ISSUE_WAYS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.MEM_ISSUE_WAYS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.ADDRESS_SIZE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.ADDRESS_SIZE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.RETIRES_PER_CYCLE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.RETIRES_PER_CYCLE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.WRITEBACK_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.WRITEBACK_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.FETCH_WORDS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.FETCH_WORDS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.EXEC_UNITS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.EXEC_UNITS}

set _wave_session_group_2 dris_1
if {[gui_sg_is_group -name "$_wave_session_group_2"]} {
    set _wave_session_group_2 [gui_sg_generate_new_name]
}
set Group2 "$_wave_session_group_2"

gui_sg_addsignal -group "$_wave_session_group_2" { {Sim:top.RISCV_Core_interface.core_inst.dris.ENTRIES} {Sim:top.RISCV_Core_interface.core_inst.dris.locker_1_comb} {Sim:top.RISCV_Core_interface.core_inst.dris.MEMORY_READ_PORTS} {Sim:top.RISCV_Core_interface.core_inst.dris.full_id_tmp} {Sim:top.RISCV_Core_interface.core_inst.dris.clock} {Sim:top.RISCV_Core_interface.core_inst.dris.clear_valid} {Sim:top.RISCV_Core_interface.core_inst.dris.dep1} {Sim:top.RISCV_Core_interface.core_inst.dris.fetch_group_dep1_valid} {Sim:top.RISCV_Core_interface.core_inst.dris.dep2} {Sim:top.RISCV_Core_interface.core_inst.dris.dris_entries} {Sim:top.RISCV_Core_interface.core_inst.dris.fetch_pkts} {Sim:top.RISCV_Core_interface.core_inst.dris.set_dispatched} {Sim:top.RISCV_Core_interface.core_inst.dris.FETCH_WAYS} {Sim:top.RISCV_Core_interface.core_inst.dris.reset_n} {Sim:top.RISCV_Core_interface.core_inst.dris.REG_FILE_WRITE_PORTS} {Sim:top.RISCV_Core_interface.core_inst.dris.locker_2_comb} {Sim:top.RISCV_Core_interface.core_inst.dris.WRITEBACK_PORTS} {Sim:top.RISCV_Core_interface.core_inst.dris.fetch_group_dep2_valid} {Sim:top.RISCV_Core_interface.core_inst.dris.new_ids} {Sim:top.RISCV_Core_interface.core_inst.dris.fetch_ptr} {Sim:top.RISCV_Core_interface.core_inst.dris.MEMORY_WRITE_PORTS} {Sim:top.RISCV_Core_interface.core_inst.dris.writeback_pkts} {Sim:top.RISCV_Core_interface.core_inst.dris.dep2_completing_now} {Sim:top.RISCV_Core_interface.core_inst.dris.dep1_completing_now} {Sim:top.RISCV_Core_interface.core_inst.dris.$unit} {Sim:top.RISCV_Core_interface.core_inst.dris.EXEC_UNITS} }
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.ENTRIES}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.ENTRIES}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.MEMORY_READ_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.MEMORY_READ_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.FETCH_WAYS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.FETCH_WAYS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.REG_FILE_WRITE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.REG_FILE_WRITE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.WRITEBACK_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.WRITEBACK_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.MEMORY_WRITE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.MEMORY_WRITE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.EXEC_UNITS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.dris.EXEC_UNITS}

set _wave_session_group_3 ssc_1
if {[gui_sg_is_group -name "$_wave_session_group_3"]} {
    set _wave_session_group_3 [gui_sg_generate_new_name]
}
set Group3 "$_wave_session_group_3"

gui_sg_addsignal -group "$_wave_session_group_3" { {Sim:top.RISCV_Core_interface.core_inst.ssc.trap_pc} {Sim:top.RISCV_Core_interface.core_inst.ssc.d_cache_ready} {Sim:top.RISCV_Core_interface.core_inst.ssc.store_ready} {Sim:top.RISCV_Core_interface.core_inst.ssc.retire_ptr} {Sim:top.RISCV_Core_interface.core_inst.ssc.oldest_branch_id} {Sim:top.RISCV_Core_interface.core_inst.ssc.clock} {Sim:top.RISCV_Core_interface.core_inst.ssc.reg_commits} {Sim:top.RISCV_Core_interface.core_inst.ssc.flush_vector} {Sim:top.RISCV_Core_interface.core_inst.ssc.retire_vector} {Sim:top.RISCV_Core_interface.core_inst.ssc.flush_mask} {Sim:top.RISCV_Core_interface.core_inst.ssc.store_id} {Sim:top.RISCV_Core_interface.core_inst.ssc.dris_entries} {Sim:top.RISCV_Core_interface.core_inst.ssc.trap_valid} {Sim:top.RISCV_Core_interface.core_inst.ssc.reset_n} {Sim:top.RISCV_Core_interface.core_inst.ssc.REG_FILE_WRITE_PORTS} {Sim:top.RISCV_Core_interface.core_inst.ssc.retire_ready_vector} {Sim:top.RISCV_Core_interface.core_inst.ssc.RETIRES_PER_CYCLE} {Sim:top.RISCV_Core_interface.core_inst.ssc.entries_checked} {Sim:top.RISCV_Core_interface.core_inst.ssc.MEMORY_WRITE_PORTS} {Sim:top.RISCV_Core_interface.core_inst.ssc.branch_fence_valid} {Sim:top.RISCV_Core_interface.core_inst.ssc.REG_RETIRES_PER_CYCLE} {Sim:top.RISCV_Core_interface.core_inst.ssc.$unit} {Sim:top.RISCV_Core_interface.core_inst.ssc.MEMORY_RETIRES_PER_CYCLE} {Sim:top.RISCV_Core_interface.core_inst.ssc.trap_id} }
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.REG_FILE_WRITE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.REG_FILE_WRITE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.RETIRES_PER_CYCLE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.RETIRES_PER_CYCLE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.MEMORY_WRITE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.MEMORY_WRITE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.REG_RETIRES_PER_CYCLE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.REG_RETIRES_PER_CYCLE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.MEMORY_RETIRES_PER_CYCLE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.ssc.MEMORY_RETIRES_PER_CYCLE}

set _wave_session_group_4 tony_d_1
if {[gui_sg_is_group -name "$_wave_session_group_4"]} {
    set _wave_session_group_4 [gui_sg_generate_new_name]
}
set Group4 "$_wave_session_group_4"

gui_sg_addsignal -group "$_wave_session_group_4" { {Sim:top.RISCV_Core_interface.tony_d.unnamed$$_0} {Sim:top.RISCV_Core_interface.tony_d.core_req_stall_mem} {Sim:top.RISCV_Core_interface.tony_d.POLICY} {Sim:top.RISCV_Core_interface.tony_d.do_evict_writeback} {Sim:top.RISCV_Core_interface.tony_d.core_req_bus_wait_en} {Sim:top.RISCV_Core_interface.tony_d.wr_en} {Sim:top.RISCV_Core_interface.tony_d.cache_store} {Sim:top.RISCV_Core_interface.tony_d.cache_fill_data} {Sim:top.RISCV_Core_interface.tony_d.core_rsp_ready} {Sim:top.RISCV_Core_interface.tony_d.use_latched_addr} {Sim:top.RISCV_Core_interface.tony_d.core_rsp_ctrl_signals} {Sim:top.RISCV_Core_interface.tony_d.latch_old_word_fill} {Sim:top.RISCV_Core_interface.tony_d.stall} {Sim:top.RISCV_Core_interface.tony_d.mem_rsp_good} {Sim:top.RISCV_Core_interface.tony_d.evicted_line} {Sim:top.RISCV_Core_interface.tony_d.old_word_latched} {Sim:top.RISCV_Core_interface.tony_d.mem_rsp_data} {Sim:top.RISCV_Core_interface.tony_d.core_rsp_data_valid} {Sim:top.RISCV_Core_interface.tony_d.do_forward} {Sim:top.RISCV_Core_interface.tony_d.clk} {Sim:top.RISCV_Core_interface.tony_d.fwd_words} {Sim:top.RISCV_Core_interface.tony_d.core_rsp_id} {Sim:top.RISCV_Core_interface.tony_d.cache_fill_valid} {Sim:top.RISCV_Core_interface.tony_d.rsp_words} {Sim:top.RISCV_Core_interface.tony_d.INDEX_BITS} {Sim:top.RISCV_Core_interface.tony_d.wb_pending} {Sim:top.RISCV_Core_interface.tony_d.read_miss} {Sim:top.RISCV_Core_interface.tony_d.read_data} {Sim:top.RISCV_Core_interface.tony_d.core_req_store_data} {Sim:top.RISCV_Core_interface.tony_d.core_req_id_latched} {Sim:top.RISCV_Core_interface.tony_d.core_rsp_data} {Sim:top.RISCV_Core_interface.tony_d.rst_l} {Sim:top.RISCV_Core_interface.tony_d.cache_wr_valid} {Sim:top.RISCV_Core_interface.tony_d.mem_rsp_ready} {Sim:top.RISCV_Core_interface.tony_d.state} {Sim:top.RISCV_Core_interface.tony_d.core_req_id} {Sim:top.RISCV_Core_interface.tony_d.cache_stall} {Sim:top.RISCV_Core_interface.tony_d.ADDRESS_SIZE} {Sim:top.RISCV_Core_interface.tony_d.core_req_store_mask} {Sim:top.RISCV_Core_interface.tony_d.evicted_dirty} {Sim:top.RISCV_Core_interface.tony_d.mem_req_store_data} {Sim:top.RISCV_Core_interface.tony_d.evicted_addr_latched} {Sim:top.RISCV_Core_interface.tony_d.do_fill} {Sim:top.RISCV_Core_interface.tony_d.core_req_cancel} {Sim:top.RISCV_Core_interface.tony_d.WAYS} {Sim:top.RISCV_Core_interface.tony_d.address} {Sim:top.RISCV_Core_interface.tony_d.read_hit} {Sim:top.RISCV_Core_interface.tony_d.latch_old_word_hit} {Sim:top.RISCV_Core_interface.tony_d.is_eviction} {Sim:top.RISCV_Core_interface.tony_d.fwd_pending} {Sim:top.RISCV_Core_interface.tony_d.cancel} {Sim:top.RISCV_Core_interface.tony_d.mem_req_store_mask} {Sim:top.RISCV_Core_interface.tony_d.mem_rsp_addr} {Sim:top.RISCV_Core_interface.tony_d.do_forward_saved} {Sim:top.RISCV_Core_interface.tony_d.BLOCK_OFFSET_BITS} {Sim:top.RISCV_Core_interface.tony_d.mem_bus_request} {Sim:top.RISCV_Core_interface.tony_d.core_req_addr_latched} {Sim:top.RISCV_Core_interface.tony_d.rd_en} {Sim:top.RISCV_Core_interface.tony_d.evicted_line_latched} {Sim:top.RISCV_Core_interface.tony_d.merged_store_word} {Sim:top.RISCV_Core_interface.tony_d.core_req_we} {Sim:top.RISCV_Core_interface.tony_d.wb_beat} {Sim:top.RISCV_Core_interface.tony_d.core_hit_valid} {Sim:top.RISCV_Core_interface.tony_d.core_rsp_excpt} {Sim:top.RISCV_Core_interface.tony_d.WORD_SIZE} {Sim:top.RISCV_Core_interface.tony_d.core_req_store_mask_latched} {Sim:top.RISCV_Core_interface.tony_d.core_rsp_addr} {Sim:top.RISCV_Core_interface.tony_d.cache_issue_read} {Sim:top.RISCV_Core_interface.tony_d.fifo_enable} {Sim:top.RISCV_Core_interface.tony_d.mem_rsp_valid} {Sim:top.RISCV_Core_interface.tony_d.mem_req_addr} {Sim:top.RISCV_Core_interface.tony_d.core_req_ctrl_signals_latched} {Sim:top.RISCV_Core_interface.tony_d.mem_req_data_load_en} {Sim:top.RISCV_Core_interface.tony_d.evicted_addr} {Sim:top.RISCV_Core_interface.tony_d.cache_wr_word} {Sim:top.RISCV_Core_interface.tony_d.core_req_re} {Sim:top.RISCV_Core_interface.tony_d.core_req_store_data_latched} }
gui_sg_addsignal -group "$_wave_session_group_4" { {Sim:top.RISCV_Core_interface.tony_d.FETCH_WORDS} {Sim:top.RISCV_Core_interface.tony_d.ud_en} {Sim:top.RISCV_Core_interface.tony_d.next_state} {Sim:top.RISCV_Core_interface.tony_d.fifo_data} {Sim:top.RISCV_Core_interface.tony_d.core_req_ctrl_signals} {Sim:top.RISCV_Core_interface.tony_d.$unit} {Sim:top.RISCV_Core_interface.tony_d.flush} {Sim:top.RISCV_Core_interface.tony_d.BLOCK_SIZE} {Sim:top.RISCV_Core_interface.tony_d.core_req_addr} {Sim:top.RISCV_Core_interface.tony_d.mem_rsp_excpt} }
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.tony_d.POLICY}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.tony_d.POLICY}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.tony_d.INDEX_BITS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.tony_d.INDEX_BITS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.tony_d.ADDRESS_SIZE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.tony_d.ADDRESS_SIZE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.tony_d.WAYS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.tony_d.WAYS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.tony_d.BLOCK_OFFSET_BITS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.tony_d.BLOCK_OFFSET_BITS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.tony_d.WORD_SIZE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.tony_d.WORD_SIZE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.tony_d.FETCH_WORDS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.tony_d.FETCH_WORDS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.tony_d.BLOCK_SIZE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.tony_d.BLOCK_SIZE}

set _wave_session_group_5 Group1
if {[gui_sg_is_group -name "$_wave_session_group_5"]} {
    set _wave_session_group_5 [gui_sg_generate_new_name]
}
set Group5 "$_wave_session_group_5"

gui_sg_addsignal -group "$_wave_session_group_5" { {Sim:top.cycle_count} {Sim:top.commit_pkts} }
gui_set_radix -radix {decimal} -signals {Sim:top.cycle_count}
gui_set_radix -radix {twosComplement} -signals {Sim:top.cycle_count}

set _wave_session_group_6 iiu
if {[gui_sg_is_group -name "$_wave_session_group_6"]} {
    set _wave_session_group_6 [gui_sg_generate_new_name]
}
set Group6 "$_wave_session_group_6"

gui_sg_addsignal -group "$_wave_session_group_6" { {Sim:top.RISCV_Core_interface.core_inst.iiu.shelf_free_count} {Sim:top.RISCV_Core_interface.core_inst.iiu.next_pc} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_req_stall_mem} {Sim:top.RISCV_Core_interface.core_inst.iiu.intake_stall} {Sim:top.RISCV_Core_interface.core_inst.iiu.mispredict_branch_id} {Sim:top.RISCV_Core_interface.core_inst.iiu.fetch_ptr} {Sim:top.RISCV_Core_interface.core_inst.iiu.redirect} {Sim:top.RISCV_Core_interface.core_inst.iiu.trap_valid} {Sim:top.RISCV_Core_interface.core_inst.iiu.trap_pc} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_rsp_ready} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_ctrl} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_rsp_data_valid} {Sim:top.RISCV_Core_interface.core_inst.iiu.shelf_in_pkt} {Sim:top.RISCV_Core_interface.core_inst.iiu.primary_ct_found} {Sim:top.RISCV_Core_interface.core_inst.iiu.clock} {Sim:top.RISCV_Core_interface.core_inst.iiu.words_left} {Sim:top.RISCV_Core_interface.core_inst.iiu.retire_ptr} {Sim:top.RISCV_Core_interface.core_inst.iiu.btb_write_ctrl} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_rsp_data} {Sim:top.RISCV_Core_interface.core_inst.iiu.btb_train} {Sim:top.RISCV_Core_interface.core_inst.iiu.ct_resume_pc} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_rs1} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_rs2} {Sim:top.RISCV_Core_interface.core_inst.iiu.ADDRESS_SIZE} {Sim:top.RISCV_Core_interface.core_inst.iiu.shelf_room} {Sim:top.RISCV_Core_interface.core_inst.iiu.grab} {Sim:top.RISCV_Core_interface.core_inst.iiu.btb_read_hist} {Sim:top.RISCV_Core_interface.core_inst.iiu.NUM_UPDATE_PORTS} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_req_cancel} {Sim:top.RISCV_Core_interface.core_inst.iiu.mispredict_pc} {Sim:top.RISCV_Core_interface.core_inst.iiu.ct_count} {Sim:top.RISCV_Core_interface.core_inst.iiu.mispredict_valid} {Sim:top.RISCV_Core_interface.core_inst.iiu.primary_ct_slot} {Sim:top.RISCV_Core_interface.core_inst.iiu.seq_next_fetch} {Sim:top.RISCV_Core_interface.core_inst.iiu.dris_entries} {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_OFFSET_BITS} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_pc} {Sim:top.RISCV_Core_interface.core_inst.iiu.ct_redirect_pend} {Sim:top.RISCV_Core_interface.core_inst.iiu.reset_n} {Sim:top.RISCV_Core_interface.core_inst.iiu.ct_redirect} {Sim:top.RISCV_Core_interface.core_inst.iiu.issue_fire} {Sim:top.RISCV_Core_interface.core_inst.iiu.btb_predicted_pc} {Sim:top.RISCV_Core_interface.core_inst.iiu.shelf_alloc_valid} {Sim:top.RISCV_Core_interface.core_inst.iiu.flush_mask} {Sim:top.RISCV_Core_interface.core_inst.iiu.group_has_ct} {Sim:top.RISCV_Core_interface.core_inst.iiu.group_count} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_rsp_excpt} {Sim:top.RISCV_Core_interface.core_inst.iiu.cut} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_rsp_addr} {Sim:top.RISCV_Core_interface.core_inst.iiu.occupancy} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_valid} {Sim:top.RISCV_Core_interface.core_inst.iiu.oldest_branch_id} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_imm} {Sim:top.RISCV_Core_interface.core_inst.iiu.CT_PER_GROUP_MAX} {Sim:top.RISCV_Core_interface.core_inst.iiu.pc_F} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_is_ct} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_req_re} {Sim:top.RISCV_Core_interface.core_inst.iiu.FETCH_WORDS} {Sim:top.RISCV_Core_interface.core_inst.iiu.redirect_pc} {Sim:top.RISCV_Core_interface.core_inst.iiu.dris_intake_pkts} {Sim:top.RISCV_Core_interface.core_inst.iiu.avail} {Sim:top.RISCV_Core_interface.core_inst.iiu.$unit} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_pred_pc} {Sim:top.RISCV_Core_interface.core_inst.iiu.slot_rd} {Sim:top.RISCV_Core_interface.core_inst.iiu.update_bus} {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_SIZE} {Sim:top.RISCV_Core_interface.core_inst.iiu.branch_fence_valid} {Sim:top.RISCV_Core_interface.core_inst.iiu.core_req_addr} {Sim:top.RISCV_Core_interface.core_inst.iiu.dris_room} }
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.ADDRESS_SIZE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.ADDRESS_SIZE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.NUM_UPDATE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.NUM_UPDATE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_OFFSET_BITS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_OFFSET_BITS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.CT_PER_GROUP_MAX}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.CT_PER_GROUP_MAX}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.FETCH_WORDS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.FETCH_WORDS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_SIZE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_SIZE}

set _wave_session_group_7 scheduler
if {[gui_sg_is_group -name "$_wave_session_group_7"]} {
    set _wave_session_group_7 [gui_sg_generate_new_name]
}
set Group7 "$_wave_session_group_7"

gui_sg_addsignal -group "$_wave_session_group_7" { {Sim:top.RISCV_Core_interface.core_inst.scheduler.sel_idx} {Sim:top.RISCV_Core_interface.core_inst.scheduler.issue_count} {Sim:top.RISCV_Core_interface.core_inst.scheduler.retire_ptr} {Sim:top.RISCV_Core_interface.core_inst.scheduler.clock} {Sim:top.RISCV_Core_interface.core_inst.scheduler.rs1_data_intermed} {Sim:top.RISCV_Core_interface.core_inst.scheduler.sel_entries} {Sim:top.RISCV_Core_interface.core_inst.scheduler.sel_valid} {Sim:top.RISCV_Core_interface.core_inst.scheduler.operand_1} {Sim:top.RISCV_Core_interface.core_inst.scheduler.operand_2} {Sim:top.RISCV_Core_interface.core_inst.scheduler.dris_entries} {Sim:top.RISCV_Core_interface.core_inst.scheduler.ready_vector} {Sim:top.RISCV_Core_interface.core_inst.scheduler.set_dispatched} {Sim:top.RISCV_Core_interface.core_inst.scheduler.rs2_data} {Sim:top.RISCV_Core_interface.core_inst.scheduler.rs2_addr} {Sim:top.RISCV_Core_interface.core_inst.scheduler.issue_pkts} {Sim:top.RISCV_Core_interface.core_inst.scheduler.read_rf} {Sim:top.RISCV_Core_interface.core_inst.scheduler.reset_n} {Sim:top.RISCV_Core_interface.core_inst.scheduler.REG_FILE_WRITE_PORTS} {Sim:top.RISCV_Core_interface.core_inst.scheduler.ENTRIES_CHECKED} {Sim:top.RISCV_Core_interface.core_inst.scheduler.entries_checked} {Sim:top.RISCV_Core_interface.core_inst.scheduler.rs1_data} {Sim:top.RISCV_Core_interface.core_inst.scheduler.MEMORY_WRITE_PORTS} {Sim:top.RISCV_Core_interface.core_inst.scheduler.operand_source_entries} {Sim:top.RISCV_Core_interface.core_inst.scheduler.rs1_addr} {Sim:top.RISCV_Core_interface.core_inst.scheduler.$unit} {Sim:top.RISCV_Core_interface.core_inst.scheduler.EXEC_UNITS} }
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.issue_count}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.issue_count}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.REG_FILE_WRITE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.REG_FILE_WRITE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.ENTRIES_CHECKED}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.ENTRIES_CHECKED}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.MEMORY_WRITE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.MEMORY_WRITE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.EXEC_UNITS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.EXEC_UNITS}
if {![info exists useOldWindow]} { 
	set useOldWindow true
}
if {$useOldWindow && [string first "Wave" [gui_get_current_window -view]]==0} { 
	set Wave.1 [gui_get_current_window -view] 
} else {
	set Wave.1 [lindex [gui_get_window_ids -type Wave] 0]
if {[string first "Wave" ${Wave.1}]!=0} {
gui_open_window Wave
set Wave.1 [ gui_get_current_window -view ]
}
}

set groupExD [gui_get_pref_value -category Wave -key exclusiveSG]
gui_set_pref_value -category Wave -key exclusiveSG -value {false}
set origWaveHeight [gui_get_pref_value -category Wave -key waveRowHeight]
gui_list_set_height -id Wave -height 25
set origGroupCreationState [gui_list_create_group_when_add -wave]
gui_list_create_group_when_add -wave -disable
gui_marker_set_ref -id ${Wave.1}  C1
gui_wv_zoom_timerange -id ${Wave.1} 315545 316255
gui_list_add_group -id ${Wave.1} -after {New Group} [list ${Group1}]
gui_list_add_group -id ${Wave.1} -after {New Group} [list ${Group2}]
gui_list_add_group -id ${Wave.1} -after {New Group} [list ${Group3}]
gui_list_add_group -id ${Wave.1} -after {New Group} [list ${Group4}]
gui_list_add_group -id ${Wave.1} -after {New Group} [list ${Group5}]
gui_list_add_group -id ${Wave.1} -after {New Group} [list ${Group6}]
gui_list_add_group -id ${Wave.1} -after {New Group} [list ${Group7}]
gui_list_collapse -id ${Wave.1} ${Group1}
gui_list_collapse -id ${Wave.1} ${Group6}
gui_list_expand -id ${Wave.1} top.RISCV_Core_interface.core_inst.dris.dris_entries
gui_list_expand -id ${Wave.1} {top.RISCV_Core_interface.core_inst.dris.dris_entries[0]}
gui_list_expand -id ${Wave.1} top.RISCV_Core_interface.core_inst.ssc.store_id
gui_list_expand -id ${Wave.1} top.RISCV_Core_interface.core_inst.scheduler.issue_pkts
gui_list_expand -id ${Wave.1} {top.RISCV_Core_interface.core_inst.scheduler.issue_pkts[0]}
gui_list_select -id ${Wave.1} {{top.RISCV_Core_interface.core_inst.dris.dris_entries[0].pc} }
gui_seek_criteria -id ${Wave.1} {Value...}


gui_set_pref_value -category Wave -key exclusiveSG -value $groupExD
gui_list_set_height -id Wave -height $origWaveHeight
if {$origGroupCreationState} {
	gui_list_create_group_when_add -wave -enable
}
if { $groupExD } {
 gui_msg_report -code DVWW028
}
gui_list_set_filter -id ${Wave.1} -list { {Buffer 1} {Input 1} {Others 1} {Linkage 1} {Output 1} {Parameter 1} {All 1} {Aggregate 1} {LibBaseMember 1} {Event 1} {Assertion 1} {Constant 1} {Interface 1} {BaseMembers 1} {Signal 1} {$unit 1} {Inout 1} {Variable 1} }
gui_list_set_filter -id ${Wave.1} -text {*}
gui_list_set_insertion_bar  -id ${Wave.1} -group ${Group7}  -position in

gui_marker_move -id ${Wave.1} {C1} 315800
gui_view_scroll -id ${Wave.1} -vertical -set 168
gui_show_grid -id ${Wave.1} -enable false
#</Session>

