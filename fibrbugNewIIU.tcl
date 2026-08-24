# Begin_DVE_Session_Save_Info
# DVE full session
# Saved on Mon Aug 24 16:55:42 2026
# Designs open: 1
#   Sim: sim
# Toplevel windows open: 2
# 	TopLevel.1
# 	TopLevel.2
#   Source.1: top.RISCV_Core_interface.ifetch_bounds.unnamed$$_1
#   Wave.1: 327 signals
#   Group count = 12
#   Group core_inst signal count = 82
#   Group dris signal count = 26
#   Group ssc signal count = 24
#   Group tony_d signal count = 87
#   Group core_inst_1 signal count = 82
#   Group dris_1 signal count = 26
#   Group ssc_1 signal count = 24
#   Group tony_d_1 signal count = 87
#   Group Group1 signal count = 2
#   Group scheduler signal count = 26
#   Group iiu signal count = 75
#   Group Group2 signal count = 5
# End_DVE_Session_Save_Info

# DVE version: T-2022.06_Full64
# DVE build date: May 31 2022 20:53:03


#<Session mode="Full" path="/afs/ece.cmu.edu/usr/daniello/Private/riscv-metaflow-lightning/fibrbugNewIIU.tcl" type="Debug">

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
gui_show_window -window ${TopLevel.1} -show_state normal -rect {{744 438} {1508 1316}}

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
set HSPane.1 [gui_create_window -type HSPane -parent ${TopLevel.1} -dock_state left -dock_on_new_line true -dock_extent 491]
catch { set Hier.1 [gui_share_window -id ${HSPane.1} -type Hier] }
catch { set Stack.1 [gui_share_window -id ${HSPane.1} -type Stack -silent] }
catch { set Class.1 [gui_share_window -id ${HSPane.1} -type Class -silent] }
catch { set Object.1 [gui_share_window -id ${HSPane.1} -type Object -silent] }
gui_set_window_pref_key -window ${HSPane.1} -key dock_width -value_type integer -value 491
gui_set_window_pref_key -window ${HSPane.1} -key dock_height -value_type integer -value -1
gui_set_window_pref_key -window ${HSPane.1} -key dock_offset -value_type integer -value 0
gui_update_layout -id ${HSPane.1} {{left 0} {top 0} {width 490} {height 556} {dock_state left} {dock_on_new_line true} {child_hier_colhier 370} {child_hier_coltype 141} {child_hier_colpd 0} {child_hier_col1 0} {child_hier_col2 1} {child_hier_col3 -1}}
set DLPane.1 [gui_create_window -type DLPane -parent ${TopLevel.1} -dock_state left -dock_on_new_line true -dock_extent 294]
catch { set Data.1 [gui_share_window -id ${DLPane.1} -type Data] }
catch { set Local.1 [gui_share_window -id ${DLPane.1} -type Local -silent] }
catch { set Member.1 [gui_share_window -id ${DLPane.1} -type Member -silent] }
gui_set_window_pref_key -window ${DLPane.1} -key dock_width -value_type integer -value 294
gui_set_window_pref_key -window ${DLPane.1} -key dock_height -value_type integer -value 576
gui_set_window_pref_key -window ${DLPane.1} -key dock_offset -value_type integer -value 0
gui_update_layout -id ${DLPane.1} {{left 0} {top 0} {width 293} {height 556} {dock_state left} {dock_on_new_line true} {child_data_colvariable 369} {child_data_colvalue 288} {child_data_coltype 285} {child_data_col1 0} {child_data_col2 1} {child_data_col3 2}}
set Console.1 [gui_create_window -type Console -parent ${TopLevel.1} -dock_state bottom -dock_on_new_line true -dock_extent 176]
gui_set_window_pref_key -window ${Console.1} -key dock_width -value_type integer -value 764
gui_set_window_pref_key -window ${Console.1} -key dock_height -value_type integer -value 176
gui_set_window_pref_key -window ${Console.1} -key dock_offset -value_type integer -value 0
gui_update_layout -id ${Console.1} {{left 0} {top 0} {width 764} {height 175} {dock_state bottom} {dock_on_new_line true}}
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
gui_show_window -window ${TopLevel.2} -show_state maximized -rect {{0 23} {2559 1391}}

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
gui_update_layout -id ${Wave.1} {{show_state maximized} {dock_state undocked} {dock_on_new_line false} {child_wave_left 743} {child_wave_right 1811} {child_wave_colname 245} {child_wave_colvalue 494} {child_wave_col1 0} {child_wave_col2 1}}

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
gui_set_env SIMSETUP::SIMARGS {{ -ucligui}}
gui_set_env SIMSETUP::SIMEXE {sim}
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
gui_load_child_values {top.RISCV_Core_interface.core_inst.scheduler}
gui_load_child_values {top.RISCV_Core_interface.core_inst.ssc}
gui_load_child_values {top}
gui_load_child_values {top.RISCV_Core_interface.core_inst.iiu}


set _session_group_12 core_inst
gui_sg_create "$_session_group_12"
set core_inst "$_session_group_12"

gui_sg_addsignal -group "$_session_group_12" { top.RISCV_Core_interface.core_inst.core_req_stall_mem top.RISCV_Core_interface.core_inst.fetch_pkts top.RISCV_Core_interface.core_inst.commit_pkts top.RISCV_Core_interface.core_inst.flush_vector top.RISCV_Core_interface.core_inst.core_rsp_ready_d top.RISCV_Core_interface.core_inst.RF_WAYS top.RISCV_Core_interface.core_inst.issue_pkts_reg top.RISCV_Core_interface.core_inst.fetch_ptr top.RISCV_Core_interface.core_inst.core_req_we_d top.RISCV_Core_interface.core_inst.trap_valid top.RISCV_Core_interface.core_inst.core_req_id_d top.RISCV_Core_interface.core_inst.mem_rs2_data top.RISCV_Core_interface.core_inst.trap_pc top.RISCV_Core_interface.core_inst.core_rsp_data_valid_d top.RISCV_Core_interface.core_inst.core_rsp_ready top.RISCV_Core_interface.core_inst.retire_vector top.RISCV_Core_interface.core_inst.rf_commit_valid top.RISCV_Core_interface.core_inst.core_rsp_ctrl_signals_d top.RISCV_Core_interface.core_inst.rf_we top.RISCV_Core_interface.core_inst.core_rsp_data_valid top.RISCV_Core_interface.core_inst.core_rsp_data_d top.RISCV_Core_interface.core_inst.sched_rs2_addr top.RISCV_Core_interface.core_inst.clock top.RISCV_Core_interface.core_inst.MEM_ISSUE_WAYS top.RISCV_Core_interface.core_inst.store_ready top.RISCV_Core_interface.core_inst.rf_commit_pc top.RISCV_Core_interface.core_inst.retire_ptr top.RISCV_Core_interface.core_inst.sched_rs1_data top.RISCV_Core_interface.core_inst.rf_rd_data top.RISCV_Core_interface.core_inst.writeback_pkts top.RISCV_Core_interface.core_inst.core_req_re_d top.RISCV_Core_interface.core_inst.halted top.RISCV_Core_interface.core_inst.core_rsp_data top.RISCV_Core_interface.core_inst.rf_rd top.RISCV_Core_interface.core_inst.core_req_stall_mem_d top.RISCV_Core_interface.core_inst.rf_commit_pkts top.RISCV_Core_interface.core_inst.rf_rs1 top.RISCV_Core_interface.core_inst.rf_rs2 top.RISCV_Core_interface.core_inst.rf_rs1_data top.RISCV_Core_interface.core_inst.ADDRESS_SIZE top.RISCV_Core_interface.core_inst.mem_rs2_addr top.RISCV_Core_interface.core_inst.core_req_cancel top.RISCV_Core_interface.core_inst.sched_read_rf top.RISCV_Core_interface.core_inst.mem_rs1_data top.RISCV_Core_interface.core_inst.core_req_store_mask_d top.RISCV_Core_interface.core_inst.store_id top.RISCV_Core_interface.core_inst.RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.issue_pkts top.RISCV_Core_interface.core_inst.WRITEBACK_PORTS top.RISCV_Core_interface.core_inst.dris_entries top.RISCV_Core_interface.core_inst.reset_n top.RISCV_Core_interface.core_inst.rf_commit_insn top.RISCV_Core_interface.core_inst.mem_read_rf top.RISCV_Core_interface.core_inst.core_req_ctrl_signals_d top.RISCV_Core_interface.core_inst.sched_rs1_addr top.RISCV_Core_interface.core_inst.flush_mask top.RISCV_Core_interface.core_inst.core_rsp_addr_d top.RISCV_Core_interface.core_inst.core_req_cancel_d top.RISCV_Core_interface.core_inst.core_rsp_excpt top.RISCV_Core_interface.core_inst.core_rsp_excpt_d top.RISCV_Core_interface.core_inst.mem_issue_pkts top.RISCV_Core_interface.core_inst.core_rsp_addr top.RISCV_Core_interface.core_inst.oldest_branch_id top.RISCV_Core_interface.core_inst.d_granted top.RISCV_Core_interface.core_inst.core_req_addr_d top.RISCV_Core_interface.core_inst.sched_rs2_data top.RISCV_Core_interface.core_inst.core_req_re top.RISCV_Core_interface.core_inst.core_rsp_id_d top.RISCV_Core_interface.core_inst.FETCH_WORDS top.RISCV_Core_interface.core_inst.reg_commits top.RISCV_Core_interface.core_inst.dris_intake_pkts top.RISCV_Core_interface.core_inst.set_dispatched top.RISCV_Core_interface.core_inst.mem_rs1_addr top.RISCV_Core_interface.core_inst.EXEC_UNITS {top.RISCV_Core_interface.core_inst.$unit} top.RISCV_Core_interface.core_inst.update_bus top.RISCV_Core_interface.core_inst.set_dispatched_mem top.RISCV_Core_interface.core_inst.branch_fence_valid top.RISCV_Core_interface.core_inst.core_req_store_data_d top.RISCV_Core_interface.core_inst.core_req_addr top.RISCV_Core_interface.core_inst.trap_id top.RISCV_Core_interface.core_inst.rf_rs2_data }
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

set _session_group_13 dris
gui_sg_create "$_session_group_13"
set dris "$_session_group_13"

gui_sg_addsignal -group "$_session_group_13" { top.RISCV_Core_interface.core_inst.dris.ENTRIES top.RISCV_Core_interface.core_inst.dris.locker_1_comb top.RISCV_Core_interface.core_inst.dris.MEMORY_READ_PORTS top.RISCV_Core_interface.core_inst.dris.full_id_tmp top.RISCV_Core_interface.core_inst.dris.clock top.RISCV_Core_interface.core_inst.dris.clear_valid top.RISCV_Core_interface.core_inst.dris.dep1 top.RISCV_Core_interface.core_inst.dris.fetch_group_dep1_valid top.RISCV_Core_interface.core_inst.dris.dep2 top.RISCV_Core_interface.core_inst.dris.dris_entries top.RISCV_Core_interface.core_inst.dris.fetch_pkts top.RISCV_Core_interface.core_inst.dris.set_dispatched top.RISCV_Core_interface.core_inst.dris.FETCH_WAYS top.RISCV_Core_interface.core_inst.dris.reset_n top.RISCV_Core_interface.core_inst.dris.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.dris.locker_2_comb top.RISCV_Core_interface.core_inst.dris.WRITEBACK_PORTS top.RISCV_Core_interface.core_inst.dris.fetch_group_dep2_valid top.RISCV_Core_interface.core_inst.dris.new_ids top.RISCV_Core_interface.core_inst.dris.fetch_ptr top.RISCV_Core_interface.core_inst.dris.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.dris.writeback_pkts top.RISCV_Core_interface.core_inst.dris.dep2_completing_now top.RISCV_Core_interface.core_inst.dris.dep1_completing_now {top.RISCV_Core_interface.core_inst.dris.$unit} top.RISCV_Core_interface.core_inst.dris.EXEC_UNITS }
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

set _session_group_14 ssc
gui_sg_create "$_session_group_14"
set ssc "$_session_group_14"

gui_sg_addsignal -group "$_session_group_14" { top.RISCV_Core_interface.core_inst.ssc.trap_pc top.RISCV_Core_interface.core_inst.ssc.d_cache_ready top.RISCV_Core_interface.core_inst.ssc.store_ready top.RISCV_Core_interface.core_inst.ssc.retire_ptr top.RISCV_Core_interface.core_inst.ssc.oldest_branch_id top.RISCV_Core_interface.core_inst.ssc.clock top.RISCV_Core_interface.core_inst.ssc.reg_commits top.RISCV_Core_interface.core_inst.ssc.flush_vector top.RISCV_Core_interface.core_inst.ssc.retire_vector top.RISCV_Core_interface.core_inst.ssc.flush_mask top.RISCV_Core_interface.core_inst.ssc.store_id top.RISCV_Core_interface.core_inst.ssc.dris_entries top.RISCV_Core_interface.core_inst.ssc.trap_valid top.RISCV_Core_interface.core_inst.ssc.reset_n top.RISCV_Core_interface.core_inst.ssc.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.ssc.retire_ready_vector top.RISCV_Core_interface.core_inst.ssc.RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.ssc.entries_checked top.RISCV_Core_interface.core_inst.ssc.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.ssc.branch_fence_valid top.RISCV_Core_interface.core_inst.ssc.REG_RETIRES_PER_CYCLE {top.RISCV_Core_interface.core_inst.ssc.$unit} top.RISCV_Core_interface.core_inst.ssc.MEMORY_RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.ssc.trap_id }
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

set _session_group_15 tony_d
gui_sg_create "$_session_group_15"
set tony_d "$_session_group_15"

gui_sg_addsignal -group "$_session_group_15" { {top.RISCV_Core_interface.tony_d.unnamed$$_0} top.RISCV_Core_interface.tony_d.core_req_stall_mem top.RISCV_Core_interface.tony_d.POLICY top.RISCV_Core_interface.tony_d.do_evict_writeback top.RISCV_Core_interface.tony_d.core_req_bus_wait_en top.RISCV_Core_interface.tony_d.wr_en top.RISCV_Core_interface.tony_d.cache_store top.RISCV_Core_interface.tony_d.cache_fill_data top.RISCV_Core_interface.tony_d.core_rsp_ready top.RISCV_Core_interface.tony_d.use_latched_addr top.RISCV_Core_interface.tony_d.core_rsp_ctrl_signals top.RISCV_Core_interface.tony_d.latch_old_word_fill top.RISCV_Core_interface.tony_d.stall top.RISCV_Core_interface.tony_d.mem_rsp_good top.RISCV_Core_interface.tony_d.evicted_line top.RISCV_Core_interface.tony_d.old_word_latched top.RISCV_Core_interface.tony_d.mem_rsp_data top.RISCV_Core_interface.tony_d.core_rsp_data_valid top.RISCV_Core_interface.tony_d.do_forward top.RISCV_Core_interface.tony_d.clk top.RISCV_Core_interface.tony_d.fwd_words top.RISCV_Core_interface.tony_d.core_rsp_id top.RISCV_Core_interface.tony_d.cache_fill_valid top.RISCV_Core_interface.tony_d.rsp_words top.RISCV_Core_interface.tony_d.INDEX_BITS top.RISCV_Core_interface.tony_d.wb_pending top.RISCV_Core_interface.tony_d.read_miss top.RISCV_Core_interface.tony_d.read_data top.RISCV_Core_interface.tony_d.core_req_store_data top.RISCV_Core_interface.tony_d.core_req_id_latched top.RISCV_Core_interface.tony_d.core_rsp_data top.RISCV_Core_interface.tony_d.rst_l top.RISCV_Core_interface.tony_d.cache_wr_valid top.RISCV_Core_interface.tony_d.mem_rsp_ready top.RISCV_Core_interface.tony_d.state top.RISCV_Core_interface.tony_d.core_req_id top.RISCV_Core_interface.tony_d.cache_stall top.RISCV_Core_interface.tony_d.ADDRESS_SIZE top.RISCV_Core_interface.tony_d.core_req_store_mask top.RISCV_Core_interface.tony_d.evicted_dirty top.RISCV_Core_interface.tony_d.mem_req_store_data top.RISCV_Core_interface.tony_d.evicted_addr_latched top.RISCV_Core_interface.tony_d.do_fill top.RISCV_Core_interface.tony_d.core_req_cancel top.RISCV_Core_interface.tony_d.WAYS top.RISCV_Core_interface.tony_d.address top.RISCV_Core_interface.tony_d.read_hit top.RISCV_Core_interface.tony_d.latch_old_word_hit top.RISCV_Core_interface.tony_d.is_eviction top.RISCV_Core_interface.tony_d.fwd_pending top.RISCV_Core_interface.tony_d.cancel top.RISCV_Core_interface.tony_d.mem_req_store_mask top.RISCV_Core_interface.tony_d.mem_rsp_addr top.RISCV_Core_interface.tony_d.do_forward_saved top.RISCV_Core_interface.tony_d.BLOCK_OFFSET_BITS top.RISCV_Core_interface.tony_d.mem_bus_request top.RISCV_Core_interface.tony_d.core_req_addr_latched top.RISCV_Core_interface.tony_d.rd_en top.RISCV_Core_interface.tony_d.evicted_line_latched top.RISCV_Core_interface.tony_d.merged_store_word top.RISCV_Core_interface.tony_d.core_req_we top.RISCV_Core_interface.tony_d.wb_beat top.RISCV_Core_interface.tony_d.core_hit_valid top.RISCV_Core_interface.tony_d.core_rsp_excpt top.RISCV_Core_interface.tony_d.WORD_SIZE top.RISCV_Core_interface.tony_d.core_req_store_mask_latched top.RISCV_Core_interface.tony_d.core_rsp_addr top.RISCV_Core_interface.tony_d.cache_issue_read top.RISCV_Core_interface.tony_d.fifo_enable top.RISCV_Core_interface.tony_d.mem_rsp_valid top.RISCV_Core_interface.tony_d.mem_req_addr top.RISCV_Core_interface.tony_d.core_req_ctrl_signals_latched top.RISCV_Core_interface.tony_d.mem_req_data_load_en top.RISCV_Core_interface.tony_d.evicted_addr top.RISCV_Core_interface.tony_d.cache_wr_word top.RISCV_Core_interface.tony_d.core_req_re top.RISCV_Core_interface.tony_d.core_req_store_data_latched top.RISCV_Core_interface.tony_d.FETCH_WORDS top.RISCV_Core_interface.tony_d.ud_en top.RISCV_Core_interface.tony_d.next_state top.RISCV_Core_interface.tony_d.fifo_data top.RISCV_Core_interface.tony_d.core_req_ctrl_signals {top.RISCV_Core_interface.tony_d.$unit} top.RISCV_Core_interface.tony_d.flush top.RISCV_Core_interface.tony_d.BLOCK_SIZE top.RISCV_Core_interface.tony_d.core_req_addr top.RISCV_Core_interface.tony_d.mem_rsp_excpt }
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

set _session_group_16 core_inst_1
gui_sg_create "$_session_group_16"
set core_inst_1 "$_session_group_16"

gui_sg_addsignal -group "$_session_group_16" { top.RISCV_Core_interface.core_inst.core_req_stall_mem top.RISCV_Core_interface.core_inst.fetch_pkts top.RISCV_Core_interface.core_inst.commit_pkts top.RISCV_Core_interface.core_inst.flush_vector top.RISCV_Core_interface.core_inst.core_rsp_ready_d top.RISCV_Core_interface.core_inst.RF_WAYS top.RISCV_Core_interface.core_inst.issue_pkts_reg top.RISCV_Core_interface.core_inst.fetch_ptr top.RISCV_Core_interface.core_inst.core_req_we_d top.RISCV_Core_interface.core_inst.trap_valid top.RISCV_Core_interface.core_inst.core_req_id_d top.RISCV_Core_interface.core_inst.mem_rs2_data top.RISCV_Core_interface.core_inst.trap_pc top.RISCV_Core_interface.core_inst.core_rsp_data_valid_d top.RISCV_Core_interface.core_inst.core_rsp_ready top.RISCV_Core_interface.core_inst.retire_vector top.RISCV_Core_interface.core_inst.rf_commit_valid top.RISCV_Core_interface.core_inst.core_rsp_ctrl_signals_d top.RISCV_Core_interface.core_inst.rf_we top.RISCV_Core_interface.core_inst.core_rsp_data_valid top.RISCV_Core_interface.core_inst.core_rsp_data_d top.RISCV_Core_interface.core_inst.sched_rs2_addr top.RISCV_Core_interface.core_inst.clock top.RISCV_Core_interface.core_inst.MEM_ISSUE_WAYS top.RISCV_Core_interface.core_inst.store_ready top.RISCV_Core_interface.core_inst.rf_commit_pc top.RISCV_Core_interface.core_inst.retire_ptr top.RISCV_Core_interface.core_inst.sched_rs1_data top.RISCV_Core_interface.core_inst.rf_rd_data top.RISCV_Core_interface.core_inst.writeback_pkts top.RISCV_Core_interface.core_inst.core_req_re_d top.RISCV_Core_interface.core_inst.halted top.RISCV_Core_interface.core_inst.core_rsp_data top.RISCV_Core_interface.core_inst.rf_rd top.RISCV_Core_interface.core_inst.core_req_stall_mem_d top.RISCV_Core_interface.core_inst.rf_commit_pkts top.RISCV_Core_interface.core_inst.rf_rs1 top.RISCV_Core_interface.core_inst.rf_rs2 top.RISCV_Core_interface.core_inst.rf_rs1_data top.RISCV_Core_interface.core_inst.ADDRESS_SIZE top.RISCV_Core_interface.core_inst.mem_rs2_addr top.RISCV_Core_interface.core_inst.core_req_cancel top.RISCV_Core_interface.core_inst.sched_read_rf top.RISCV_Core_interface.core_inst.mem_rs1_data top.RISCV_Core_interface.core_inst.core_req_store_mask_d top.RISCV_Core_interface.core_inst.store_id top.RISCV_Core_interface.core_inst.RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.issue_pkts top.RISCV_Core_interface.core_inst.WRITEBACK_PORTS top.RISCV_Core_interface.core_inst.dris_entries top.RISCV_Core_interface.core_inst.reset_n top.RISCV_Core_interface.core_inst.rf_commit_insn top.RISCV_Core_interface.core_inst.mem_read_rf top.RISCV_Core_interface.core_inst.core_req_ctrl_signals_d top.RISCV_Core_interface.core_inst.sched_rs1_addr top.RISCV_Core_interface.core_inst.flush_mask top.RISCV_Core_interface.core_inst.core_rsp_addr_d top.RISCV_Core_interface.core_inst.core_req_cancel_d top.RISCV_Core_interface.core_inst.core_rsp_excpt top.RISCV_Core_interface.core_inst.core_rsp_excpt_d top.RISCV_Core_interface.core_inst.mem_issue_pkts top.RISCV_Core_interface.core_inst.core_rsp_addr top.RISCV_Core_interface.core_inst.oldest_branch_id top.RISCV_Core_interface.core_inst.d_granted top.RISCV_Core_interface.core_inst.core_req_addr_d top.RISCV_Core_interface.core_inst.sched_rs2_data top.RISCV_Core_interface.core_inst.core_req_re top.RISCV_Core_interface.core_inst.core_rsp_id_d top.RISCV_Core_interface.core_inst.FETCH_WORDS top.RISCV_Core_interface.core_inst.reg_commits top.RISCV_Core_interface.core_inst.dris_intake_pkts top.RISCV_Core_interface.core_inst.set_dispatched top.RISCV_Core_interface.core_inst.mem_rs1_addr top.RISCV_Core_interface.core_inst.EXEC_UNITS {top.RISCV_Core_interface.core_inst.$unit} top.RISCV_Core_interface.core_inst.update_bus top.RISCV_Core_interface.core_inst.set_dispatched_mem top.RISCV_Core_interface.core_inst.branch_fence_valid top.RISCV_Core_interface.core_inst.core_req_store_data_d top.RISCV_Core_interface.core_inst.core_req_addr top.RISCV_Core_interface.core_inst.trap_id top.RISCV_Core_interface.core_inst.rf_rs2_data }
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

set _session_group_17 dris_1
gui_sg_create "$_session_group_17"
set dris_1 "$_session_group_17"

gui_sg_addsignal -group "$_session_group_17" { top.RISCV_Core_interface.core_inst.dris.ENTRIES top.RISCV_Core_interface.core_inst.dris.locker_1_comb top.RISCV_Core_interface.core_inst.dris.MEMORY_READ_PORTS top.RISCV_Core_interface.core_inst.dris.full_id_tmp top.RISCV_Core_interface.core_inst.dris.clock top.RISCV_Core_interface.core_inst.dris.clear_valid top.RISCV_Core_interface.core_inst.dris.dep1 top.RISCV_Core_interface.core_inst.dris.fetch_group_dep1_valid top.RISCV_Core_interface.core_inst.dris.dep2 top.RISCV_Core_interface.core_inst.dris.dris_entries top.RISCV_Core_interface.core_inst.dris.fetch_pkts top.RISCV_Core_interface.core_inst.dris.set_dispatched top.RISCV_Core_interface.core_inst.dris.FETCH_WAYS top.RISCV_Core_interface.core_inst.dris.reset_n top.RISCV_Core_interface.core_inst.dris.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.dris.locker_2_comb top.RISCV_Core_interface.core_inst.dris.WRITEBACK_PORTS top.RISCV_Core_interface.core_inst.dris.fetch_group_dep2_valid top.RISCV_Core_interface.core_inst.dris.new_ids top.RISCV_Core_interface.core_inst.dris.fetch_ptr top.RISCV_Core_interface.core_inst.dris.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.dris.writeback_pkts top.RISCV_Core_interface.core_inst.dris.dep2_completing_now top.RISCV_Core_interface.core_inst.dris.dep1_completing_now {top.RISCV_Core_interface.core_inst.dris.$unit} top.RISCV_Core_interface.core_inst.dris.EXEC_UNITS }
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

set _session_group_18 ssc_1
gui_sg_create "$_session_group_18"
set ssc_1 "$_session_group_18"

gui_sg_addsignal -group "$_session_group_18" { top.RISCV_Core_interface.core_inst.ssc.trap_pc top.RISCV_Core_interface.core_inst.ssc.d_cache_ready top.RISCV_Core_interface.core_inst.ssc.store_ready top.RISCV_Core_interface.core_inst.ssc.retire_ptr top.RISCV_Core_interface.core_inst.ssc.oldest_branch_id top.RISCV_Core_interface.core_inst.ssc.clock top.RISCV_Core_interface.core_inst.ssc.reg_commits top.RISCV_Core_interface.core_inst.ssc.flush_vector top.RISCV_Core_interface.core_inst.ssc.retire_vector top.RISCV_Core_interface.core_inst.ssc.flush_mask top.RISCV_Core_interface.core_inst.ssc.store_id top.RISCV_Core_interface.core_inst.ssc.dris_entries top.RISCV_Core_interface.core_inst.ssc.trap_valid top.RISCV_Core_interface.core_inst.ssc.reset_n top.RISCV_Core_interface.core_inst.ssc.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.ssc.retire_ready_vector top.RISCV_Core_interface.core_inst.ssc.RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.ssc.entries_checked top.RISCV_Core_interface.core_inst.ssc.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.ssc.branch_fence_valid top.RISCV_Core_interface.core_inst.ssc.REG_RETIRES_PER_CYCLE {top.RISCV_Core_interface.core_inst.ssc.$unit} top.RISCV_Core_interface.core_inst.ssc.MEMORY_RETIRES_PER_CYCLE top.RISCV_Core_interface.core_inst.ssc.trap_id }
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

set _session_group_19 tony_d_1
gui_sg_create "$_session_group_19"
set tony_d_1 "$_session_group_19"

gui_sg_addsignal -group "$_session_group_19" { {top.RISCV_Core_interface.tony_d.unnamed$$_0} top.RISCV_Core_interface.tony_d.core_req_stall_mem top.RISCV_Core_interface.tony_d.POLICY top.RISCV_Core_interface.tony_d.do_evict_writeback top.RISCV_Core_interface.tony_d.core_req_bus_wait_en top.RISCV_Core_interface.tony_d.wr_en top.RISCV_Core_interface.tony_d.cache_store top.RISCV_Core_interface.tony_d.cache_fill_data top.RISCV_Core_interface.tony_d.core_rsp_ready top.RISCV_Core_interface.tony_d.use_latched_addr top.RISCV_Core_interface.tony_d.core_rsp_ctrl_signals top.RISCV_Core_interface.tony_d.latch_old_word_fill top.RISCV_Core_interface.tony_d.stall top.RISCV_Core_interface.tony_d.mem_rsp_good top.RISCV_Core_interface.tony_d.evicted_line top.RISCV_Core_interface.tony_d.old_word_latched top.RISCV_Core_interface.tony_d.mem_rsp_data top.RISCV_Core_interface.tony_d.core_rsp_data_valid top.RISCV_Core_interface.tony_d.do_forward top.RISCV_Core_interface.tony_d.clk top.RISCV_Core_interface.tony_d.fwd_words top.RISCV_Core_interface.tony_d.core_rsp_id top.RISCV_Core_interface.tony_d.cache_fill_valid top.RISCV_Core_interface.tony_d.rsp_words top.RISCV_Core_interface.tony_d.INDEX_BITS top.RISCV_Core_interface.tony_d.wb_pending top.RISCV_Core_interface.tony_d.read_miss top.RISCV_Core_interface.tony_d.read_data top.RISCV_Core_interface.tony_d.core_req_store_data top.RISCV_Core_interface.tony_d.core_req_id_latched top.RISCV_Core_interface.tony_d.core_rsp_data top.RISCV_Core_interface.tony_d.rst_l top.RISCV_Core_interface.tony_d.cache_wr_valid top.RISCV_Core_interface.tony_d.mem_rsp_ready top.RISCV_Core_interface.tony_d.state top.RISCV_Core_interface.tony_d.core_req_id top.RISCV_Core_interface.tony_d.cache_stall top.RISCV_Core_interface.tony_d.ADDRESS_SIZE top.RISCV_Core_interface.tony_d.core_req_store_mask top.RISCV_Core_interface.tony_d.evicted_dirty top.RISCV_Core_interface.tony_d.mem_req_store_data top.RISCV_Core_interface.tony_d.evicted_addr_latched top.RISCV_Core_interface.tony_d.do_fill top.RISCV_Core_interface.tony_d.core_req_cancel top.RISCV_Core_interface.tony_d.WAYS top.RISCV_Core_interface.tony_d.address top.RISCV_Core_interface.tony_d.read_hit top.RISCV_Core_interface.tony_d.latch_old_word_hit top.RISCV_Core_interface.tony_d.is_eviction top.RISCV_Core_interface.tony_d.fwd_pending top.RISCV_Core_interface.tony_d.cancel top.RISCV_Core_interface.tony_d.mem_req_store_mask top.RISCV_Core_interface.tony_d.mem_rsp_addr top.RISCV_Core_interface.tony_d.do_forward_saved top.RISCV_Core_interface.tony_d.BLOCK_OFFSET_BITS top.RISCV_Core_interface.tony_d.mem_bus_request top.RISCV_Core_interface.tony_d.core_req_addr_latched top.RISCV_Core_interface.tony_d.rd_en top.RISCV_Core_interface.tony_d.evicted_line_latched top.RISCV_Core_interface.tony_d.merged_store_word top.RISCV_Core_interface.tony_d.core_req_we top.RISCV_Core_interface.tony_d.wb_beat top.RISCV_Core_interface.tony_d.core_hit_valid top.RISCV_Core_interface.tony_d.core_rsp_excpt top.RISCV_Core_interface.tony_d.WORD_SIZE top.RISCV_Core_interface.tony_d.core_req_store_mask_latched top.RISCV_Core_interface.tony_d.core_rsp_addr top.RISCV_Core_interface.tony_d.cache_issue_read top.RISCV_Core_interface.tony_d.fifo_enable top.RISCV_Core_interface.tony_d.mem_rsp_valid top.RISCV_Core_interface.tony_d.mem_req_addr top.RISCV_Core_interface.tony_d.core_req_ctrl_signals_latched top.RISCV_Core_interface.tony_d.mem_req_data_load_en top.RISCV_Core_interface.tony_d.evicted_addr top.RISCV_Core_interface.tony_d.cache_wr_word top.RISCV_Core_interface.tony_d.core_req_re top.RISCV_Core_interface.tony_d.core_req_store_data_latched top.RISCV_Core_interface.tony_d.FETCH_WORDS top.RISCV_Core_interface.tony_d.ud_en top.RISCV_Core_interface.tony_d.next_state top.RISCV_Core_interface.tony_d.fifo_data top.RISCV_Core_interface.tony_d.core_req_ctrl_signals {top.RISCV_Core_interface.tony_d.$unit} top.RISCV_Core_interface.tony_d.flush top.RISCV_Core_interface.tony_d.BLOCK_SIZE top.RISCV_Core_interface.tony_d.core_req_addr top.RISCV_Core_interface.tony_d.mem_rsp_excpt }
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

set _session_group_20 Group1
gui_sg_create "$_session_group_20"
set Group1 "$_session_group_20"

gui_sg_addsignal -group "$_session_group_20" { top.cycle_count top.commit_pkts }

set _session_group_21 scheduler
gui_sg_create "$_session_group_21"
set scheduler "$_session_group_21"

gui_sg_addsignal -group "$_session_group_21" { top.RISCV_Core_interface.core_inst.scheduler.sel_idx top.RISCV_Core_interface.core_inst.scheduler.issue_count top.RISCV_Core_interface.core_inst.scheduler.retire_ptr top.RISCV_Core_interface.core_inst.scheduler.clock top.RISCV_Core_interface.core_inst.scheduler.rs1_data_intermed top.RISCV_Core_interface.core_inst.scheduler.sel_entries top.RISCV_Core_interface.core_inst.scheduler.sel_valid top.RISCV_Core_interface.core_inst.scheduler.operand_1 top.RISCV_Core_interface.core_inst.scheduler.operand_2 top.RISCV_Core_interface.core_inst.scheduler.dris_entries top.RISCV_Core_interface.core_inst.scheduler.ready_vector top.RISCV_Core_interface.core_inst.scheduler.set_dispatched top.RISCV_Core_interface.core_inst.scheduler.rs2_data top.RISCV_Core_interface.core_inst.scheduler.rs2_addr top.RISCV_Core_interface.core_inst.scheduler.issue_pkts top.RISCV_Core_interface.core_inst.scheduler.read_rf top.RISCV_Core_interface.core_inst.scheduler.reset_n top.RISCV_Core_interface.core_inst.scheduler.REG_FILE_WRITE_PORTS top.RISCV_Core_interface.core_inst.scheduler.ENTRIES_CHECKED top.RISCV_Core_interface.core_inst.scheduler.entries_checked top.RISCV_Core_interface.core_inst.scheduler.rs1_data top.RISCV_Core_interface.core_inst.scheduler.MEMORY_WRITE_PORTS top.RISCV_Core_interface.core_inst.scheduler.operand_source_entries top.RISCV_Core_interface.core_inst.scheduler.rs1_addr {top.RISCV_Core_interface.core_inst.scheduler.$unit} top.RISCV_Core_interface.core_inst.scheduler.EXEC_UNITS }
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.REG_FILE_WRITE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.REG_FILE_WRITE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.ENTRIES_CHECKED}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.ENTRIES_CHECKED}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.MEMORY_WRITE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.MEMORY_WRITE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.EXEC_UNITS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.scheduler.EXEC_UNITS}

set _session_group_22 iiu
gui_sg_create "$_session_group_22"
set iiu "$_session_group_22"

gui_sg_addsignal -group "$_session_group_22" { {top.RISCV_Core_interface.core_inst.iiu.fetch_position_assertion.unnamed$$_0} top.RISCV_Core_interface.core_inst.iiu.shelf_free_count top.RISCV_Core_interface.core_inst.iiu.btb_read_hist_D top.RISCV_Core_interface.core_inst.iiu.next_pc top.RISCV_Core_interface.core_inst.iiu.core_req_stall_mem top.RISCV_Core_interface.core_inst.iiu.mispredict_branch_id top.RISCV_Core_interface.core_inst.iiu.fetch_ptr top.RISCV_Core_interface.core_inst.iiu.trap_valid top.RISCV_Core_interface.core_inst.iiu.dris_full top.RISCV_Core_interface.core_inst.iiu.trap_pc top.RISCV_Core_interface.core_inst.iiu.core_rsp_ready top.RISCV_Core_interface.core_inst.iiu.decoded_instrs_D top.RISCV_Core_interface.core_inst.iiu.perf_mispredict_valid top.RISCV_Core_interface.core_inst.iiu.fetched_instructions_valid_D top.RISCV_Core_interface.core_inst.iiu.pc top.RISCV_Core_interface.core_inst.iiu.core_rsp_data_valid top.RISCV_Core_interface.core_inst.iiu.shelf_in_pkt top.RISCV_Core_interface.core_inst.iiu.clock top.RISCV_Core_interface.core_inst.iiu.retire_ptr top.RISCV_Core_interface.core_inst.iiu.btb_read_hist_F1 top.RISCV_Core_interface.core_inst.iiu.btb_write_ctrl top.RISCV_Core_interface.core_inst.iiu.block_pc_F1 top.RISCV_Core_interface.core_inst.iiu.fetched_instructions_D top.RISCV_Core_interface.core_inst.iiu.core_rsp_data top.RISCV_Core_interface.core_inst.iiu.btb_train top.RISCV_Core_interface.core_inst.iiu.perf_branch_resolved top.RISCV_Core_interface.core_inst.iiu.ADDRESS_SIZE top.RISCV_Core_interface.core_inst.iiu.btb_read_hist top.RISCV_Core_interface.core_inst.iiu.core_req_cancel top.RISCV_Core_interface.core_inst.iiu.NUM_UPDATE_PORTS top.RISCV_Core_interface.core_inst.iiu.perf_stall_shelf_full top.RISCV_Core_interface.core_inst.iiu.shelf_full top.RISCV_Core_interface.core_inst.iiu.btb_best_prediction top.RISCV_Core_interface.core_inst.iiu.mispredict_pc top.RISCV_Core_interface.core_inst.iiu.mispredict_valid top.RISCV_Core_interface.core_inst.iiu.perf_stall_dris_full top.RISCV_Core_interface.core_inst.iiu.perf_stall_pc top.RISCV_Core_interface.core_inst.iiu.dris_entries top.RISCV_Core_interface.core_inst.iiu.perf_shelf_occupancy top.RISCV_Core_interface.core_inst.iiu.BLOCK_OFFSET_BITS top.RISCV_Core_interface.core_inst.iiu.reset_n top.RISCV_Core_interface.core_inst.iiu.issue_fire top.RISCV_Core_interface.core_inst.iiu.shelf_alloc_valid top.RISCV_Core_interface.core_inst.iiu.flush_mask top.RISCV_Core_interface.core_inst.iiu.stall_pc top.RISCV_Core_interface.core_inst.iiu.WPC_BUBBLE top.RISCV_Core_interface.core_inst.iiu.instr_stall top.RISCV_Core_interface.core_inst.iiu.group_count top.RISCV_Core_interface.core_inst.iiu.core_rsp_excpt top.RISCV_Core_interface.core_inst.iiu.perf_branch_mispredicted top.RISCV_Core_interface.core_inst.iiu.btb_pred_pc_block_D top.RISCV_Core_interface.core_inst.iiu.core_rsp_addr top.RISCV_Core_interface.core_inst.iiu.occupancy top.RISCV_Core_interface.core_inst.iiu.slot_valid top.RISCV_Core_interface.core_inst.iiu.oldest_branch_id top.RISCV_Core_interface.core_inst.iiu.btb_pred_pc_block_F1 top.RISCV_Core_interface.core_inst.iiu.block_pc_D top.RISCV_Core_interface.core_inst.iiu.group_is_invalid_pc top.RISCV_Core_interface.core_inst.iiu.btb_pred_pc_block top.RISCV_Core_interface.core_inst.iiu.slot_is_ct top.RISCV_Core_interface.core_inst.iiu.WPC_FLUSH top.RISCV_Core_interface.core_inst.iiu.core_req_re top.RISCV_Core_interface.core_inst.iiu.FETCH_WORDS top.RISCV_Core_interface.core_inst.iiu.dris_intake_pkts {top.RISCV_Core_interface.core_inst.iiu.$unit} top.RISCV_Core_interface.core_inst.iiu.flush top.RISCV_Core_interface.core_inst.iiu.update_bus top.RISCV_Core_interface.core_inst.iiu.BLOCK_SIZE top.RISCV_Core_interface.core_inst.iiu.stall_D top.RISCV_Core_interface.core_inst.iiu.branch_fence_valid top.RISCV_Core_interface.core_inst.iiu.block_pc top.RISCV_Core_interface.core_inst.iiu.core_req_addr top.RISCV_Core_interface.core_inst.iiu.stall_F1 top.RISCV_Core_interface.core_inst.iiu.perf_issue_fire top.RISCV_Core_interface.core_inst.iiu.perf_branch_mispredict_squashed }
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.ADDRESS_SIZE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.ADDRESS_SIZE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.NUM_UPDATE_PORTS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.NUM_UPDATE_PORTS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_OFFSET_BITS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_OFFSET_BITS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.WPC_BUBBLE}
gui_set_radix -radix {unsigned} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.WPC_BUBBLE}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.WPC_FLUSH}
gui_set_radix -radix {unsigned} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.WPC_FLUSH}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.FETCH_WORDS}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.FETCH_WORDS}
gui_set_radix -radix {decimal} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_SIZE}
gui_set_radix -radix {twosComplement} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.BLOCK_SIZE}

set _session_group_23 Group2
gui_sg_create "$_session_group_23"
set Group2 "$_session_group_23"

gui_sg_addsignal -group "$_session_group_23" { top.RISCV_Core_interface.core_inst.iiu.fetched_instructions_valid_F2 top.RISCV_Core_interface.core_inst.iiu.btb_read_hist_F2 top.RISCV_Core_interface.core_inst.iiu.block_pc_F2 top.RISCV_Core_interface.core_inst.iiu.btb_pred_pc_block_F2 top.RISCV_Core_interface.core_inst.iiu.stall_F2 }
gui_set_radix -radix {binary} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.fetched_instructions_valid_F2}
gui_set_radix -radix {unsigned} -signals {Sim:top.RISCV_Core_interface.core_inst.iiu.fetched_instructions_valid_F2}

# Global: Highlighting

# Global: Stack
gui_change_stack_mode -mode list

# Post database loading setting...

# Restore C1 time
gui_set_time -C1_only 60600



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
catch {gui_list_expand -id ${Hier.1} top.RISCV_Core_interface.core_inst}
catch {gui_list_select -id ${Hier.1} {top.RISCV_Core_interface.core_inst.iiu}}
gui_view_scroll -id ${Hier.1} -vertical -set 108
gui_view_scroll -id ${Hier.1} -horizontal -set 0

# Class 'Class.1'
gui_list_set_filter -id ${Class.1} -list { {OVM 1} {VMM 1} {All 1} {Object 1} {UVM 1} {RVM 1} }
gui_list_set_filter -id ${Class.1} -text {*}
gui_change_design -id ${Class.1} -design Sim
# Warning: Class view not found.

# Member 'Member.1'
gui_list_set_filter -id ${Member.1} -list { {InternalMember 0} {RandMember 1} {All 0} {BaseMember 0} {PrivateMember 1} {LibBaseMember 0} {AutomaticMember 1} {VirtualMember 1} {PublicMember 1} {ProtectedMember 1} {OverRiddenMember 0} {InterfaceClassMember 1} {StaticMember 1} }
gui_list_set_filter -id ${Member.1} -text {*}

# Data 'Data.1'
gui_list_set_filter -id ${Data.1} -list { {Buffer 1} {Input 1} {Others 1} {Linkage 1} {Output 1} {LowPower 1} {Parameter 1} {All 1} {Aggregate 1} {LibBaseMember 1} {Event 1} {Assertion 1} {Constant 1} {Interface 1} {BaseMembers 1} {Signal 1} {$unit 1} {Inout 1} {Variable 1} }
gui_list_set_filter -id ${Data.1} -text {*}
gui_list_show_data -id ${Data.1} {top.RISCV_Core_interface.core_inst.iiu}
gui_view_scroll -id ${Data.1} -vertical -set 0
gui_view_scroll -id ${Data.1} -horizontal -set 0
gui_view_scroll -id ${Hier.1} -vertical -set 108
gui_view_scroll -id ${Hier.1} -horizontal -set 0

# Source 'Source.1'
gui_src_value_annotate -id ${Source.1} -switch false
gui_set_env TOGGLE::VALUEANNOTATE 0
gui_open_source -id ${Source.1}  -replace -active {top.RISCV_Core_interface.ifetch_bounds.unnamed$$_1} /afs/ece.cmu.edu/usr/daniello/Private/riscv-metaflow-lightning/tb/ifetch_bounds_check.sv
gui_view_scroll -id ${Source.1} -vertical -set 2985
gui_src_set_reusable -id ${Source.1}

# View 'Wave.1'
gui_wv_sync -id ${Wave.1} -switch false
set groupExD [gui_get_pref_value -category Wave -key exclusiveSG]
gui_set_pref_value -category Wave -key exclusiveSG -value {false}
set origWaveHeight [gui_get_pref_value -category Wave -key waveRowHeight]
gui_list_set_height -id Wave -height 25
set origGroupCreationState [gui_list_create_group_when_add -wave]
gui_list_create_group_when_add -wave -disable
gui_marker_set_ref -id ${Wave.1}  C1
gui_wv_zoom_timerange -id ${Wave.1} 60021 60910
gui_list_add_group -id ${Wave.1} -after {New Group} {core_inst_1}
gui_list_add_group -id ${Wave.1} -after {New Group} {dris_1}
gui_list_add_group -id ${Wave.1} -after {New Group} {ssc_1}
gui_list_add_group -id ${Wave.1} -after {New Group} {tony_d_1}
gui_list_add_group -id ${Wave.1} -after {New Group} {Group1}
gui_list_add_group -id ${Wave.1} -after {New Group} {scheduler}
gui_list_add_group -id ${Wave.1} -after {New Group} {iiu}
gui_list_add_group -id ${Wave.1} -after {New Group} {Group2}
gui_list_collapse -id ${Wave.1} core_inst_1
gui_list_collapse -id ${Wave.1} ssc_1
gui_list_collapse -id ${Wave.1} tony_d_1
gui_list_collapse -id ${Wave.1} scheduler
gui_list_expand -id ${Wave.1} top.RISCV_Core_interface.core_inst.dris.dris_entries
gui_list_expand -id ${Wave.1} {top.RISCV_Core_interface.core_inst.dris.dris_entries[6]}
gui_list_expand -id ${Wave.1} {top.RISCV_Core_interface.core_inst.dris.dris_entries[5]}
gui_list_expand -id ${Wave.1} {top.RISCV_Core_interface.core_inst.dris.dris_entries[5].entry_state}
gui_list_expand -id ${Wave.1} {top.RISCV_Core_interface.core_inst.dris.dris_entries[4]}
gui_list_expand -id ${Wave.1} {top.RISCV_Core_interface.core_inst.dris.dris_entries[4].result}
gui_list_expand -id ${Wave.1} top.commit_pkts
gui_list_expand -id ${Wave.1} {top.commit_pkts[0]}
gui_list_expand -id ${Wave.1} top.RISCV_Core_interface.core_inst.iiu.fetched_instructions_valid_F2
gui_list_expand -id ${Wave.1} top.RISCV_Core_interface.core_inst.iiu.block_pc_F2
gui_list_select -id ${Wave.1} {top.RISCV_Core_interface.core_inst.iiu.fetched_instructions_valid_F2 }
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
gui_list_set_filter -id ${Wave.1} -reset
gui_list_set_insertion_bar  -id ${Wave.1} -group Group2  -item top.RISCV_Core_interface.core_inst.iiu.stall_F2 -position below

gui_marker_move -id ${Wave.1} {C1} 60600
gui_view_scroll -id ${Wave.1} -vertical -set 3191
gui_show_grid -id ${Wave.1} -enable false
# Restore toplevel window zorder
# The toplevel window could be closed if it has no view/pane
if {[gui_exist_window -window ${TopLevel.2}]} {
	gui_set_active_window -window ${TopLevel.2}
	gui_set_active_window -window ${Wave.1}
}
if {[gui_exist_window -window ${TopLevel.1}]} {
	gui_set_active_window -window ${TopLevel.1}
	gui_set_active_window -window ${Source.1}
	gui_set_active_window -window ${HSPane.1}
}
#</Session>

