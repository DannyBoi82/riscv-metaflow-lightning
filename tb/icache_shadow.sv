/**
 * icache_shadow.sv
 *
 * Idealized I-cache residency model (simulation only, `ICACHE_SHADOW).
 *
 * Answers one question: of the I$ misses a core takes, how many were
 * *avoidable* — i.e. the block had already been fetched from memory and
 * should still have been sitting in the cache?
 *
 * The model is a cache with the same geometry and the same replacement
 * policy as the real one, with a single difference: it NEVER drops a fill.
 * It is fed the real cache's own probe stream (so wrong-path fetches are
 * included), and every probe is classified:
 *
 *   shadow  real   meaning
 *   ------  -----  ----------------------------------------------------
 *   miss    miss   cold or conflict — unavoidable, this is the floor
 *   HIT     MISS   PHANTOM: the line should have been resident. Something
 *                  installed it and then lost it (see docs/perf-counters.md
 *                  section 4.1: the core_req_cancel refill path).
 *   hit     hit    fine
 *   miss    hit    "pessimistic" — see the self-check note below
 *
 * Self-check. The real cache only ever installs a block on a real miss, and
 * a real miss is either a shadow miss (shadow installs it too) or a shadow
 * hit (shadow already has it). So the real cache's contents are a subset of
 * the shadow's *until the first eviction*, and while nothing is evicted a
 * "pessimistic" classification is structurally impossible — a non-zero count
 * there means this model is misaligned and nothing else it reports can be
 * trusted. Once blocks start being evicted the two LRU states legitimately
 * diverge (the real cache installs less, so it ages differently) and a small
 * pessimistic count is expected rather than alarming. The summary prints the
 * shadow eviction count next to it so it is obvious which regime a run is in.
 * fibi's 13-block footprint in a 64-block cache is the clean regime, which is
 * why it is the workload to iterate on.
 *
 * Probe stream. `probe_addr` is cache3's `read_addr`, i.e. the address of the
 * request cache3 currently has in flight (`curr_inflight.req_addr`), which is
 * exactly the address being tag-compared on any cycle read_hit/read_miss is
 * asserted. It is a word address, like everything else at this seam.
 *
 * De-duplication. read_miss is a level, not a pulse: cache3.sv's
 * "if (stall && !ud_en) next_inflight = curr_inflight;" freezes the request
 * in the LOAD state while the other cache owns the memory bus, so read_miss
 * re-asserts every stalled cycle. (This is also why the PERF "I$ misses"
 * counter, which increments per read_miss cycle, overstates the miss count.)
 * A strobe is therefore ignored when the previous cycle asserted read_miss on
 * the same address. Two genuinely distinct misses cannot land back-to-back on
 * one address — after a miss cache3 moves to MISS_UPDATE — so the rule drops
 * held levels and nothing else. Repeated *hits* on one address are left alone.
 *
 * Output: a summary per core at the end of the run (prefix "I$ SHADOW",
 * greppable), and the full per-block record in icache_shadow.log in the
 * simulation directory. `PLUSARGS='+icache_trace'` additionally writes one
 * line per classified probe to icache_probe.log.
 */

`default_nettype none

module icache_shadow
    #(parameter  int    ADDRESS_SIZE      = 30,
      parameter  int    INDEX_BITS        = 5,
      parameter  int    BLOCK_OFFSET_BITS = 2,
      parameter  int    WAYS              = 2,
      parameter  string CORE_NAME         = "core")
     (input  logic                    clk, rst_l,
      input  logic [ADDRESS_SIZE-1:0] probe_addr,
      input  logic                    read_hit,
      input  logic                    read_miss,
      input  logic                    is_eviction,
      input  logic                    core_req_cancel);

`ifdef ICACHE_SHADOW

    localparam int    SETS           = 2 ** INDEX_BITS;
    localparam int    BLOCKS         = SETS * WAYS;
    localparam string SHADOW_LOG     = "icache_shadow.log";
    localparam string PROBE_LOG      = "icache_probe.log";

    // How many offending blocks get listed inline. The per-block record in
    // SHADOW_LOG is always complete.
    localparam int    MAX_OFFENDERS  = 10;

    /*------------------------------------------------------------------------
     * Shadow cache state
     *------------------------------------------------------------------------*/

    logic   sh_valid [SETS][WAYS];
    longint sh_tag   [SETS][WAYS];
    longint sh_age   [SETS][WAYS];   // true LRU: larger is more recent
    longint lru_clock = 0;

    /*------------------------------------------------------------------------
     * Counters
     *------------------------------------------------------------------------*/

    longint cycle          = 0;
    longint n_probe        = 0;      // distinct probes (held levels collapsed)
    longint n_real_miss    = 0;      // distinct real miss events
    longint n_real_hit     = 0;
    longint n_shadow_miss  = 0;      // the unavoidable floor
    longint n_phantom      = 0;      // shadow hit, real miss
    longint n_pessimistic  = 0;      // shadow miss, real hit (see header)
    longint n_shadow_evict = 0;
    longint n_real_evict   = 0;      // is_eviction pulses, for reference
    longint n_cancel       = 0;
    longint n_miss_cycles  = 0;      // every read_miss cycle: the PERF figure
    longint n_miss_killed  = 0;      // misses discarded before a fill was asked for

    // Per-block record, keyed by block byte address
    longint blk_probe   [longint];
    longint blk_rmiss   [longint];
    longint blk_smiss   [longint];
    longint blk_phantom [longint];
    longint blk_first   [longint];   // first cycle the block was probed

    // Edge/level detection carried across cycles
    logic                    miss_prev   = 1'b0;
    logic                    cancel_prev = 1'b0;
    logic [ADDRESS_SIZE-1:0] addr_prev   = '0;

    int probe_fd = 0;

    initial begin
        for (int s = 0; s < SETS; s++) begin
            for (int w = 0; w < WAYS; w++) begin
                sh_valid[s][w] = 1'b0;
                sh_tag  [s][w] = 0;
                sh_age  [s][w] = 0;
            end
        end

        if ($test$plusargs("icache_trace")) begin
            probe_fd = $fopen(PROBE_LOG, "w");
            if (probe_fd == 0) begin
                $display({"I$ SHADOW [%0s]: could not open %0s; per-probe",
                        " trace disabled."}, CORE_NAME, PROBE_LOG);
            end else begin
                $fdisplay(probe_fd, "# per-probe I$ trace, core %0s", CORE_NAME);
                $fdisplay(probe_fd, "# cycle  block  set  real  shadow  class");
            end
        end
    end

    /*------------------------------------------------------------------------
     * Shadow lookup / install
     *
     * Returns 1 on a shadow hit and refreshes the way's age. On a miss the
     * block is installed unconditionally — that is the whole point of the
     * model — evicting the least recently used way once the set is full.
     *------------------------------------------------------------------------*/

    function automatic logic shadow_access(input int set, input longint tag);
        int     victim;
        longint oldest;

        lru_clock = lru_clock + 1;

        for (int w = 0; w < WAYS; w++) begin
            if (sh_valid[set][w] && (sh_tag[set][w] == tag)) begin
                sh_age[set][w] = lru_clock;
                return 1'b1;
            end
        end

        // Miss: prefer an empty way, else evict the least recently used one.
        victim = 0;
        oldest = -1;
        for (int w = 0; w < WAYS; w++) begin
            if (!sh_valid[set][w]) begin
                victim = w;
                oldest = -1;
                break;
            end
            if ((oldest < 0) || (sh_age[set][w] < oldest)) begin
                oldest = sh_age[set][w];
                victim = w;
            end
        end

        if (sh_valid[set][victim]) begin
            n_shadow_evict = n_shadow_evict + 1;
        end

        sh_valid[set][victim] = 1'b1;
        sh_tag  [set][victim] = tag;
        sh_age  [set][victim] = lru_clock;
        return 1'b0;
    endfunction: shadow_access

    /*------------------------------------------------------------------------
     * Per-probe classification
     *
     * Plain always with blocking assignments: this is a checker, nothing in
     * the design reads any of it, and the reads/writes below have to see each
     * other within the cycle (same idiom as tb/ifetch_bounds_check.sv).
     *------------------------------------------------------------------------*/

    always @(posedge clk) begin: classify
        logic   probe, held, real_miss, shadow_hit;
        longint blk, tag, byte_addr;
        int     set;
        string  verdict;

        if (rst_l === 1'b1) begin
            cycle = cycle + 1;

            if ((core_req_cancel === 1'b1) && !cancel_prev) begin
                n_cancel = n_cancel + 1;
            end
            if (is_eviction === 1'b1) begin
                n_real_evict = n_real_evict + 1;
            end
            if (read_miss === 1'b1) begin
                n_miss_cycles = n_miss_cycles + 1;
            end

            probe = (read_hit === 1'b1) || (read_miss === 1'b1);

            // A read_miss level held across a bus-arbitration stall is the
            // same probe re-asserting, not a new one.
            held  = probe && miss_prev && (probe_addr === addr_prev);

            if (probe && !held && !$isunknown(probe_addr)) begin
                real_miss = (read_miss === 1'b1);

                blk       = longint'(probe_addr) >> BLOCK_OFFSET_BITS;
                set       = int'(blk % SETS);
                tag       = blk / SETS;
                byte_addr = blk << (BLOCK_OFFSET_BITS + 2);

                shadow_hit = shadow_access(set, tag);

                n_probe = n_probe + 1;
                if (real_miss) n_real_miss = n_real_miss + 1;
                else           n_real_hit  = n_real_hit  + 1;
                if (!shadow_hit) n_shadow_miss = n_shadow_miss + 1;

                if (!blk_probe.exists(byte_addr)) begin
                    blk_probe  [byte_addr] = 0;
                    blk_rmiss  [byte_addr] = 0;
                    blk_smiss  [byte_addr] = 0;
                    blk_phantom[byte_addr] = 0;
                    blk_first  [byte_addr] = cycle;
                end
                blk_probe[byte_addr] = blk_probe[byte_addr] + 1;
                if (real_miss)   blk_rmiss[byte_addr] = blk_rmiss[byte_addr] + 1;
                if (!shadow_hit) blk_smiss[byte_addr] = blk_smiss[byte_addr] + 1;

                if (shadow_hit && real_miss) begin
                    n_phantom            = n_phantom + 1;
                    blk_phantom[byte_addr] = blk_phantom[byte_addr] + 1;
                    verdict              = "PHANTOM";
                end
                else if (!shadow_hit && !real_miss) begin
                    n_pessimistic = n_pessimistic + 1;
                    verdict       = "pessimistic";
                end
                else if (real_miss) verdict = "cold";
                else                verdict = "hit";

                /* A miss resolving on the same cycle as a cancel never gets to
                 * ask memory for the line: the controller's cancel override
                 * clears mem_bus_request and drops the FSM to IDLE, so the
                 * probe is discarded with no fill in flight to lose. */
                if (real_miss && (core_req_cancel === 1'b1)) begin
                    n_miss_killed = n_miss_killed + 1;
                end

                if (probe_fd != 0) begin
                    $fdisplay(probe_fd, "%0d 0x%08x %0d %0s %0s %0s%0s",
                            cycle, byte_addr, set,
                            real_miss  ? "MISS" : "hit",
                            shadow_hit ? "hit"  : "MISS",
                            verdict,
                            (core_req_cancel === 1'b1) ? " cancel" : "");
                end
            end

            miss_prev   = (read_miss === 1'b1);
            cancel_prev = (core_req_cancel === 1'b1);
            addr_prev   = probe_addr;
        end
    end: classify

    /*------------------------------------------------------------------------
     * Summary
     *------------------------------------------------------------------------*/

    final begin
        int     log_fd;
        int     listed;
        longint best_addr, best_val;
        longint remaining [longint];   // working copy for the top-N selection

        $display("\t\t I$ SHADOW (%0s):", CORE_NAME);
        $display("\t distinct probes:          %0d", n_probe);
        $display("\t  real miss events:        %0d", n_real_miss);
        $display("\t  real miss cycles:        %0d   (what PERF 'I$ misses' counts)",
                n_miss_cycles);
        $display("\t  ideal (shadow) misses:   %0d   (the unavoidable floor)",
                n_shadow_miss);
        $display("\t  PHANTOM misses:          %0d   (resident in the model, missed for real)",
                n_phantom);
        $display("\t  pessimistic:             %0d   (self-check: must be 0 while nothing is evicted)",
                n_pessimistic);
        $display("\t  shadow evictions:        %0d   (real: %0d)",
                n_shadow_evict, n_real_evict);
        $display("\t  cancel pulses:           %0d", n_cancel);
        $display({"\t  misses killed by a cancel: %0d   (discarded before a",
                " fill was requested)"}, n_miss_killed);
        $display("\t  distinct blocks touched: %0d   (cache holds %0d)",
                blk_probe.size(), BLOCKS);

        if (n_phantom > 0) begin
            $display("\t  worst blocks (block, probes, real misses, phantom):");
            foreach (blk_phantom[a]) remaining[a] = blk_phantom[a];
            listed = 0;
            while (listed < MAX_OFFENDERS) begin
                best_addr = -1;
                best_val  = 0;
                foreach (remaining[a]) begin
                    if (remaining[a] > best_val) begin
                        best_val  = remaining[a];
                        best_addr = a;
                    end
                end
                if (best_addr < 0) break;
                $display("\t   0x%08x  %0d  %0d  %0d", best_addr,
                        blk_probe[best_addr], blk_rmiss[best_addr],
                        blk_phantom[best_addr]);
                remaining.delete(best_addr);
                listed = listed + 1;
            end
        end

        if (probe_fd != 0) begin
            $fclose(probe_fd);
            $display("\t  per-probe trace written to %0s", PROBE_LOG);
        end

        log_fd = $fopen(SHADOW_LOG, "w");
        if (log_fd == 0) begin
            $display("\t  (could not open %0s; per-block record dropped)",
                    SHADOW_LOG);
        end else begin
            $fdisplay(log_fd, "# I$ shadow per-block record, core %0s", CORE_NAME);
            $fdisplay(log_fd, {"# geometry: %0d sets x %0d ways x %0d words",
                    " = %0d blocks"}, SETS, WAYS, 2 ** BLOCK_OFFSET_BITS, BLOCKS);
            $fdisplay(log_fd, {"# totals: probes=%0d real_miss=%0d miss_cycles=%0d",
                    " shadow_miss=%0d phantom=%0d pessimistic=%0d cancels=%0d"},
                    n_probe, n_real_miss, n_miss_cycles, n_shadow_miss,
                    n_phantom, n_pessimistic, n_cancel);
            $fdisplay(log_fd, {"# block       probes  real_miss  shadow_miss",
                    "  phantom  first_cycle"});
            foreach (blk_probe[a]) begin
                $fdisplay(log_fd, "0x%08x  %0d  %0d  %0d  %0d  %0d", a,
                        blk_probe[a], blk_rmiss[a], blk_smiss[a],
                        blk_phantom[a], blk_first[a]);
            end
            $fclose(log_fd);
            $display("\t  per-block record written to %0s", SHADOW_LOG);
        end
    end

`endif /* ICACHE_SHADOW */

endmodule: icache_shadow

`default_nettype wire
