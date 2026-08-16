/**
 * ifetch_inflight.sv
 *
 * I-side request-stream occupancy monitor (simulation only, `IFETCH_INFLIGHT).
 *
 * Answers one question: is the fetch request stream kept busy, or does it go
 * idle waiting for data to come back?
 *
 * Both cores talk to their I-cache controller over the same handshake, so the
 * same instrument can be hung on both and the numbers compared directly:
 *
 *   accept   core_req_re && core_rsp_ready   -- a request is taken this cycle
 *   response core_rsp_data_valid             -- a request's data comes back
 *   cancel   core_req_cancel                 -- controller is slammed to IDLE,
 *                                              anything in flight is dropped
 *
 * "In flight" = accepted but not yet answered. The controllers are short
 * pipelines (accept at N, probe at N+1, data at the response FIFO head at
 * N+2), so the count is small; the interesting part is how often it is ZERO,
 * because a zero means the front end had nothing outstanding to ask about.
 *
 * The decisive counter is `declined`: cycles where the controller was ready
 * to take a request and the core did not make one. The in-order core ties
 * core_req_re = core_rsp_ready (riscv_core_interface_inorder.sv), so its
 * declined count is 0 by construction -- it always has a next fetch address,
 * because its BTB is indexed by the fetch address itself and produces the
 * next one combinationally. Any core that must wait for returned data to
 * learn where to fetch next will show declined > 0, and that is the cost of
 * putting the predictor after the cache instead of in front of it.
 *
 * Caveat when comparing the two cores: they instantiate different controllers
 * (cache_controller_ref vs cache_controller2) and fetch different widths
 * (1 word vs FETCH_WAYS words per request), so request COUNTS are not
 * comparable as bandwidth. Occupancy and the declined/stalled split are.
 *
 * Output: one summary per core at the end of the run, prefix "I-FETCH
 * INFLIGHT" (greppable).
 */

`default_nettype none

module ifetch_inflight
    #(parameter string CORE_NAME = "core",
      parameter int    MAX_TRACK = 8)     // histogram depth
     (input  logic clk, rst_l,
      input  logic core_req_re,
      input  logic core_rsp_ready,
      input  logic core_rsp_data_valid,
      input  logic core_req_cancel,
      input  logic halted);

`ifdef IFETCH_INFLIGHT

    // No declaration initializers on anything an always_ff writes: VCS counts
    // the initializer as a second procedural driver (Error-[ICPD_INIT]).
    // Everything is cleared in the reset branch instead.
    longint cycles;         // counted while running (post-reset, pre-halt)
    longint n_accept;       // requests taken by the controller
    longint n_response;     // responses returned to the core
    longint n_cancel;       // cancel assertions
    longint n_declined;     // ready && !re  -- core had nothing to ask
    longint n_stalled;      // !ready        -- controller refused
    longint occ_sum;        // sum of in-flight count, for the average
    longint occ_zero;       // cycles with nothing outstanding
    longint occ_hist [MAX_TRACK+1];

    int     inflight;
    int     occ_max;

    logic   accept, response, running;

    // cancel is dominant: cache_controller{2,_ref} force next_state = IDLE on
    // it, so a request presented in the same cycle is not actually taken.
    assign accept   = core_req_re && core_rsp_ready && !core_req_cancel;
    assign response = core_rsp_data_valid;
    assign running  = rst_l && !halted;

    always_ff @(posedge clk, negedge rst_l) begin
        if (!rst_l) begin
            inflight   <= 0;
            occ_max    <= 0;
            cycles     <= 0;
            n_accept   <= 0;
            n_response <= 0;
            n_cancel   <= 0;
            n_declined <= 0;
            n_stalled  <= 0;
            occ_sum    <= 0;
            occ_zero   <= 0;
            for (int i = 0; i <= MAX_TRACK; i++) occ_hist[i] <= 0;
        end
        else begin
            if (running) begin
                cycles  <= cycles + 1;
                occ_sum <= occ_sum + inflight;
                if (inflight == 0) occ_zero <= occ_zero + 1;
                occ_hist[(inflight > MAX_TRACK) ? MAX_TRACK : inflight] <=
                    occ_hist[(inflight > MAX_TRACK) ? MAX_TRACK : inflight] + 1;
                if (inflight > occ_max) occ_max <= inflight;

                if (accept)                            n_accept   <= n_accept + 1;
                if (response)                          n_response <= n_response + 1;
                if (core_req_cancel)                   n_cancel   <= n_cancel + 1;
                if (core_rsp_ready && !core_req_re)    n_declined <= n_declined + 1;
                if (!core_rsp_ready)                   n_stalled  <= n_stalled + 1;
            end

            // Occupancy update. A cancel drops everything in flight: those
            // requests never produce a response, so the counter must be
            // cleared rather than decremented, or it drifts up forever.
            if (core_req_cancel)
                inflight <= 0;
            else if (accept && !response)
                inflight <= inflight + 1;
            else if (response && !accept && inflight > 0)
                inflight <= inflight - 1;
        end
    end

    final begin
        real avg_occ, pct_zero, pct_declined, pct_stalled;

        avg_occ      = (cycles > 0) ? real'(occ_sum)    / real'(cycles) : 0.0;
        pct_zero     = (cycles > 0) ? 100.0 * real'(occ_zero)   / real'(cycles) : 0.0;
        pct_declined = (cycles > 0) ? 100.0 * real'(n_declined) / real'(cycles) : 0.0;
        pct_stalled  = (cycles > 0) ? 100.0 * real'(n_stalled)  / real'(cycles) : 0.0;

        $display("\t\t I-FETCH INFLIGHT (%0s):", CORE_NAME);
        $display("\t cycles counted:           %0d", cycles);
        $display("\t requests accepted:        %0d", n_accept);
        $display("\t responses returned:       %0d", n_response);
        $display("\t cancels:                  %0d", n_cancel);
        $display("\t avg requests in flight:   %0.3f  (max %0d)", avg_occ, occ_max);
        $display("\t cycles with 0 in flight:  %0d  (%0.1f%%)", occ_zero, pct_zero);
        $display("\t ready but no request:     %0d  (%0.1f%%)  <- front end had no address",
                 n_declined, pct_declined);
        $display("\t controller not ready:     %0d  (%0.1f%%)  <- controller backpressure",
                 n_stalled, pct_stalled);
        $display("\t in-flight histogram:");
        for (int i = 0; i <= MAX_TRACK; i++)
            if (occ_hist[i] != 0)
                $display("\t   [%0d]: %0d", i, occ_hist[i]);
    end

`endif /* IFETCH_INFLIGHT */

endmodule : ifetch_inflight

`default_nettype wire
