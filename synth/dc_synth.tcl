# dc_synth.tcl
#
# Lightning — Synopsys Design Compiler synthesis script.
#
# Synthesizes the design rooted at riscv_core_timing (the synthesis-only
# wrapper in rtl/mem/riscv_core_timing.sv, which hangs a fake main memory off
# the core's memory port), applies the SRAM timing/area/power model, and
# writes the timing, power, and area reports plus the gate-level netlist.
#
# Driven by `make synth`; see the Synthesis section of the Makefile.
#
# Originally the 18-447 course script (adapted in turn from 18-341 project 4);
# reworked for this repo's rtl/ layout, CORE selection, and config.vh knobs.
#
# Authors:
#   - 2016 - 2017: Brandon Perez
#   - 2025: Varun Rajesh and Dane Engman
#   - 2026: Henry Mayer
#   - 2026: ported off the 447 scaffolding (447src/447include/src -> rtl/)

#-------------------------------------------------------------------------------
# Command Line Arguments and Sanity Checks
#-------------------------------------------------------------------------------

# This script takes the top-level project directory, and optionally the clock
# period, the core to build, and extra Verilog defines, as arguments.
set usage "Usage: dc_shell-xg-t -f synth/dc_synth.tcl -x 'set project_dir <path>; "
append usage "\[set clock_period <period>\]; \[set core <lightning|inorder>\]; "
append usage "\[set defines {NAME=VALUE ...}\]'"

if {![info exists project_dir]} {
    puts "Error: Project directory not specified."
    puts $usage
    exit 1
}

set postprocess_error "######################################################################\n## Post Process Failed. Check synth/postprocess.py vs. the reports. ##\n######################################################################"

# Convert the project directory to an absolute path, and set the paths for the
# source file directories.
set project_dir [exec readlink -m $project_dir]
set rtl_dir $project_dir/rtl
set include_dir $rtl_dir/include

# Directory compile order, mirroring RTL_DIR_ORDER in the Makefile: packages
# must be analyzed before the modules that import them, and the 0/1 filename
# prefixes keep the package files first within each directory.
set src_dir_order [list rtl/core rtl/ooo rtl/mem]

# Files under tb/ that are real hardware rather than testbench, and so have to
# be synthesized. Listed one by one on purpose: the rest of tb/ is wrapped in
# `ifdef SIMULATION_18447 and would analyze to nothing, but only the module
# *bodies* are guarded -- the headers above the `ifdef are always parsed, and
# simulation-only types in them (e.g. `parameter string` in
# ifetch_bounds_check.sv) are hard errors in DC. Handing DC the whole
# directory made synthesis hostage to testbench edits; adding a design module
# to tb/ and forgetting this list fails loudly at link instead.
#
# register_file.sv is the architectural register file the cores instantiate
# (LightningCore's `rf`, riscv_core's regfile). It lived in 447src/ before the
# port, which the old script analyzed for the same reason.
set tb_src [list $project_dir/tb/register_file.sv]

set postprocess_script $project_dir/synth/postprocess.py

# Check that the project and source file directories exist
if {![file isdirectory $project_dir]} {
    puts "Error: $project_dir: Project directory does not exist."
    exit 1
} elseif {![file isdirectory $rtl_dir]} {
    puts "Error: $project_dir: Project directory does not have an rtl directory."
    exit 1
} elseif {![file isdirectory $include_dir]} {
    puts "Error: $project_dir: Project directory does not have an rtl/include directory."
    exit 1
} elseif {![file exists $postprocess_script]} {
    puts "Error: $postprocess_script: Post-processing script does not exist."
    exit 1
}

# Which riscv_core_interface implementation to synthesize. Both rtl/mem
# files define that module name, so exactly one may be analyzed. Mirrors CORE
# in config.mk.
if {![info exists core]} {
    set core "lightning"
}
switch -- $core {
    "lightning" {
        set excluded_src [list $rtl_dir/mem/riscv_core_interface_inorder.sv]
    }
    "inorder" {
        set excluded_src [list $rtl_dir/mem/riscv_core_interface.sv]
    }
    default {
        puts "Error: Invalid core '$core'. Must be one of {lightning, inorder}."
        puts $usage
        exit 1
    }
}

# If the user didn't specify a clock period, use the default. Otherwise, check
# that the clock period is valid.
if {![info exists clock_period]} {
    set clock_period 10.0
} elseif {![string is double $clock_period] || $clock_period <= 0} {
    puts -nonewline "Error: Clock period '$clock_period' is not a positive "
    puts "double value."
    exit 1
}

# Extra Verilog defines (the synthesis-side equivalent of PARAMS), e.g.
# {LTG_DRIS_ENTRIES=32 LTG_DCACHE_INDEX_BITS=6}. See rtl/include/config.vh.
# Note that SIMULATION_18447 is deliberately never defined here: it is what
# selects the behavioral SRAMs and compiles out riscv_core_timing.
if {![info exists defines]} {
    set defines [list]
}

#-------------------------------------------------------------------------------
# Setup and Variables
#-------------------------------------------------------------------------------

# Collect the source files in the same order the Makefile compiles them: per
# directory in src_dir_order, sorted within the directory.
set src [list]
foreach subdir $src_dir_order {
    set dir $project_dir/$subdir
    if {![file isdirectory $dir]} {
        puts "Error: $dir: Source directory does not exist."
        exit 1
    }
    set found [exec find -L $dir -type f "(" -name "*.sv" -o -name "*.v" ")"]
    foreach file [lsort [split [string trim $found] "\n"]] {
        if {[lsearch -exact $excluded_src $file] == -1} {
            lappend src $file
        }
    }
}

if {[llength $src] == 0} {
    puts "Error: $project_dir: No Verilog sources found."
    exit 1
}

# The hardware that lives under tb/ (see tb_src above).
foreach file $tb_src {
    if {![file exists $file]} {
        puts "Error: $file: Design source under tb/ does not exist."
        exit 1
    }
    lappend src $file
}

# Set the libraries used to implement the design
set target_library /afs/ece/class/ece447/tools/synopsys/typical.db
set link_library /afs/ece/class/ece447/tools/synopsys/typical.db

# Set the top module and add every source subdirectory to the search path, so
# that `include of the headers in rtl/include resolves.
set top_module riscv_core_timing
set src_subdirs [lsort [split [string trim \
    [exec find -L $rtl_dir $project_dir/tb -type d]] "\n"]]
set search_path [concat $search_path $src_subdirs]

# Setup the compiler for parallel compilation with the max number of threads.
set cores [exec getconf _NPROCESSORS_ONLN]
set threads [expr min($cores, 16)]
set_host_options -max_cores $threads

# Define a library where our synthesized design files will be stored
define_design_lib WORK -path "./work"

#-------------------------------------------------------------------------------
# Design Synthesis
#-------------------------------------------------------------------------------

puts "Info: Synthesizing core '$core' at a ${clock_period}ns clock period."
if {[llength $defines] > 0} {
    puts "Info: Extra defines: $defines"
}

# Syntax check the source files, and create library objects for the files for
# design synthesis.
if {[llength $defines] > 0} {
    set analyze_ok [analyze -format sverilog -lib WORK -define $defines $src]
} else {
    set analyze_ok [analyze -format sverilog -lib WORK $src]
}
if {!$analyze_ok} {
    exit 1
}

# Synthesize the design into a technology-independent design, and link the
# design to library components and references to other modules in the design.
if {![elaborate $top_module -lib WORK]} {
    exit 1
}

# Even though the elaborate command already performs linking, it succeeds even
# if linking fails, so link is run again to check for this case.
if {![link]} {
    exit 1
}

#-------------------------------------------------------------------------------
# Design and Optimization Constraints
#-------------------------------------------------------------------------------

# Set the design to optimize as the top module. All modules in the hierarchy
# below will also be optimized.
current_design $top_module

# Create a clock for the design, and set its period. This can be changed to a
# lower value to force the synthesis tool to work harder to optimize the design.
create_clock -period $clock_period clk

# Model a semi-realistic delay for main memory by setting a delay on the input
# ports to the top module.
set real_inputs [remove_from_collection [all_inputs] clk]
set_input_delay -clock clk 0.0 $real_inputs
set_output_delay -clock clk 0.0 [all_outputs]

# Set the maximum allowed combinational delay to be the clock period.
set_max_delay $clock_period [all_outputs]

# For some reason, DC very heavily prefers using ripple-carry adders when
# implementing addition, even if the design isn't meeting timing. Thus, we force
# the compiler not to use them, so it will instead use carry-lookahead adders.
set_dont_use standard.sldb/DW01_addsub/rpl
set_dont_use standard.sldb/DW01_add/rpl
set_dont_use standard.sldb/DW01_sub/rpl

# Add clock slew and skew to force the tool to explore different FFs
set_clock_transition  0.04 [get_clocks clk]
set_clock_latency -source 0.05 [get_clocks clk]

# Add don't touches to the memory interfaces to avoid the tool destroying the
# timing model (rtl/mem/riscv_core_timing.sv).
set fmd_insts [get_cells -hierarchical -quiet \
    -filter {ref_name =~ *fake_memory_delay*}]
if {[sizeof_collection $fmd_insts] == 0} {
    puts "Warning: No fake_memory_delay instance found; the reported critical"
    puts "         path will not include any main-memory delay."
} else {
    foreach_in_collection inst $fmd_insts {
        set_dont_touch $inst
    }
}

#-------------------------------------------------------------------------------
# SRAM Constraints
#-------------------------------------------------------------------------------

# This is potentially inefficient since we technically synth twice
# We can instead report power and area on the sram designs and then
# post process the data ourselves instead of synth twice

# Get SRAM timing designs (rtl/mem/sram_synthesis.sv). Fetch designs quietly
# to avoid errors if none exist.
set sram_designs [get_designs -quiet *sram_timing_model*]
set active_sram_designs ""

echo "" > sram.rpt
if {[sizeof_collection $sram_designs] > 0} {
    foreach design_name [get_attribute $sram_designs name] {
        set sram_instances [get_cells -hierarchical -quiet \
            -filter "ref_name =~ *$design_name*"]
        if {[sizeof_collection $sram_instances] > 0} {
            puts "Info: Module $design_name is instantiated. Processing..."

            # Make current design
            current_design $design_name
            create_clock -period $clock_period clk

            # Get SRAM parameters
            set design_parameters [get_attribute $design_name hdl_parameters]

            # Extract NUM_WORDS (only the numeric value)
            regexp {NUM_WORDS\s*=>\s*(\d+)} $design_parameters match num_words

            # Extract WORD_WIDTH (only the numeric value)
            regexp {WORD_WIDTH\s*=>\s*(\d+)} $design_parameters match word_width

            regexp {NUM_R_PORTS\s*=>\s*(\d+)} $design_parameters match num_r_ports
            regexp {NUM_W_PORTS\s*=>\s*(\d+)} $design_parameters match num_w_ports
            regexp {NUM_RW_PORTS\s*=>\s*(\d+)} $design_parameters match num_rw_ports

            # Output the extracted numeric values
            puts "NUM_WORDS: $num_words"
            puts "WORD_WIDTH: $word_width"

            set total_ports [expr {$num_r_ports + $num_w_ports + $num_rw_ports}]

            # Compute timing requirements
            set read_addr_to_read_data_delay [expr {(double($num_words) * double($word_width) * 500.0) / (1024.0 * 8.0)}]
            set write_data_setup [expr {(double($num_words) * double($word_width) * 250.0) / (1024.0 * 8.0)}]
            set write_enable_setup [expr {(double($num_words) * double($word_width) * 250.0) / (1024.0 * 8.0)}]
            set write_address_setup [expr {(double($num_words) * double($word_width) * 440.0) / (1024.0 * 8.0)}]

            # Apply port penalty
            if {$total_ports == 1} {
                set read_addr_to_read_data_delay [expr {$read_addr_to_read_data_delay * 1.25}]
                set write_data_setup [expr {$write_data_setup * 1.25}]
                set write_enable_setup [expr {$write_enable_setup * 1.25}]
                set write_address_setup [expr {$write_address_setup * 1.25}]
            }

            # Convert to buffer counts
            set read_addr_to_read_data_delay [expr {int(ceil(max($read_addr_to_read_data_delay / 69.0, 2)))}]
            set write_data_setup [expr {int(ceil(max($write_data_setup / 69.0, 1)))}]
            set write_enable_setup [expr {int(ceil(max($write_enable_setup / 69.0, 1)))}]
            set write_address_setup [expr {int(ceil(max($write_address_setup / 69.0, 2)))}]

            puts "num_read_addr_to_read_data_buffers: $read_addr_to_read_data_delay"
            puts "num_write_data_buffers: $write_data_setup"
            puts "num_write_en_buffers: $write_enable_setup"
            puts "num_write_addr_buffers: $write_address_setup"

            set buffer_type "typical/BUFX20"

            # Constrain read_addr -> read_data path
            insert_buffer -no_of_cells $read_addr_to_read_data_delay -new_cell_names sram_delay [get_ports read_addr*] $buffer_type

            # Constrain write_data timing path
            insert_buffer -no_of_cells $write_data_setup -new_cell_names sram_delay  [get_ports write_data\[*\]] $buffer_type

            # Constrain write_en timing path
            insert_buffer -no_of_cells $write_enable_setup -new_cell_names sram_delay  [get_ports we] $buffer_type

            # Constrain write_addr timing path
            insert_buffer -no_of_cells $write_address_setup -new_cell_names sram_delay  [get_ports write_addr\[*\]] $buffer_type

            if {![compile -map_effort high -area_effort high -incremental_mapping]} {
                exit 1
            }

            echo "Design: $design_name; Words: $num_words; Word_Width: $word_width; R_Ports: $num_r_ports; W_Ports: $num_w_ports; RW_Ports: $num_rw_ports" >> sram.rpt
            report_area -nosplit >> sram.rpt

            # Keep a track of the ones we actually touched
            if {$active_sram_designs == ""} {
                set active_sram_designs [get_designs $design_name]
            } else {
                set active_sram_designs [add_to_collection $active_sram_designs [get_designs $design_name]]
            }

            current_design $top_module
        } else {
            puts "Info: Module $design_name loaded but unused. Skipping..."
        }
    }
}

# Ensure active SRAM designs don't get modified
if {$active_sram_designs != ""} {
    set_dont_touch $active_sram_designs
}

# Restore top level design
current_design $top_module

#-------------------------------------------------------------------------------
# Design Optimization
#-------------------------------------------------------------------------------

# Conduct a two pass optimisation of the design to force the tool to generate a correct
# overall netlist and then focus on specific optimisations. Area effort is set to low but during
# my testing this is not a significant concern (the area results generated are within a reasonable margin
# of a higher area effort and the timing is better)

# Add clock uncertainty scaled with the clock period so that changes in clock period don't make massive changes
# to the compiler's effort
set pass1_uncertainty [expr 0.15 * $clock_period]
set_clock_uncertainty $pass1_uncertainty [get_clocks clk];

if {![compile -map_effort medium -area_effort low  \
        -incremental_mapping]} {
    exit 1
}


set pass2_uncertainty [expr 0.3 * $clock_period]
set_clock_uncertainty $pass2_uncertainty [get_clocks clk];

# Optimise hot paths in the design. Boundary optimisation allows the tool to make optimisations between
# different modules, but this is less effective than optimisations on a single module
if {![compile -map_effort high -area_effort low -boundary_optimization -incremental_mapping]} {
    exit 1
}

#-------------------------------------------------------------------------------
# Report Generation
#-------------------------------------------------------------------------------

# Restore clock to have less uncertainty to relax timing constraint
set final_uncertainty [expr 0.01 * $clock_period]
set_clock_uncertainty $final_uncertainty [get_clocks clk];


# Check the final optimized design for any inconsistencies and report them.
if {![check_design]} {
    exit 1
}

# Only loop over the SRAMs that we confirmed were active, and use
# sizeof_collection instead of llength to prevent script failures.
if {$active_sram_designs != ""} {
    foreach design_name [get_attribute $active_sram_designs name] {
        set cells_of_design [get_cells -hierarchical -quiet -filter "ref_name == $design_name"]
        set count [sizeof_collection $cells_of_design]

        echo "Design: $design_name; Count: $count" >> sram.rpt
    }
}


# Report the timing of the design.
report_timing > timing_riscv_core.rpt

report_area -nosplit > original_area_riscv_core.rpt
report_power -nosplit > original_power_riscv_core.rpt

report_area > area_riscv_core.rpt
report_power > power_riscv_core.rpt

report_power -hierarchy -nosplit > power_riscv_core_hier.rpt

if {[catch {exec python3 $postprocess_script sram.rpt original_area_riscv_core.rpt original_power_riscv_core.rpt power_riscv_core_hier.rpt timing_riscv_core.rpt} result]} {
    puts $postprocess_error
    puts "\nPython Script Error Details:\n$result\n"
    exit 1
}


file delete original_area_riscv_core.rpt original_power_riscv_core.rpt power_riscv_core_hier.rpt

# Tries to find pipeline stages.
# The hierarchy is riscv_core_timing/RISCV_Core/core_inst/{design}, so the
# unit of interest is the next path component (e.g.
# RISCV_Core/core_inst/dris for the DRIS on the lightning core, or
# RISCV_Core/core_inst/<stage> on the in-order core).
proc extract_stage {pin_name} {
    if {[regexp {core_inst/([^/]+)/} $pin_name -> stage]} {
        return $stage
    } elseif {[regexp {^RISCV_Core/([^/]+)/} $pin_name -> unit]} {
        return $unit
    } else {
        return UNKNOWN
    }
}

# Save current stdout so we can restore it later
set original_stdout stdout

# Redirect all output to the report file
redirect -file top_paths.rpt {
    puts "Top unique pipeline-stage timing paths"
    puts "======================================"
    puts ""

    # this is quite high but keep in mind that every single pin of a register is a separate path
    set worst_paths [get_timing_paths -max_paths 10000]
    set seen_stage_pairs {}
    set count 0
    set max_paths 10

    # Hashamps moment
    foreach_in_collection p $worst_paths {

        # Get raw pin names
        set sp_pin [get_object_name [get_attribute $p startpoint]]
        set ep_pin [get_object_name [get_attribute $p endpoint]]

        # Extract architectural stages
        set launch_stage  [extract_stage $sp_pin]
        set capture_stage [extract_stage $ep_pin]

        set stage_pair "$launch_stage -> $capture_stage"

        # is this a new stage pair?
        if {[lsearch $seen_stage_pairs $stage_pair] == -1} {
            lappend seen_stage_pairs $stage_pair

            puts "Pipeline stage transition: $stage_pair"
            report_timing \
                -from [get_attribute $p startpoint] \
                -to   [get_attribute $p endpoint]

            puts ""
            incr count
        }

        if {$count >= $max_paths} {
            break
        }
    }

    puts "======================================"
    puts "Reported $count unique pipeline-stage paths"
}

# Restore normal stdout
set stdout $original_stdout


# Output the netlist of the final synthesized design in verilog format.
write -hierarchy -format verilog -output netlist_riscv_core.sv
exit 0
