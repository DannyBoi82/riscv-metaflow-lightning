/**
 * commit_verifier.sv
 *
 * Testbench-side consumer of the commit packet stream (the verify-trace
 * flow — see rtl/include/riscv_commit.vh and README "verify-trace").
 *
 * The verifier keeps a shadow architectural register file built purely from
 * the commit packets the core emits at retirement. Packets are applied
 * slot-serialized in program order (slot 0 = oldest), which reconstructs
 * the intermediate architectural states a multi-way-retire regfile never
 * physically holds and makes same-cycle WAW pairs individually visible.
 *
 * Duties:
 *  - With the `+commit_trace` plusarg: print one compact full-state line
 *    per committed instruction to commit_trace.txt — the retiring PC plus
 *    x1..x31 in hex, with a ` #cycle=N time=T` comment the checker strips. An
 *    initial anchor line (reset state, PC = USER_TEXT_START) is printed
 *    so a reset-state mismatch is caught at commit 0.
 *  - With the `+mem_trace` plusarg: print one line per *committed memory op*
 *    (pc, L|S, address, byte mask, lane-aligned data) to mem_trace.txt — the
 *    verify-mem flow, diffed against the reference simulator's `memtrace`
 *    output by scripts/check_mem_trace.py. Cores fill the packet's `mem`
 *    field only in `DEBUG builds, so the file is empty without the define.
 *  - At halt: the end-of-run register dump (stdout + simulation.reg +
 *    simulation.reg2), from the shadow state *including* any commits that
 *    land on the halt edge itself. A run that ends *without* halting (the
 *    watchdog) still gets its dump, from a `final` block, so `make verify`
 *    always has a register state to diff — see the note there.
 *
 * Everything here is print-side only: no simulation time is consumed, so
 * cycle counts and perf counters are unaffected (the cost is wall clock
 * and disk when tracing).
 *
 * Authors:
 *  - 2016 - 2017: Brandon Perez (register dump, from register_file.sv)
 *  - 2026: verify-trace shadow/trace machinery
 **/

// This module is only included when we are running simulation
`ifdef SIMULATION_18447

// RISC-V Includes
`include "riscv_isa.vh"                 // Number of registers and width
`include "riscv_abi.vh"                 // Definition of the SP and GP registers
`include "memory_segments.vh"           // Memory segment addresses
`include "riscv_commit.vh"              // Commit packet definition

// Local Includes
`include "riscv_register_names.vh"      // Names for the RISC-V registers

// Force the compiler to throw an error if any variables are undeclared
`default_nettype none

module commit_verifier
    import RISCV_ISA::XLEN, RISCV_ISA::NUM_REGS;
    import RISCV_Commit::commit_pkt_t, RISCV_Commit::COMMIT_WAYS_MAX;

    (input logic                                clk, rst_l, halted,
     input commit_pkt_t [COMMIT_WAYS_MAX-1:0]   commit_pkts);

    // Import the stack/global pointer registers and the segment addresses
    import RISCV_ABI::SP, RISCV_ABI::GP;
    import MemorySegments::STACK_END, MemorySegments::USER_DATA_START,
           MemorySegments::USER_TEXT_START;

    // Import the names of all the registers
    import RISCV_RegisterNames::*;

    // The file handle number for stdout
    localparam STDOUT = 32'h8000_0002;

    // Architectural reset state: must match tb/register_file.sv's reset
    // (and the refsim's initial state) exactly.
    function automatic logic [NUM_REGS-1:0][XLEN-1:0] reset_state();
        logic [NUM_REGS-1:0][XLEN-1:0] regs;
        regs      = '0;
        regs[SP]  = STACK_END;
        regs[GP]  = USER_DATA_START;
        return regs;
    endfunction: reset_state

    // The shadow architectural register file, and the update value being
    // assembled for the current clock edge (blocking-assigned temp so the
    // halt-edge dump sees same-edge commits).
    logic [NUM_REGS-1:0][XLEN-1:0] shadow, upd;

    // Commit trace file; 0 when tracing is disabled
    int trace_fd = 0;

    // Memory-op trace file (+mem_trace); 0 when tracing is disabled
    int mem_trace_fd = 0;

    /* Set once the end-of-run dump has been written, so the `final` fallback
     * below doesn't dump a second time over a normal halting run. Cleared in
     * reset rather than at declaration: VCS counts a declaration initializer
     * as a second driver and rejects it. */
    logic dumped;

    initial begin : trace_setup
        logic [NUM_REGS-1:0][XLEN-1:0] anchor;
        if ($test$plusargs("commit_trace")) begin
            trace_fd = $fopen("commit_trace.txt", "w");
            /* Anchor line: architectural state before the first commit, so
             * the trace diff is anchored at commit 0. The PC field is the
             * reset PC, where the first instruction will be fetched. */
            anchor = reset_state();
            print_state_line(trace_fd, USER_TEXT_START, anchor, 0, '0);
        end
        /* The memory trace holds memory ops only, so it has no anchor line:
         * line k is the k-th committed load/store, which is exactly how the
         * refsim's memtrace is indexed. */
        if ($test$plusargs("mem_trace")) begin
            mem_trace_fd = $fopen("mem_trace.txt", "w");
        end
    end : trace_setup

    /* The dump normally happens on the halt edge below. This is the fallback
     * for a run that ends some other way — in practice the watchdog killing a
     * core that never reached its halting ecall. Without it there is no
     * simulation.reg at all and `make verify` can only report a missing file;
     * with it you get the architectural state at the cutoff, which is what
     * you actually want to look at. `shadow` (not `upd`) is the state as of
     * the last completed clock edge. The Makefile fails a timed-out run
     * regardless of how that state compares — see `verify`. */
    final begin
        if (trace_fd != 0) begin
            $fclose(trace_fd);
        end
        if (mem_trace_fd != 0) begin
            $fclose(mem_trace_fd);
        end
        if (!dumped) begin
            dump_registers(shadow);
        end
    end

    always_ff @(posedge clk, negedge rst_l) begin
        if (!rst_l) begin
            shadow <= reset_state();
            dumped = 1'b0;
        end
        else begin
            upd = shadow;

            // Apply this edge's commits oldest-first (slot-serialized)
            commit_apply_loop: for (int i = 0; i < COMMIT_WAYS_MAX; i++) begin
                if (commit_pkts[i].valid) begin
                    // rd_addr == 0 means "no architectural register write"
                    if (commit_pkts[i].rd_addr != 5'd0) begin
                        upd[commit_pkts[i].rd_addr] = commit_pkts[i].rd_wdata;
                    end
                    if (trace_fd != 0) begin
                        print_state_line(trace_fd, commit_pkts[i].pc_rdata,
                                upd, top.cycle_count, commit_pkts[i].insn);
                    end
                    if (mem_trace_fd != 0) begin
                        print_mem_line(mem_trace_fd, commit_pkts[i],
                                top.cycle_count);
                    end
                end
            end

            /* When simulation finishes, dump the register state to stdout
             * and file. Uses upd, not shadow: a commit landing on the halt
             * edge itself must be part of the dump. */
            if (halted) begin
                /* Blocking, like upd above: the `final` fallback must see
                 * this before it runs, and it is the only driver. */
                dumped = 1'b1;
                dump_registers(upd);
            end

            shadow <= upd;
        end
    end

    /* Prints one compact commit-trace line: the PC of the retiring
     * instruction, then x1..x31 (x0 elided), all as bare 8-digit hex, then
     * a '#' comment carrying the RTL retire cycle, the simulation time and
     * the instruction word (the trace checker strips '#' comments before
     * diffing — the refsim side has none of them, and the checker reads
     * them back for its divergence report). One line per commit is the only
     * diffed format; pretty-printing is a viewer script over these lines.
     *
     * `cycle` is passed in because top.cycle_count needs a hierarchical
     * reference from the caller; $time does not, and is the same simulation
     * time as the commit being printed. It is what a waveform viewer is
     * indexed by, so the divergence report can be acted on directly rather
     * than converting cycles by hand at the current LTG_CLOCK_HALF_PERIOD. */
    function automatic void print_state_line(int fd, logic [XLEN-1:0] pc,
            const ref logic [NUM_REGS-1:0][XLEN-1:0] regs, input int cycle,
            input logic [XLEN-1:0] insn);

        $fwrite(fd, "%x", pc);
        for (int i = 1; i < NUM_REGS; i++) begin
            $fwrite(fd, " %x", regs[i]);
        end
        $fwrite(fd, " #cycle=%0d time=%0d insn=%x\n", cycle, $time, insn);
    endfunction: print_state_line

    /* Prints one memory-op trace line for a committed instruction that touched
     * memory, and nothing at all for one that did not:
     *
     *     <pc> <L|S> <addr> <mask> <data>   #cycle=N time=T insn=X
     *     004000a4 S 10000000 f 0000002a    #cycle=41 time=4100 insn=00a12023
     *
     * This is the RTL half of verify-mem; the reference simulator's `memtrace`
     * command writes the same five fields (see scripts/check_mem_trace.py,
     * which strips the '#' comment). Ops appear in retirement order, which is
     * program order, so a core that reorders memory *internally* still emits a
     * comparable trace — what the diff catches is a memory op that is missing,
     * extra, out of order, or carrying the wrong address/lanes/data.
     *
     * The packet must not claim to both read and write; that is a core bug,
     * not a trace ambiguity, so flag it rather than silently picking one. */
    function automatic void print_mem_line(int fd, commit_pkt_t pkt,
            input int cycle);

        logic is_load;

        if ((pkt.mem.rmask == 4'd0) && (pkt.mem.wmask == 4'd0)) begin
            return;
        end
        if ((pkt.mem.rmask != 4'd0) && (pkt.mem.wmask != 4'd0)) begin
            $fatal(1, "commit packet at pc %x claims both a read (mask %x) and a write (mask %x)",
                    pkt.pc_rdata, pkt.mem.rmask, pkt.mem.wmask);
        end

        is_load = (pkt.mem.rmask != 4'd0);
        $fwrite(fd, "%x %s %x %x %x #cycle=%0d time=%0d insn=%x\n",
                pkt.pc_rdata,
                is_load ? "L" : "S", pkt.mem.addr,
                is_load ? pkt.mem.rmask : pkt.mem.wmask,
                is_load ? pkt.mem.rdata : pkt.mem.wdata,
                cycle, $time, pkt.insn);
    endfunction: print_mem_line

    // Dumps the end-of-run register state to stdout and the .reg files
    function automatic void dump_registers(
            const ref logic [NUM_REGS-1:0][XLEN-1:0] registers);

        int fd;

        /* Cycle and time are both printed, and are *not* interchangeable:
         * this line used to pass $time under the "Cycle" label, which made a
         * watchdog kill look like it ran 2e9 cycles against a 20M limit. */
        $display("\n18-447 Register File Dump at Cycle %0d (time %0d), Mem Accesses: %0d",
                top.cycle_count, $time, top.mem_access);
        $display("---------------------------------------------\n");
        print_cpu_state(STDOUT, registers);

        fd = $fopen("simulation.reg");
        print_cpu_state(fd, registers);
        $display();
        $fclose(fd);

        fd = $fopen("simulation.reg2");
        $fdisplay(fd, "\n18-447 Register File Dump at Cycle %0d (time %0d), Mem Accesses: %0d",
                top.cycle_count, $time, top.mem_access);
        $fdisplay(fd, "---------------------------------------------\n");
        print_cpu_state(fd, registers);
        $fclose(fd);
    endfunction: dump_registers

    // Prints out the information for a single register to the given file.
    function void print_register(int fd, int i, register_name_t reg_name,
            const ref logic [NUM_REGS-1:0][XLEN-1:0] registers);

        // Format the ABI alias name for the register
        string abi_name, reg_hex_value, reg_uint_value, reg_int_value;
        abi_name = {"(", reg_name.abi_name, ")"};

        /* Format the hex/signed/unsigned views of the register. The hex value
         * is formatted separately because Verilator (<= 5.048 at least) leaks
         * the '-' (left-justify) flag from earlier %-Ns specifiers into a
         * later %x in the same format string, dropping its zero-padding. */
        $sformat(reg_hex_value, "0x%x", registers[i]);
        $sformat(reg_uint_value, "(%0d)", registers[i]);
        $sformat(reg_int_value, "(%0d)", signed'(registers[i]));

        // Print out the register's names and values
        $fdisplay(fd, "%-8s %-8s = %-10s %-12s %-13s", reg_name.isa_name,
                abi_name, reg_hex_value, reg_uint_value, reg_int_value);
    endfunction: print_register

    // Prints the CPU state to the given file.
    function void print_cpu_state(int fd,
            const ref logic [NUM_REGS-1:0][XLEN-1:0] registers);

        /* Print out the instructions fetched and the current pc value. Don't
         * print this to the register dump file. */
        if (fd == STDOUT) begin
            $fdisplay(fd, "Current CPU State and Register Values:");
            $fdisplay(fd, "--------------------------------------");
            $fdisplay(fd, "%-20s = %0d", "Cycle Count",
                    $root.top.cycle_count);
            $fdisplay(fd, "%-20s = 0x%x\n", "Program Counter (PC)",
                    $root.top.pc);
        end

        // Display the header for the table of register values
        $fdisplay(fd, "%-8s %-8s   %-10s %-12s %-13s", "ISA Name", "ABI Name",
                "Hex Value", "Uint Value", "Int Value");
        /* The explicit %s keeps Verilator from printing the replication as a
         * decimal number; VCS treats the bare replication as a format string. */
        $fdisplay(fd, "%s", {(8+1+8+3+10+1+12+1+13){"-"}});

        // Display the register and its values for each register
        foreach (REGISTER_NAMES[i]) begin
            print_register(fd, i, REGISTER_NAMES[i], registers);
        end
    endfunction: print_cpu_state

endmodule: commit_verifier

`endif /* SIMULATION_18447 */
