# Begin_DVE_Session_Save_Info
# DVE full session
# Saved on Mon Aug 3 15:29:45 2026
# Designs open: 1
#   Sim: sim
# Toplevel windows open: 2
# 	TopLevel.1
# 	TopLevel.2
#   Source.1: top.CommitVerifier
#   Wave.1: 219 signals
#   Group count = 8
#   Group core_inst signal count = 82
#   Group dris signal count = 26
#   Group ssc signal count = 24
#   Group tony_d signal count = 87
#   Group core_inst_1 signal count = 82
#   Group dris_1 signal count = 26
#   Group ssc_1 signal count = 24
#   Group tony_d_1 signal count = 87
# End_DVE_Session_Save_Info

# DVE version: T-2022.06_Full64
# DVE build date: May 31 2022 20:53:03


#<Session mode="Full" path="/afs/ece.cmu.edu/usr/daniello/Private/riscv-metaflow-lightning/memtest2drissizedebugAAAAAAAAA.tcl" type="Debug">

gui_set_loading_session_type Post
gui_continuetime_set

# Close design
if { [gui_sim_state -check active] } {
    gui_sim_terminate
}
gui_close_db -all
gui_expr_clear_all

# Close all windows
gui_close_window -type Console
gui_close_window -type Wave
gui_close_window -type Source
gui_close_window -type Schematic
gui_close_window -type Data
gui_close_window -type DriverLoad
gui_close_window -type List
gui_close_window -type Memory
gui_close_window -type HSPane
gui_close_window -type DLPane
gui_close_window -type Assertion
gui_close_window -type CovHier
gui_close_window -type CoverageTable
gui_close_window -type CoverageMap
gui_close_window -type CovDetail
gui_close_window -type Local
gui_close_window -type Stack
gui_close_window -type Watch
gui_close_window -type Group
gui_close_window -type Transaction



# Application preferences
gui_set_pref_value -key app_default_font -value {Helvetica,10,-1,5,50,0,0,0,0,0}
gui_src_preferences -tabstop 8 -maxbits 24 -windownumber 1
#<WindowLayout>

# DVE top-level session


# Create and position top-level window: TopLevel.1

if {![gui_exist_window -window TopLevel.1]} {
    set TopLevel.1 [ gui_create_window -type TopLevel \
       -icon $::env(DVE)/auxx/gui/images/toolbars/dvewin.xpm] 
} else { 
    set TopLevel.1 TopLevel.1
}
gui_show_window -window ${TopLevel.1} -show_state normal -rect {{769 31} {1532 908}}

# ToolBar settings
gui_set_toolbar_attributes -toolbar {TimeOperations} -dock_state top
gui_set_toolbar_attributes -toolbar {TimeOperations} -offset 0
gui_show_toolbar -toolbar {TimeOperations}
gui_hide_toolbar -toolbar {&File}
gui_set_toolbar_attributes -toolbar {&Edit} -dock_state top
gui_set_toolbar_attributes -toolbar {&Edit} -offset 0
gui_show_toolbar -toolbar {&Edit}
gui_hide_toolbar -toolbar {CopyPaste}
gui_set_toolbar_attributes -toolbar {&Trace} -dock_state top
gui_set_toolbar_attributes -toolbar {&Trace} -offset 0
gui_show_toolbar -toolbar {&Trace}
gui_hide_toolbar -toolbar {TraceInstance}
gui_hide_toolbar -toolbar {BackTrace}
gui_set_toolbar_attributes -toolbar {&Scope} -dock_state top
gui_set_toolbar_attributes -toolbar {&Scope} -offset 0
gui_show_toolbar -toolbar {&Scope}
gui_set_toolbar_attributes -toolbar {&Window} -dock_state top
gui_set_toolbar_attributes -toolbar {&Window} -offset 0
gui_show_toolbar -toolbar {&Window}
gui_set_toolbar_attributes -toolbar {Signal} -dock_state top
gui_set_toolbar_attributes -toolbar {Signal} -offset 0
gui_show_toolbar -toolbar {Signal}
gui_set_toolbar_attributes -toolbar {Zoom} -dock_state top
gui_set_toolbar_attributes -toolbar {Zoom} -offset 0
gui_show_toolbar -toolbar {Zoom}
gui_set_toolbar_attributes -toolbar {Zoom And Pan History} -dock_state top
gui_set_toolbar_attributes -toolbar {Zoom And Pan History} -offset 0
gui_show_toolbar -toolbar {Zoom And Pan History}
gui_set_toolbar_attributes -toolbar {Grid} -dock_state top
gui_set_toolbar_attributes -toolbar {Grid} -offset 0
gui_show_toolbar -toolbar {Grid}
gui_set_toolbar_attributes -toolbar {Simulator} -dock_state top
gui_set_toolbar_attributes -toolbar {Simulator} -offset 0
gui_show_toolbar -toolbar {Simulator}
gui_set_toolbar_attributes -toolbar {Interactive Rewind} -dock_state top
gui_set_toolbar_attributes -toolbar {Interactive Rewind} -offset 0
gui_show_toolbar -toolbar {Interactive Rewind}
gui_set_toolbar_attributes -toolbar {Testbench} -dock_state top
gui_set_toolbar_attributes -toolbar {Testbench} -offset 0
gui_show_toolbar -toolbar {Testbench}

# End ToolBar settings

# Docked window settings
set HSPane.1 [gui_create_window -type HSPane -parent ${TopLevel.1} -dock_state left -dock_on_new_line true -dock_extent 494]
catch { set Hier.1 [gui_share_window -id ${HSPane.1} -type Hier] }
catch { set Stack.1 [gui_share_window -id ${HSPane.1} -type Stack -silent] }
catch { set Class.1 [gui_share_window -id ${HSPane.1} -type Class -silent] }
catch { set Object.1 [gui_share_window -id ${HSPane.1} -type Object -silent] }
gui_set_window_pref_key -window ${HSPane.1} -key dock_width -value_type integer -value 494
gui_set_window_pref_key -window ${HSPane.1} -key dock_height -value_type integer -value -1
gui_set_window_pref_key -window ${HSPane.1} -key dock_offset -value_type integer -value 0
gui_update_layout -id ${HSPane.1} {{left 0} {top 0} {width 493} {height 552} {dock_state left} {dock_on_new_line true} {child_hier_colhier 370} {child_hier_coltype 141} {child_hier_colpd 0} {child_hier_col1 0} {child_hier_col2 1} {child_hier_col3 -1}}
set DLPane.1 [gui_create_window -type DLPane -parent ${TopLevel.1} -dock_state left -dock_on_new_line true -dock_extent 297]
catch { set Data.1 [gui_share_window -id ${DLPane.1} -type Data] }
catch { set Local.1 [gui_share_window -id ${DLPane.1} -type Local -silent] }
catch { set Member.1 [gui_share_window -id ${DLPane.1} -type Member -silent] }
gui_set_window_pref_key -window ${DLPane.1} -key dock_width -value_type integer -value 297
gui_set_window_pref_key -window ${DLPane.1} -key dock_height -value_type integer -value 576
gui_set_window_pref_key -window ${DLPane.1} -key dock_offset -value_type integer -value 0
gui_update_layout -id ${DLPane.1} {{left 0} {top 0} {width 296} {height 552} {dock_state left} {dock_on_new_line true} {child_data_colvariable 369} {child_data_colvalue 288} {child_data_coltype 285} {child_data_col1 0} {child_data_col2 1} {child_data_col3 2}}
set Console.1 [gui_create_window -type Console -parent ${TopLevel.1} -dock_state bottom -dock_on_new_line true -dock_extent 179]
gui_set_window_pref_key -window ${Console.1} -key dock_width -value_type integer -value 764
gui_set_window_pref_key -window ${Console.1} -key dock_height -value_type integer -value 179
gui_set_window_pref_key -window ${Console.1} -key dock_offset -value_type integer -value 0
gui_update_layout -id ${Console.1} {{left 0} {top 0} {width 763} {height 178} {dock_state bottom} {dock_on_new_line true}}
#### Start - Readjusting docked view's offset / size
set dockAreaList { top left right bottom }
foreach dockArea $dockAreaList {
  set viewList [gui_ekki_get_window_ids -active_parent -dock_area $dockArea]
  foreach view $viewList {
      if {[lsearch -exact [gui_get_window_pref_keys -window $view] dock_width] != -1} {
        set dockWidth [gui_get_window_pref_value -window $view -key dock_width]
        set dockHeight [gui_get_window_pref_value -window $view -key dock_height]
        set offset [gui_get_window_pref_value -window $view -key dock_offset]
        if { [string equal "top" $dockArea] || [string equal "bottom" $dockArea]} {
          gui_set_window_attributes -window $view -dock_offset $offset -width $dockWidth
        } else {
          gui_set_window_attributes -window $view -dock_offset $offset -height $dockHeight
        }
      }
  }
}
#### End - Readjusting docked view's offset / size
gui_sync_global -id ${TopLevel.1} -option true

# MDI window settings
set Source.1 [gui_create_window -type {Source}  -parent ${TopLevel.1}]
gui_show_window -window ${Source.1} -show_state maximized
gui_update_layout -id ${Source.1} {{show_state maximized} {dock_state undocked} {dock_on_new_line false}}

# End MDI window settings


# Create and position top-level window: TopLevel.2

if {![gui_exist_window -window TopLevel.2]} {
    set TopLevel.2 [ gui_create_window -type TopLevel \
       -icon $::env(DVE)/auxx/gui/images/toolbars/dvewin.xpm] 
} else { 
    set TopLevel.2 TopLevel.2
}
gui_show_window -window ${TopLevel.2} -show_state maximized -rect {{0 23} {1535 911}}

# ToolBar settings
gui_set_toolbar_attributes -toolbar {TimeOperations} -dock_state top
gui_set_toolbar_attributes -toolbar {TimeOperations} -offset 0
gui_show_toolbar -toolbar {TimeOperations}
gui_hide_toolbar -toolbar {&File}
gui_set_toolbar_attributes -toolbar {&Edit} -dock_state top
gui_set_toolbar_attributes -toolbar {&Edit} -offset 0
gui_show_toolbar -toolbar {&Edit}
gui_hide_toolbar -toolbar {CopyPaste}
gui_set_toolbar_attributes -toolbar {&Trace} -dock_state top
gui_set_toolbar_attributes -toolbar {&Trace} -offset 0
gui_show_toolbar -toolbar {&Trace}
gui_hide_toolbar -toolbar {TraceInstance}
gui_hide_toolbar -toolbar {BackTrace}
gui_set_toolbar_attributes -toolbar {&Scope} -dock_state top
gui_set_toolbar_attributes -toolbar {&Scope} -offset 0
gui_show_toolbar -toolbar {&Scope}
gui_set_toolbar_attributes -toolbar {&Window} -dock_state top
gui_set_toolbar_attributes -toolbar {&Window} -offset 0
gui_show_toolbar -toolbar {&Window}
gui_set_toolbar_attributes -toolbar {Signal} -dock_state top
gui_set_toolbar_attributes -toolbar {Signal} -offset 0
gui_show_toolbar -toolbar {Signal}
gui_set_toolbar_attributes -toolbar {Zoom} -dock_state top
gui_set_toolbar_attributes -toolbar {Zoom} -offset 0
gui_show_toolbar -toolbar {Zoom}
gui_set_toolbar_attributes -toolbar {Zoom And Pan History} -dock_state top
gui_set_toolbar_attributes -toolbar {Zoom And Pan History} -offset 0
gui_show_toolbar -toolbar {Zoom And Pan History}
gui_set_toolbar_attributes -toolbar {Grid} -dock_state top
gui_set_toolbar_attributes -toolbar {Grid} -offset 0
gui_show_toolbar -toolbar {Grid}
gui_set_toolbar_attributes -toolbar {Simulator} -dock_state top
gui_set_toolbar_attributes -toolbar {Simulator} -offset 0
gui_show_toolbar -toolbar {Simulator}
gui_set_toolbar_attributes -toolbar {Interactive Rewind} -dock_state top
gui_set_toolbar_attributes -toolbar {Interactive Rewind} -offset 0
gui_show_toolbar -toolbar {Interactive Rewind}
gui_set_toolbar_attributes -toolbar {Testbench} -dock_state top
gui_set_toolbar_attributes -toolbar {Testbench} -offset 0
gui_show_toolbar -toolbar {Testbench}

# End ToolBar settings

# Docked window settings
gui_sync_global -id ${TopLevel.2} -option true

# MDI window settings
set Wave.1 [gui_create_window -type {Wave}  -parent ${TopLevel.2}]
gui_show_window -window ${Wave.1} -show_state maximized
gui_update_layout -id ${Wave.1} {{show_state maximized} {dock_state undocked} {dock_on_new_line false} {child_wave_left 445} {child_wave_right 1085} {child_wave_colname 215} {child_wave_colvalue 226} {child_wave_col1 0} {child_wave_col2 1}}

# End MDI window settings

gui_set_env TOPLEVELS::TARGET_FRAME(Source) ${TopLevel.1}
gui_set_env TOPLEVELS::TARGET_FRAME(Schematic) ${TopLevel.1}
gui_set_env TOPLEVELS::TARGET_FRAME(PathSchematic) ${TopLevel.1}
gui_set_env TOPLEVELS::TARGET_FRAME(Wave) none
gui_set_env TOPLEVELS::TARGET_FRAME(List) none
gui_set_env TOPLEVELS::TARGET_FRAME(Memory) ${TopLevel.1}
gui_set_env TOPLEVELS::TARGET_FRAME(DriverLoad) none
gui_update_statusbar_target_frame ${TopLevel.1}
gui_update_statusbar_target_frame ${TopLevel.2}

#</WindowLayout>

#<Database>

# DVE Open design session: 

if { [llength [lindex [gui_get_db -design Sim] 0]] == 0 } {
gui_set_env SIMSETUP::SIMARGS {{}}
gui_set_env SIMSETUP::SIMEXE {./sim}
gui_set_env SIMSETUP::ALLOW_POLL {0}
if { ![gui_is_db_opened -db {sim}] } {
gui_sim_run Ucli -exe sim -args { -ucligui} -dir ../vcs -nosource
}
}
if { ![gui_sim_state -check active] } {error "Simulator did not start correctly" error}
gui_set_precision 1s
gui_set_time_units 1s
#</Database>

# DVE Global setting session: 


# Global: Breakpoints

# Global: Bus

# Global: Expressions

# Global: Signal Time Shift

# Global: Signal Compare

# Global: Signal Groups
gui_load_child_values {top.RISCV_Core_interface.tony_d}
gui_load_child_values {top.RISCV_Core_interface.core_inst.dris}
gui_load_child_values {top.RISCV_Core_interface.core_inst.ssc}
gui_load_child_values {top.RISCV_Core_interface.core_inst}


set _session_group_1 core_inst
gui_sg_create "$_session_group_1"
set core_inst "$_session_group_1"

gui_sg_addsignal -group "$_session_group_1" { top.RISCV_Core_interface.core_inst.core_req_stall_mem top.RISCV_Core_interface.core_inst.fetch_pkts top.RISCV_Core_interface.core_inst.commit_pkts top.RISCV_Core_interface.core_inst.flush_vector top.RISCV_Core_interface.core_inst.core_rsp_ready_d top.RISCV_Core_interface.core_inst.RF_WAYS top.RISCV_Core_interface.core_inst.issue_pkts_reg top.RISCV_Core_interface.core_inst.fetch_ptr top.RISCV_Core_interface.core_inst.core_req_we_d top.RISCV_Core_interface.core_inst.trap_valid top.RISCV_Core_interface.core_inst.core_req_id_d top.RISCV_Core_interface.core_inst.mem_rs2_data top.RISCV_Core_interface.core_inst.trap_pc top.RISCV_Core_interface.core_inst.core_rsp_data_valid_d top.RISCV_Core_interface.core_inst.core_rsp_ready top.RISCV_Core_interface.core_inst.retire_vector top.RISCV_Core_interface.core_inst.rf_commit_valid top.RISCV_Core_interface.core_inst.core_rsp_ctrl_signals_d top.RISCV_Core_interface.core_inst.rf_we top.RISCV_Core_interface.core_inst.core_rsp_data_valid top.RISCV_Core_interface.core_inst.core_rsp_data_d top.RISCV_Core_interface.core_inst.sched_rs2_addr top.RISCV_Core_interface.core_inst.clock top.RISCV_Core_interface.core_inst.MEM_ISSUE_WAYS top.RISCV_Core_interface.core_inst.store_ready top.RISCV_Core_interface.core_inst.rf_commit_pc top.RISCV_Core_interface.core_inst.retire_ptr top.RISCV_Core_interface.core_inst.sched_rs1_data top.RISCV_Core_interface.core_inst.rf_rd_data top.RISCV_Core_interface.core_inst.writeback_pkts top.RISCV_Core_interface.core_inst.core_req_re_d top.RISCV_Core_interface.core_inst.halted top.RISCV_Core_interface.core_inst.core_rsp_data top.RISCV_Core_interface.core_inst.rf_rd top.RISCV_Core_interface.core_inst.core_req_stall_mem_d top.RISCV_Core_interface.core_inst.rf_commit_pkts top.RISCV_Core_interface.core_inst.rf_rs1 top.RISCV_Core_interface.core_inst.rf_rs2 top.RISCV_Core_interface.core_inst.rf_rs1_data top.RISCV_Core_interface.core_inst.ADDRESS_SIZE top.RISCV_Core_interface.core_inst.mem_rs2_addr top.RISCV_Core_interface.core_inst.core_req_cancel top.RISCV_Core_interface.core_inst.sched_read_rf top.RISCV_Core_interface.core_inst.mem_rs1_data top.RISCV_Core_interface.core_inst.core_req_store_mask_d top.RISCV_Core_interface.core_inst.store_id top.RISCV_Core_interface.core_inst.RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.issue_pkts top.RISCV_Core_interface.core_inst.WRITEBACK_PORTS top.RISCV_Core_interface.core_inst.dris_entries top.RISCV_Core_interface.core_inst.reset_n top.RISCV_Core_interface.core_inst.rf_commit_insn top.RISCV_Core_interface.core_inst.mem_read_rf top.RISCV_Core_interface.core_inst.core_req_ctrl_signals_d top.RISCV_Core_interface.core_inst.sched_rs1_addr top.RISCV_Core_interface.core_inst.flush_mask top.RISCV_Core_interface.core_inst.core_rsp_addr_d top.RISCV_Core_interface.core_inst.core_req_cancel_d top.RISCV_Core_interface.core_inst.core_rsp_excpt top.RISCV_Core_interface.core_inst.core_rsp_excpt_d top.RISCV_Core_interface.core_inst.mem_issue_pkts top.RISCV_Core_interface.core_inst.core_rsp_addr top.RISCV_Core_interface.core_inst.oldest_branch_id top.RISCV_Core_interface.core_inst.d_granted top.RISCV_Core_interface.core_inst.core_req_addr_d top.RISCV_Core_interface.core_inst.sched_rs2_data top.RISCV_Core_interface.core_inst.core_req_re top.RISCV_Core_interface.core_inst.core_rsp_id_d top.RISCV_Core_interface.core_inst.FETCH_WORDS top.RISCV_Core_interface.core_inst.reg_commits top.RISCV_Core_interface.core_inst.dris_intake_pkts top.RISCV_Core_interface.core_inst.set_dispatched top.RISCV_Core_interface.core_inst.mem_rs1_addr top.RISCV_Core_interface.core_inst.EXEC_UNITS {top.RISCV_Core_interface.core_inst.$unit} top.RISCV_Core_interface.core_inst.update_bus top.RISCV_Core_interface.core_inst.set_dispatched_mem top.RISCV_Core_interface.core_inst.branch_fence_valid top.RISCV_Core_interface.core_inst.core_req_store_data_d top.RISCV_Core_interface.core_inst.core_req_addr top.RISCV_Core_interface.core_inst.trap_id top.RISCV_Core_interface.core_inst.rf_rs2_data }
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

set _session_group_2 dris
gui_sg_create "$_session_group_2"
set dris "$_session_group_2"

gui_sg_addsignal -group "$_session_group_2" { top.RISCV_Core_interface.core_inst.dris.ENTRIES top.RISCV_Core_interface.core_inst.dris.locker_1_comb top.RISCV_Core_interface.core_inst.dris.MEMORY_READ_PORTS top.RISCV_Core_interface.core_inst.dris.full_id_tmp top.RISCV_Core_interface.core_inst.dris.clock top.RISCV_Core_interface.core_inst.dris.clear_valid top.RISCV_Core_interface.core_inst.dris.dep1 top.RISCV_Core_interface.core_inst.dris.fetch_group_dep1_valid top.RISCV_Core_interface.core_inst.dris.dep2 top.RISCV_Core_interface.core_inst.dris.dris_entries top.RISCV_Core_interface.core_inst.dris.fetch_pkts top.RISCV_Core_interface.core_inst.dris.set_dispatched top.RISCV_Core_interface.core_inst.dris.FETCH_WAYS top.RISCV_Core_interface.core_inst.dris.reset_n top.RISCV_Core_interface.core_inst.dris.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.dris.locker_2_comb top.RISCV_Core_interface.core_inst.dris.WRITEBACK_PORTS top.RISCV_Core_interface.core_inst.dris.fetch_group_dep2_valid top.RISCV_Core_interface.core_inst.dris.new_ids top.RISCV_Core_interface.core_inst.dris.fetch_ptr top.RISCV_Core_interface.core_inst.dris.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.dris.writeback_pkts top.RISCV_Core_interface.core_inst.dris.dep2_completing_now top.RISCV_Core_interface.core_inst.dris.dep1_completing_now {top.RISCV_Core_interface.core_inst.dris.$unit} top.RISCV_Core_interface.core_inst.dris.EXEC_UNITS }
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

set _session_group_3 ssc
gui_sg_create "$_session_group_3"
set ssc "$_session_group_3"

gui_sg_addsignal -group "$_session_group_3" { top.RISCV_Core_interface.core_inst.ssc.trap_pc top.RISCV_Core_interface.core_inst.ssc.d_cache_ready top.RISCV_Core_interface.core_inst.ssc.store_ready top.RISCV_Core_interface.core_inst.ssc.retire_ptr top.RISCV_Core_interface.core_inst.ssc.oldest_branch_id top.RISCV_Core_interface.core_inst.ssc.clock top.RISCV_Core_interface.core_inst.ssc.reg_commits top.RISCV_Core_interface.core_inst.ssc.flush_vector top.RISCV_Core_interface.core_inst.ssc.retire_vector top.RISCV_Core_interface.core_inst.ssc.flush_mask top.RISCV_Core_interface.core_inst.ssc.store_id top.RISCV_Core_interface.core_inst.ssc.dris_entries top.RISCV_Core_interface.core_inst.ssc.trap_valid top.RISCV_Core_interface.core_inst.ssc.reset_n top.RISCV_Core_interface.core_inst.ssc.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.ssc.retire_ready_vector top.RISCV_Core_interface.core_inst.ssc.RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.ssc.entries_checked top.RISCV_Core_interface.core_inst.ssc.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.ssc.branch_fence_valid top.RISCV_Core_interface.core_inst.ssc.REG_RETIRES_PER_CYCLE {top.RISCV_Core_interface.core_inst.ssc.$unit} top.RISCV_Core_interface.core_inst.ssc.MEMORY_RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.ssc.trap_id }
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

set _session_group_4 tony_d
gui_sg_create "$_session_group_4"
set tony_d "$_session_group_4"

gui_sg_addsignal -group "$_session_group_4" { {top.RISCV_Core_interface.tony_d.unnamed$$_0} top.RISCV_Core_interface.tony_d.core_req_stall_mem top.RISCV_Core_interface.tony_d.POLICY top.RISCV_Core_interface.tony_d.do_evict_writeback top.RISCV_Core_interface.tony_d.core_req_bus_wait_en top.RISCV_Core_interface.tony_d.wr_en top.RISCV_Core_interface.tony_d.cache_store top.RISCV_Core_interface.tony_d.cache_fill_data top.RISCV_Core_interface.tony_d.core_rsp_ready top.RISCV_Core_interface.tony_d.use_latched_addr top.RISCV_Core_interface.tony_d.core_rsp_ctrl_signals top.RISCV_Core_interface.tony_d.latch_old_word_fill top.RISCV_Core_interface.tony_d.stall top.RISCV_Core_interface.tony_d.mem_rsp_good top.RISCV_Core_interface.tony_d.evicted_line top.RISCV_Core_interface.tony_d.old_word_latched top.RISCV_Core_interface.tony_d.mem_rsp_data top.RISCV_Core_interface.tony_d.core_rsp_data_valid top.RISCV_Core_interface.tony_d.do_forward top.RISCV_Core_interface.tony_d.clk top.RISCV_Core_interface.tony_d.fwd_words top.RISCV_Core_interface.tony_d.core_rsp_id top.RISCV_Core_interface.tony_d.cache_fill_valid top.RISCV_Core_interface.tony_d.rsp_words top.RISCV_Core_interface.tony_d.INDEX_BITS top.RISCV_Core_interface.tony_d.wb_pending top.RISCV_Core_interface.tony_d.read_miss top.RISCV_Core_interface.tony_d.read_data top.RISCV_Core_interface.tony_d.core_req_store_data top.RISCV_Core_interface.tony_d.core_req_id_latched top.RISCV_Core_interface.tony_d.core_rsp_data top.RISCV_Core_interface.tony_d.rst_l top.RISCV_Core_interface.tony_d.cache_wr_valid top.RISCV_Core_interface.tony_d.mem_rsp_ready top.RISCV_Core_interface.tony_d.state top.RISCV_Core_interface.tony_d.core_req_id top.RISCV_Core_interface.tony_d.cache_stall top.RISCV_Core_interface.tony_d.ADDRESS_SIZE top.RISCV_Core_interface.tony_d.core_req_store_mask top.RISCV_Core_interface.tony_d.evicted_dirty top.RISCV_Core_interface.tony_d.mem_req_store_data top.RISCV_Core_interface.tony_d.evicted_addr_latched top.RISCV_Core_interface.tony_d.do_fill top.RISCV_Core_interface.tony_d.core_req_cancel top.RISCV_Core_interface.tony_d.WAYS top.RISCV_Core_interface.tony_d.address top.RISCV_Core_interface.tony_d.read_hit top.RISCV_Core_interface.tony_d.latch_old_word_hit top.RISCV_Core_interface.tony_d.is_eviction top.RISCV_Core_interface.tony_d.fwd_pending top.RISCV_Core_interface.tony_d.cancel top.RISCV_Core_interface.tony_d.mem_req_store_mask top.RISCV_Core_interface.tony_d.mem_rsp_addr top.RISCV_Core_interface.tony_d.do_forward_saved top.RISCV_Core_interface.tony_d.BLOCK_OFFSET_BITS top.RISCV_Core_interface.tony_d.mem_bus_request top.RISCV_Core_interface.tony_d.core_req_addr_latched top.RISCV_Core_interface.tony_d.rd_en top.RISCV_Core_interface.tony_d.evicted_line_latched top.RISCV_Core_interface.tony_d.merged_store_word top.RISCV_Core_interface.tony_d.core_req_we top.RISCV_Core_interface.tony_d.wb_beat top.RISCV_Core_interface.tony_d.core_hit_valid top.RISCV_Core_interface.tony_d.core_rsp_excpt top.RISCV_Core_interface.tony_d.WORD_SIZE top.RISCV_Core_interface.tony_d.core_req_store_mask_latched top.RISCV_Core_interface.tony_d.core_rsp_addr top.RISCV_Core_interface.tony_d.cache_issue_read top.RISCV_Core_interface.tony_d.fifo_enable top.RISCV_Core_interface.tony_d.mem_rsp_valid top.RISCV_Core_interface.tony_d.mem_req_addr top.RISCV_Core_interface.tony_d.core_req_ctrl_signals_latched top.RISCV_Core_interface.tony_d.mem_req_data_load_en top.RISCV_Core_interface.tony_d.evicted_addr top.RISCV_Core_interface.tony_d.cache_wr_word top.RISCV_Core_interface.tony_d.core_req_re top.RISCV_Core_interface.tony_d.core_req_store_data_latched top.RISCV_Core_interface.tony_d.FETCH_WORDS top.RISCV_Core_interface.tony_d.ud_en top.RISCV_Core_interface.tony_d.next_state top.RISCV_Core_interface.tony_d.fifo_data top.RISCV_Core_interface.tony_d.core_req_ctrl_signals {top.RISCV_Core_interface.tony_d.$unit} top.RISCV_Core_interface.tony_d.flush top.RISCV_Core_interface.tony_d.BLOCK_SIZE top.RISCV_Core_interface.tony_d.core_req_addr top.RISCV_Core_interface.tony_d.mem_rsp_excpt }
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

set _session_group_5 core_inst_1
gui_sg_create "$_session_group_5"
set core_inst_1 "$_session_group_5"

gui_sg_addsignal -group "$_session_group_5" { top.RISCV_Core_interface.core_inst.core_req_stall_mem top.RISCV_Core_interface.core_inst.fetch_pkts top.RISCV_Core_interface.core_inst.commit_pkts top.RISCV_Core_interface.core_inst.flush_vector top.RISCV_Core_interface.core_inst.core_rsp_ready_d top.RISCV_Core_interface.core_inst.RF_WAYS top.RISCV_Core_interface.core_inst.issue_pkts_reg top.RISCV_Core_interface.core_inst.fetch_ptr top.RISCV_Core_interface.core_inst.core_req_we_d top.RISCV_Core_interface.core_inst.trap_valid top.RISCV_Core_interface.core_inst.core_req_id_d top.RISCV_Core_interface.core_inst.mem_rs2_data top.RISCV_Core_interface.core_inst.trap_pc top.RISCV_Core_interface.core_inst.core_rsp_data_valid_d top.RISCV_Core_interface.core_inst.core_rsp_ready top.RISCV_Core_interface.core_inst.retire_vector top.RISCV_Core_interface.core_inst.rf_commit_valid top.RISCV_Core_interface.core_inst.core_rsp_ctrl_signals_d top.RISCV_Core_interface.core_inst.rf_we top.RISCV_Core_interface.core_inst.core_rsp_data_valid top.RISCV_Core_interface.core_inst.core_rsp_data_d top.RISCV_Core_interface.core_inst.sched_rs2_addr top.RISCV_Core_interface.core_inst.clock top.RISCV_Core_interface.core_inst.MEM_ISSUE_WAYS top.RISCV_Core_interface.core_inst.store_ready top.RISCV_Core_interface.core_inst.rf_commit_pc top.RISCV_Core_interface.core_inst.retire_ptr top.RISCV_Core_interface.core_inst.sched_rs1_data top.RISCV_Core_interface.core_inst.rf_rd_data top.RISCV_Core_interface.core_inst.writeback_pkts top.RISCV_Core_interface.core_inst.core_req_re_d top.RISCV_Core_interface.core_inst.halted top.RISCV_Core_interface.core_inst.core_rsp_data top.RISCV_Core_interface.core_inst.rf_rd top.RISCV_Core_interface.core_inst.core_req_stall_mem_d top.RISCV_Core_interface.core_inst.rf_commit_pkts top.RISCV_Core_interface.core_inst.rf_rs1 top.RISCV_Core_interface.core_inst.rf_rs2 top.RISCV_Core_interface.core_inst.rf_rs1_data top.RISCV_Core_interface.core_inst.ADDRESS_SIZE top.RISCV_Core_interface.core_inst.mem_rs2_addr top.RISCV_Core_interface.core_inst.core_req_cancel top.RISCV_Core_interface.core_inst.sched_read_rf top.RISCV_Core_interface.core_inst.mem_rs1_data top.RISCV_Core_interface.core_inst.core_req_store_mask_d top.RISCV_Core_interface.core_inst.store_id top.RISCV_Core_interface.core_inst.RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.issue_pkts top.RISCV_Core_interface.core_inst.WRITEBACK_PORTS top.RISCV_Core_interface.core_inst.dris_entries top.RISCV_Core_interface.core_inst.reset_n top.RISCV_Core_interface.core_inst.rf_commit_insn top.RISCV_Core_interface.core_inst.mem_read_rf top.RISCV_Core_interface.core_inst.core_req_ctrl_signals_d top.RISCV_Core_interface.core_inst.sched_rs1_addr top.RISCV_Core_interface.core_inst.flush_mask top.RISCV_Core_interface.core_inst.core_rsp_addr_d top.RISCV_Core_interface.core_inst.core_req_cancel_d top.RISCV_Core_interface.core_inst.core_rsp_excpt top.RISCV_Core_interface.core_inst.core_rsp_excpt_d top.RISCV_Core_interface.core_inst.mem_issue_pkts top.RISCV_Core_interface.core_inst.core_rsp_addr top.RISCV_Core_interface.core_inst.oldest_branch_id top.RISCV_Core_interface.core_inst.d_granted top.RISCV_Core_interface.core_inst.core_req_addr_d top.RISCV_Core_interface.core_inst.sched_rs2_data top.RISCV_Core_interface.core_inst.core_req_re top.RISCV_Core_interface.core_inst.core_rsp_id_d top.RISCV_Core_interface.core_inst.FETCH_WORDS top.RISCV_Core_interface.core_inst.reg_commits top.RISCV_Core_interface.core_inst.dris_intake_pkts top.RISCV_Core_interface.core_inst.set_dispatched top.RISCV_Core_interface.core_inst.mem_rs1_addr top.RISCV_Core_interface.core_inst.EXEC_UNITS {top.RISCV_Core_interface.core_inst.$unit} top.RISCV_Core_interface.core_inst.update_bus top.RISCV_Core_interface.core_inst.set_dispatched_mem top.RISCV_Core_interface.core_inst.branch_fence_valid top.RISCV_Core_interface.core_inst.core_req_store_data_d top.RISCV_Core_interface.core_inst.core_req_addr top.RISCV_Core_interface.core_inst.trap_id top.RISCV_Core_interface.core_inst.rf_rs2_data }
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

set _session_group_6 dris_1
gui_sg_create "$_session_group_6"
set dris_1 "$_session_group_6"

gui_sg_addsignal -group "$_session_group_6" { top.RISCV_Core_interface.core_inst.dris.ENTRIES top.RISCV_Core_interface.core_inst.dris.locker_1_comb top.RISCV_Core_interface.core_inst.dris.MEMORY_READ_PORTS top.RISCV_Core_interface.core_inst.dris.full_id_tmp top.RISCV_Core_interface.core_inst.dris.clock top.RISCV_Core_interface.core_inst.dris.clear_valid top.RISCV_Core_interface.core_inst.dris.dep1 top.RISCV_Core_interface.core_inst.dris.fetch_group_dep1_valid top.RISCV_Core_interface.core_inst.dris.dep2 top.RISCV_Core_interface.core_inst.dris.dris_entries top.RISCV_Core_interface.core_inst.dris.fetch_pkts top.RISCV_Core_interface.core_inst.dris.set_dispatched top.RISCV_Core_interface.core_inst.dris.FETCH_WAYS top.RISCV_Core_interface.core_inst.dris.reset_n top.RISCV_Core_interface.core_inst.dris.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.dris.locker_2_comb top.RISCV_Core_interface.core_inst.dris.WRITEBACK_PORTS top.RISCV_Core_interface.core_inst.dris.fetch_group_dep2_valid top.RISCV_Core_interface.core_inst.dris.new_ids top.RISCV_Core_interface.core_inst.dris.fetch_ptr top.RISCV_Core_interface.core_inst.dris.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.dris.writeback_pkts top.RISCV_Core_interface.core_inst.dris.dep2_completing_now top.RISCV_Core_interface.core_inst.dris.dep1_completing_now {top.RISCV_Core_interface.core_inst.dris.$unit} top.RISCV_Core_interface.core_inst.dris.EXEC_UNITS }
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

set _session_group_7 ssc_1
gui_sg_create "$_session_group_7"
set ssc_1 "$_session_group_7"

gui_sg_addsignal -group "$_session_group_7" { top.RISCV_Core_interface.core_inst.ssc.trap_pc top.RISCV_Core_interface.core_inst.ssc.d_cache_ready top.RISCV_Core_interface.core_inst.ssc.store_ready top.RISCV_Core_interface.core_inst.ssc.retire_ptr top.RISCV_Core_interface.core_inst.ssc.oldest_branch_id top.RISCV_Core_interface.core_inst.ssc.clock top.RISCV_Core_interface.core_inst.ssc.reg_commits top.RISCV_Core_interface.core_inst.ssc.flush_vector top.RISCV_Core_interface.core_inst.ssc.retire_vector top.RISCV_Core_interface.core_inst.ssc.flush_mask top.RISCV_Core_interface.core_inst.ssc.store_id top.RISCV_Core_interface.core_inst.ssc.dris_entries top.RISCV_Core_interface.core_inst.ssc.trap_valid top.RISCV_Core_interface.core_inst.ssc.reset_n top.RISCV_Core_interface.core_inst.ssc.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.ssc.retire_ready_vector top.RISCV_Core_interface.core_inst.ssc.RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.ssc.entries_checked top.RISCV_Core_interface.core_inst.ssc.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.ssc.branch_fence_valid top.RISCV_Core_interface.core_inst.ssc.REG_RETIRES_PER_CYCLE {top.RISCV_Core_interface.core_inst.ssc.$unit} top.RISCV_Core_interface.core_inst.ssc.MEMORY_RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.ssc.trap_id }
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

set _session_group_8 tony_d_1
gui_sg_create "$_session_group_8"
set tony_d_1 "$_session_group_8"

gui_sg_addsignal -group "$_session_group_8" { {top.RISCV_Core_interface.tony_d.unnamed$$_0} top.RISCV_Core_interface.tony_d.core_req_stall_mem top.RISCV_Core_interface.tony_d.POLICY top.RISCV_Core_interface.tony_d.do_evict_writeback top.RISCV_Core_interface.tony_d.core_req_bus_wait_en top.RISCV_Core_interface.tony_d.wr_en top.RISCV_Core_interface.tony_d.cache_store top.RISCV_Core_interface.tony_d.cache_fill_data top.RISCV_Core_interface.tony_d.core_rsp_ready top.RISCV_Core_interface.tony_d.use_latched_addr top.RISCV_Core_interface.tony_d.core_rsp_ctrl_signals top.RISCV_Core_interface.tony_d.latch_old_word_fill top.RISCV_Core_interface.tony_d.stall top.RISCV_Core_interface.tony_d.mem_rsp_good top.RISCV_Core_interface.tony_d.evicted_line top.RISCV_Core_interface.tony_d.old_word_latched top.RISCV_Core_interface.tony_d.mem_rsp_data top.RISCV_Core_interface.tony_d.core_rsp_data_valid top.RISCV_Core_interface.tony_d.do_forward top.RISCV_Core_interface.tony_d.clk top.RISCV_Core_interface.tony_d.fwd_words top.RISCV_Core_interface.tony_d.core_rsp_id top.RISCV_Core_interface.tony_d.cache_fill_valid top.RISCV_Core_interface.tony_d.rsp_words top.RISCV_Core_interface.tony_d.INDEX_BITS top.RISCV_Core_interface.tony_d.wb_pending top.RISCV_Core_interface.tony_d.read_miss top.RISCV_Core_interface.tony_d.read_data top.RISCV_Core_interface.tony_d.core_req_store_data top.RISCV_Core_interface.tony_d.core_req_id_latched top.RISCV_Core_interface.tony_d.core_rsp_data top.RISCV_Core_interface.tony_d.rst_l top.RISCV_Core_interface.tony_d.cache_wr_valid top.RISCV_Core_interface.tony_d.mem_rsp_ready top.RISCV_Core_interface.tony_d.state top.RISCV_Core_interface.tony_d.core_req_id top.RISCV_Core_interface.tony_d.cache_stall top.RISCV_Core_interface.tony_d.ADDRESS_SIZE top.RISCV_Core_interface.tony_d.core_req_store_mask top.RISCV_Core_interface.tony_d.evicted_dirty top.RISCV_Core_interface.tony_d.mem_req_store_data top.RISCV_Core_interface.tony_d.evicted_addr_latched top.RISCV_Core_interface.tony_d.do_fill top.RISCV_Core_interface.tony_d.core_req_cancel top.RISCV_Core_interface.tony_d.WAYS top.RISCV_Core_interface.tony_d.address top.RISCV_Core_interface.tony_d.read_hit top.RISCV_Core_interface.tony_d.latch_old_word_hit top.RISCV_Core_interface.tony_d.is_eviction top.RISCV_Core_interface.tony_d.fwd_pending top.RISCV_Core_interface.tony_d.cancel top.RISCV_Core_interface.tony_d.mem_req_store_mask top.RISCV_Core_interface.tony_d.mem_rsp_addr top.RISCV_Core_interface.tony_d.do_forward_saved top.RISCV_Core_interface.tony_d.BLOCK_OFFSET_BITS top.RISCV_Core_interface.tony_d.mem_bus_request top.RISCV_Core_interface.tony_d.core_req_addr_latched top.RISCV_Core_interface.tony_d.rd_en top.RISCV_Core_interface.tony_d.evicted_line_latched top.RISCV_Core_interface.tony_d.merged_store_word top.RISCV_Core_interface.tony_d.core_req_we top.RISCV_Core_interface.tony_d.wb_beat top.RISCV_Core_interface.tony_d.core_hit_valid top.RISCV_Core_interface.tony_d.core_rsp_excpt top.RISCV_Core_interface.tony_d.WORD_SIZE top.RISCV_Core_interface.tony_d.core_req_store_mask_latched top.RISCV_Core_interface.tony_d.core_rsp_addr top.RISCV_Core_interface.tony_d.cache_issue_read top.RISCV_Core_interface.tony_d.fifo_enable top.RISCV_Core_interface.tony_d.mem_rsp_valid top.RISCV_Core_interface.tony_d.mem_req_addr top.RISCV_Core_interface.tony_d.core_req_ctrl_signals_latched top.RISCV_Core_interface.tony_d.mem_req_data_load_en top.RISCV_Core_interface.tony_d.evicted_addr top.RISCV_Core_interface.tony_d.cache_wr_word top.RISCV_Core_interface.tony_d.core_req_re top.RISCV_Core_interface.tony_d.core_req_store_data_latched top.RISCV_Core_interface.tony_d.FETCH_WORDS top.RISCV_Core_interface.tony_d.ud_en top.RISCV_Core_interface.tony_d.next_state top.RISCV_Core_interface.tony_d.fifo_data top.RISCV_Core_interface.tony_d.core_req_ctrl_signals {top.RISCV_Core_interface.tony_d.$unit} top.RISCV_Core_interface.tony_d.flush top.RISCV_Core_interface.tony_d.BLOCK_SIZE top.RISCV_Core_interface.tony_d.core_req_addr top.RISCV_Core_interface.tony_d.mem_rsp_excpt }
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

# Global: Highlighting

# Global: Stack
gui_change_stack_mode -mode list

# Post database loading setting...

# Restore C1 time
gui_set_time -C1_only 156



# Save global setting...

# Wave/List view global setting
gui_cov_show_value -switch false

# Close all empty TopLevel windows
foreach __top [gui_ekki_get_window_ids -type TopLevel] {
    if { [llength [gui_ekki_get_window_ids -parent $__top]] == 0} {
        gui_close_window -window $__top
    }
}
gui_set_loading_session_type noSession
# DVE View/pane content session: 


# Hier 'Hier.1'
gui_show_window -window ${Hier.1}
gui_list_set_filter -id ${Hier.1} -list { {Package 1} {All 0} {Process 1} {VirtPowSwitch 0} {UnnamedProcess 1} {UDP 0} {Function 1} {Block 1} {SrsnAndSpaCell 0} {OVA Unit 1} {LeafScCell 1} {LeafVlgCell 1} {Interface 1} {LeafVhdCell 1} {$unit 1} {NamedBlock 1} {Task 1} {VlgPackage 1} {ClassDef 1} {VirtIsoCell 0} }
gui_list_set_filter -id ${Hier.1} -text {*}
gui_hier_list_init -id ${Hier.1}
gui_change_design -id ${Hier.1} -design Sim
catch {gui_list_expand -id ${Hier.1} top}
catch {gui_list_expand -id ${Hier.1} top.RISCV_Core_interface}
catch {gui_list_select -id ${Hier.1} {top.RISCV_Core_interface.core_inst}}
gui_view_scroll -id ${Hier.1} -vertical -set 272
gui_view_scroll -id ${Hier.1} -horizontal -set 0

# Class 'Class.1'
gui_list_set_filter -id ${Class.1} -list { {OVM 1} {VMM 1} {All 1} {Object 1} {UVM 1} {RVM 1} }
gui_list_set_filter -id ${Class.1} -text {*}
gui_change_design -id ${Class.1} -design Sim

# Member 'Member.1'
gui_list_set_filter -id ${Member.1} -list { {InternalMember 0} {RandMember 1} {All 0} {BaseMember 0} {PrivateMember 1} {LibBaseMember 0} {AutomaticMember 1} {VirtualMember 1} {PublicMember 1} {ProtectedMember 1} {OverRiddenMember 0} {InterfaceClassMember 1} {StaticMember 1} }
gui_list_set_filter -id ${Member.1} -text {*}

# Data 'Data.1'
gui_list_set_filter -id ${Data.1} -list { {Buffer 1} {Input 1} {Others 1} {Linkage 1} {Output 1} {LowPower 1} {Parameter 1} {All 1} {Aggregate 1} {LibBaseMember 1} {Event 1} {Assertion 1} {Constant 1} {Interface 1} {BaseMembers 1} {Signal 1} {$unit 1} {Inout 1} {Variable 1} }
gui_list_set_filter -id ${Data.1} -text {*}
gui_list_show_data -id ${Data.1} {top.RISCV_Core_interface.core_inst.ssc}
gui_view_scroll -id ${Data.1} -vertical -set 0
gui_view_scroll -id ${Data.1} -horizontal -set 0
gui_view_scroll -id ${Hier.1} -vertical -set 272
gui_view_scroll -id ${Hier.1} -horizontal -set 0

# Source 'Source.1'
gui_src_value_annotate -id ${Source.1} -switch false
gui_set_env TOGGLE::VALUEANNOTATE 0
gui_open_source -id ${Source.1}  -replace -active top.CommitVerifier /afs/ece.cmu.edu/usr/daniello/Private/riscv-metaflow-lightning/tb/commit_verifier.sv
gui_view_scroll -id ${Source.1} -vertical -set 1635
gui_src_set_reusable -id ${Source.1}
# Warning: Class view not found.

# View 'Wave.1'
gui_wv_sync -id ${Wave.1} -switch false
set groupExD [gui_get_pref_value -category Wave -key exclusiveSG]
gui_set_pref_value -category Wave -key exclusiveSG -value {false}
set origWaveHeight [gui_get_pref_value -category Wave -key waveRowHeight]
gui_list_set_height -id Wave -height 25
set origGroupCreationState [gui_list_create_group_when_add -wave]
gui_list_create_group_when_add -wave -disable
gui_marker_set_ref -id ${Wave.1}  C1
gui_wv_zoom_timerange -id ${Wave.1} 0 355
gui_list_add_group -id ${Wave.1} -after {New Group} {core_inst_1}
gui_list_add_group -id ${Wave.1} -after {New Group} {dris_1}
gui_list_add_group -id ${Wave.1} -after {New Group} {ssc_1}
gui_list_add_group -id ${Wave.1} -after {New Group} {tony_d_1}
gui_seek_criteria -id ${Wave.1} {Any Edge}



gui_set_env TOGGLE::DEFAULT_WAVE_WINDOW ${Wave.1}
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
gui_list_set_insertion_bar  -id ${Wave.1} -group tony_d_1  -position in

gui_marker_move -id ${Wave.1} {C1} 156
gui_view_scroll -id ${Wave.1} -vertical -set 0
gui_show_grid -id ${Wave.1} -enable false
# Restore toplevel window zorder
# The toplevel window could be closed if it has no view/pane
if {[gui_exist_window -window ${TopLevel.1}]} {
	gui_set_active_window -window ${TopLevel.1}
	gui_set_active_window -window ${Source.1}
	gui_set_active_window -window ${HSPane.1}
}
if {[gui_exist_window -window ${TopLevel.2}]} {
	gui_set_active_window -window ${TopLevel.2}
	gui_set_active_window -window ${Wave.1}
}
#</Session>

