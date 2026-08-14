/**
 * ifetch_bounds_check.sv
 *
 * I-side fetch address bounds checker (simulation only).
 *
 * Taps the core -> I-cache request seam (core_req_re / core_req_addr) and
 * records every address the core asks the instruction cache for. An address
 * is in bounds if it lands inside one of the program images the testbench
 * actually loaded:
 *
 *   [USER_TEXT_START,   USER_TEXT_START   + sizeof(mem.text.bin))
 *   [KERNEL_TEXT_START, KERNEL_TEXT_START + sizeof(mem.ktext.bin))
 *
 * The image sizes are the same bytes main_memory.sv reads into seg_mem, so
 * this is the address range the test's disassembly covers - anything else is
 * a fetch into the 0xdedede... fill, or into a segment with no code at all.
 *
 * core_req_addr is a word address (the core drives pc[31:2], see
 * InstructionIssueUnit's "core_req_addr = pc_F[2 +: ADDRESS_SIZE]"), so the
 * two low bits are implied and are put back here before the range compare.
 *
 * Out-of-bounds fetches are reported, not fatal, by default: on an OoO core a
 * wrong-path fetch past the end of the program is legal behaviour, and the
 * point of this checker is to measure how much of it happens (it is a prime
 * suspect for Lightning's I$ miss count - see docs/perf-counters.md). Build
 * with `PARAMS='+define+IFETCH_BOUNDS_FATAL'` to stop on the first one; that
 * still leaves a register dump and the record below (the $fatal goes out
 * through $finish, so final blocks run), but make still exits 0 - grep the
 * log rather than testing the exit status, same as the watchdog.
 *
 * Output: a summary per core at the end of the run, the first MAX_REPORTS
 * violations inline (prefix "IFETCH-OOB:", greppable), and the full
 * per-address record - count and first cycle seen - in ifetch_oob.log in the
 * simulation directory.
 */

`include "memory_segments.vh"

`default_nettype none

module ifetch_bounds_check
    #(parameter  int    ADDRESS_SIZE = 30,
      parameter  string CORE_NAME    = "core")
     (input  logic                      clk, rst_l,
      input  logic                      core_req_re,
      input  logic [ADDRESS_SIZE-1:0]   core_req_addr);

`ifdef SIMULATION_18447

    import MemorySegments::USER_TEXT_SEGMENT;
    import MemorySegments::KERNEL_TEXT_SEGMENT;

    localparam int    SEEK_END            = 2;
    localparam string SEGMENT_FILE_PREFIX = "mem";
    localparam string OOB_LOG_FILE        = "ifetch_oob.log";

    // How many violations get printed inline before stdout goes quiet. The
    // per-address record in OOB_LOG_FILE is always complete.
    localparam int    MAX_REPORTS         = 20;

    /*------------------------------------------------------------------------
     * Bounds, taken from the loaded program images at time 0
     *------------------------------------------------------------------------*/

    longint text_lo, text_hi, ktext_lo, ktext_hi;

    /* Size of a segment's image file in bytes, or -1 if it can't be opened.
     * Same $fseek/$ftell idiom main_memory.sv uses to size-check the file. */
    function automatic longint image_bytes(input string extension);
        string path;
        int    fd, size;

        path = {SEGMENT_FILE_PREFIX, extension};
        fd   = $fopen(path, "rb");
        if (fd == 0) begin
            return -1;
        end

        void'($fseek(fd, 0, SEEK_END));
        size = $ftell(fd);
        $fclose(fd);
        return longint'(size);
    endfunction: image_bytes

    initial begin
        longint text_bytes, ktext_bytes;

        text_bytes  = image_bytes(USER_TEXT_SEGMENT.extension);
        ktext_bytes = image_bytes(KERNEL_TEXT_SEGMENT.extension);
        if ((text_bytes < 0) || (ktext_bytes < 0)) begin
            $fatal(1, "IFETCH-BOUNDS: unable to open the program images.");
        end

        text_lo  = USER_TEXT_SEGMENT.base_addr;
        text_hi  = text_lo + text_bytes;
        ktext_lo = KERNEL_TEXT_SEGMENT.base_addr;
        ktext_hi = ktext_lo + ktext_bytes;

        $display("IFETCH-BOUNDS [%0s]: text  [0x%08x, 0x%08x)  %0d bytes",
                CORE_NAME, text_lo, text_hi, text_bytes);
        $display("IFETCH-BOUNDS [%0s]: ktext [0x%08x, 0x%08x)  %0d bytes",
                CORE_NAME, ktext_lo, ktext_hi, ktext_bytes);
    end

    /*------------------------------------------------------------------------
     * Per-request check
     *------------------------------------------------------------------------*/

    longint cycle    = 0;
    longint n_req    = 0;
    longint n_oob    = 0;
    longint n_unkn   = 0;
    longint n_report = 0;
    longint lo_seen  = -1;      // in-bounds fetch footprint, low water mark
    longint hi_seen  = -1;      // ... and high water mark

    // Full record of the out-of-bounds addresses: how often, and when first
    longint oob_count [longint];
    longint oob_first [longint];

    /* Plain always with blocking assignments: this is a checker, nothing in
     * the design reads these counters, and the reads/writes below have to see
     * each other within the cycle. */
    always @(posedge clk) begin: bounds_check
        longint byte_addr;
        logic   in_bounds;

        if (rst_l === 1'b1) begin
            cycle = cycle + 1;

            if (core_req_re === 1'b1) begin
                n_req = n_req + 1;

                if ($isunknown(core_req_addr)) begin
                    n_unkn = n_unkn + 1;
                    if (n_report < MAX_REPORTS) begin
                        n_report = n_report + 1;
                        $display({"IFETCH-OOB [%0s]: cycle %0d: I$ read",
                                " asserted with an unknown address (0x%0x)."},
                                CORE_NAME, cycle, core_req_addr);
                    end
                end else begin
                    // put back the two implied low bits of the word address
                    byte_addr = longint'(core_req_addr) << 2;
                    in_bounds = ((byte_addr >= text_lo)  && (byte_addr < text_hi))
                             || ((byte_addr >= ktext_lo) && (byte_addr < ktext_hi));

                    if (in_bounds) begin
                        if ((lo_seen < 0) || (byte_addr < lo_seen)) begin
                            lo_seen = byte_addr;
                        end
                        if ((hi_seen < 0) || (byte_addr > hi_seen)) begin
                            hi_seen = byte_addr;
                        end
                    end else begin
                        n_oob = n_oob + 1;
                        if (!oob_count.exists(byte_addr)) begin
                            oob_count[byte_addr] = 0;
                            oob_first[byte_addr] = cycle;
                        end
                        oob_count[byte_addr] = oob_count[byte_addr] + 1;

                        if (n_report < MAX_REPORTS) begin
                            n_report = n_report + 1;
                            $display({"IFETCH-OOB [%0s]: cycle %0d: fetch of",
                                    " 0x%08x is outside the program (text",
                                    " [0x%08x, 0x%08x), ktext [0x%08x,",
                                    " 0x%08x))."},
                                    CORE_NAME, cycle, byte_addr,
                                    text_lo, text_hi, ktext_lo, ktext_hi);
                            if (n_report == MAX_REPORTS) begin
                                $display({"IFETCH-OOB [%0s]: further violations",
                                        " suppressed; full record in %0s."},
                                        CORE_NAME, OOB_LOG_FILE);
                            end
                        end

`ifdef IFETCH_BOUNDS_FATAL
                        $fatal(1, {"IFETCH-OOB [%0s]: fetch of 0x%08x is",
                                " outside the program."}, CORE_NAME, byte_addr);
`endif
                    end
                end
            end
        end
    end: bounds_check

    /*------------------------------------------------------------------------
     * Summary
     *------------------------------------------------------------------------*/

    final begin
        int log_fd;

        $display("\t\t I-FETCH BOUNDS (%0s):", CORE_NAME);
        $display("\t I$ read requests:          %0d", n_req);
        $display("\t  in-bounds footprint:      0x%08x .. 0x%08x",
                lo_seen, hi_seen);
        $display("\t  out-of-bounds requests:   %0d  (%0d distinct addresses)",
                n_oob, oob_count.size());
        $display("\t  unknown-address requests: %0d", n_unkn);

        if (n_oob > 0) begin
            log_fd = $fopen(OOB_LOG_FILE, "w");
            if (log_fd == 0) begin
                $display({"\t  (could not open %0s; per-address record",
                        " dropped)"}, OOB_LOG_FILE);
            end else begin
                $fdisplay(log_fd, "# out-of-bounds I-fetch addresses, core %0s",
                        CORE_NAME);
                $fdisplay(log_fd, {"# text [0x%08x, 0x%08x)  ktext [0x%08x,",
                        " 0x%08x)"}, text_lo, text_hi, ktext_lo, ktext_hi);
                $fdisplay(log_fd, "# address     requests  first_cycle");
                foreach (oob_count[addr]) begin
                    $fdisplay(log_fd, "0x%08x  %0d  %0d", addr,
                            oob_count[addr], oob_first[addr]);
                end
                $fclose(log_fd);
                $display("\t  per-address record written to %0s", OOB_LOG_FILE);
            end
        end
    end

`endif /* SIMULATION_18447 */

endmodule: ifetch_bounds_check

`default_nettype wire
